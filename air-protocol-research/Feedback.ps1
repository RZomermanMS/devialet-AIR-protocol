Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'Common.ps1')
function Get-AirHexString([byte[]]$Bytes,[int]$Offset,[int]$Count) { Assert-AirRange $Bytes $Offset $Count; (($Bytes[$Offset..($Offset+$Count-1)] | ForEach-Object { $_.ToString('X2') }) -join '') }
function ConvertFrom-AirDf([byte[]]$Bytes) {
    # All integers big-endian. Layout: 0..1 magic 4466; 4..5 session(candidate); 10..17 u64 Field10; 18..25 u64 Field18; 37..38 count; 39+4i start,end u16; last 2 CRC16-CCITT(init FFFF).
    if ($null -eq $Bytes) { throw 'Df: null payload' }
    if ($Bytes.Length -lt 41) { throw 'Df: truncated (<41 bytes)' }
    if ($Bytes[0] -ne 0x44 -or $Bytes[1] -ne 0x66) { throw 'Df: bad magic' }
    if ((($Bytes.Length - 41) % 4) -ne 0) { throw 'Df: length is not 41+4n' }
    $n = ($Bytes.Length - 41) / 4
    $count = [int](Get-AirUIntBE $Bytes 37 2)
    if ($count -ne $n) { throw "Df: count $count does not match length-derived $n" }
    $crcStored = [UInt16](Get-AirUIntBE $Bytes ($Bytes.Length-2) 2)
    $crcCalc = Get-AirCrc16 $Bytes ($Bytes.Length-2)
    if ($crcStored -ne $crcCalc) { throw ('Df: CRC mismatch stored {0:X4} computed {1:X4}' -f $crcStored,$crcCalc) }
    $iv = @(); $ordered = $true; $prevEnd = -1
    for ($i=0; $i -lt $n; $i++) {
        $s = [int](Get-AirUIntBE $Bytes (39+4*$i) 2); $e = [int](Get-AirUIntBE $Bytes (41+4*$i) 2)
        if ($s -gt $e -or $s -le $prevEnd) { $ordered = $false }
        $prevEnd = $e
        $iv += [pscustomobject]@{ Start=$s; End=$e }
    }
    [pscustomobject]@{
        Length=$Bytes.Length; Magic='4466'; Session4_5=[int](Get-AirUIntBE $Bytes 4 2); Session5_6=[int](Get-AirUIntBE $Bytes 5 2)
        Field10_U64BE=[UInt64](Get-AirUIntBE $Bytes 10 8); Field18_U64BE=[UInt64](Get-AirUIntBE $Bytes 18 8)
        Count=$count; Intervals=$iv; IntervalsOrdered=$ordered; Crc=('{0:X4}' -f $crcStored); CrcValid=$true
    }
}
function ConvertFrom-AirDa([byte[]]$Bytes) {
    if ($null -eq $Bytes) { throw 'Da: null payload' }
    if ($Bytes.Length -ne 345) { throw 'Da: length must be 345' }
    if ($Bytes[0] -ne 0x44 -or $Bytes[1] -ne 0x61) { throw 'Da: bad magic' }
    $crcStored = [UInt16](Get-AirUIntBE $Bytes 343 2); $crcCalc = Get-AirCrc16 $Bytes 343
    if ($crcStored -ne $crcCalc) { throw ('Da: CRC mismatch stored {0:X4} computed {1:X4}' -f $crcStored,$crcCalc) }
    $ascii = [Text.Encoding]::ASCII
    $name = $ascii.GetString($Bytes,19,32).TrimEnd([char]0,' ')
    $inputs = @()
    for ($i=0; $i -lt 15; $i++) {
        $o = 52 + 17*$i
        $inputs += [pscustomobject]@{ Index=$i; Flag=$Bytes[$o]; Label=$ascii.GetString($Bytes,$o+1,16).TrimEnd([char]0,' ') }
    }
    $b310 = [int]$Bytes[310]
    [pscustomobject]@{
        Length=345; Name=$name; Inputs=$inputs; PowerOn=(($Bytes[307] -band 0x80) -ne 0); Muted=(($Bytes[308] -band 2) -ne 0)
        Channel=(($Bytes[308] -band 0x3C) -shr 2); VolumeRaw=$b310; Volume=(($b310 - 195) / 2.0); Crc=('{0:X4}' -f $crcStored); CrcValid=$true
    }
}
function Get-AirDfDmCorrelation($DfRows, $DmUnique) {
    # Hypothesis only: interval values are block indexes (counter/200). Bounded to at most 200 Df and all Dm blocks.
    $dfs = @($DfRows | Where-Object { $_.D.Count -gt 0 } | Select-Object -First 200)
    if ($dfs.Count -eq 0 -or @($DmUnique).Count -eq 0) { return [pscustomobject]@{ Confidence='none'; Note='insufficient data' } }
    $first = @{}; foreach ($m in $DmUnique) { if ($m.Block -gt 0 -and ($m.Counter % $m.Block) -eq 0) { $first[[int]($m.Counter / $m.Block)] = $m.FirstSeen } }
    $startOk = 0; $inSeen = 0; $inAfter = 0; $inNever = 0; $gapSeen = 0; $gapTot = 0; $f10ahead = 0
    foreach ($x in $dfs) {
        $d = $x.D
        if ($d.Intervals[0].Start -eq ([int]($d.Field18_U64BE / 200) + 1)) { $startOk++ }
        if ((($d.Field10_U64BE + 1) / 200) -ge $d.Intervals[-1].End) { $f10ahead++ }
        $inI = @{}
        foreach ($iv in $d.Intervals) { for ($k=$iv.Start; $k -le $iv.End; $k++) { $inI[$k]=1
            if ($first.ContainsKey($k)) { if ($first[$k] -le $x.T) { $inSeen++ } else { $inAfter++ } } else { $inNever++ } } }
        for ($k=$d.Intervals[0].Start; $k -le $d.Intervals[-1].End; $k++) { if (-not $inI.ContainsKey($k)) { $gapTot++; if ($first.ContainsKey($k) -and $first[$k] -le $x.T) { $gapSeen++ } } }
    }
    $inTot = $inSeen + $inAfter + $inNever
    [pscustomobject]@{
        Confidence='low'; DfConsidered=$dfs.Count
        FirstIntervalStartEqualsField18Div200Plus1=$startOk
        Field10Plus1Div200AtLeastLastEnd=$f10ahead
        IntervalBlocksSeenBeforeDf=$inSeen; IntervalBlocksSeenOnlyAfterDf=$inAfter; IntervalBlocksNeverSeen=$inNever
        PSeenBeforeGivenInInterval=$(if ($inTot) { [math]::Round($inSeen / $inTot, 3) } else { $null })
        PSeenBeforeGivenInGap=$(if ($gapTot) { [math]::Round($gapSeen / $gapTot, 3) } else { $null })
        Note='Structural invariant (first start = Field18/200+1) is exact; relation of intervals to observed Dm blocks is weak/ambiguous (capture may be incomplete). Meaning unproven.'
    }
}
function Get-AirFeedbackAnalysis($Packets) {
    $Packets = @($Packets); $dfRows=@(); $daRows=@(); $dm=@{}; $rej=@(); $other=0
    foreach ($p in $Packets) {
        $hex = [string]$p.PayloadHex
        if ($hex.Length -lt 4) { $other++; continue }
        $tag = $hex.Substring(0,4).ToUpperInvariant()
        try {
            if ($tag -eq '4466') { $b = ConvertFrom-AirHex $hex; $dfRows += [pscustomobject]@{ T=[UInt64]$p.TimestampRaw; D=(ConvertFrom-AirDf $b) } }
            elseif ($tag -eq '4461') { $b = ConvertFrom-AirHex $hex; $daRows += [pscustomobject]@{ T=[UInt64]$p.TimestampRaw; D=(ConvertFrom-AirDa $b) } }
            elseif ($tag -eq '446D') {
                $b = ConvertFrom-AirHex $hex
                if ($b.Length -ge 22) { $ck=[string](Get-AirUIntBE $b 12 8); $tt=[UInt64]$p.TimestampRaw; if ($dm.ContainsKey($ck) -and $dm[$ck].FirstSeen -le $tt) { $tt=$dm[$ck].FirstSeen }; $dm[$ck] = [pscustomobject]@{ FirstSeen=$tt; Counter=[UInt64](Get-AirUIntBE $b 12 8); Block=[int](Get-AirUIntBE $b 20 2); Session5_6=[int](Get-AirUIntBE $b 5 2); Session4_5=[int](Get-AirUIntBE $b 4 2) } }
            } else { $other++ }
        } catch { $rej += [pscustomobject]@{ Kind=$tag; Error=$_.Exception.Message } }
    }
    $dmU = @($dm.Values | Sort-Object Counter)
    $res = [ordered]@{
        DfValid=$dfRows.Count; DaValid=$daRows.Count; Rejected=$rej.Count; RejectedDetail=$rej; OtherPackets=$other; DmUniqueCounters=$dmU.Count
        DfIntervalsAllOrdered=(@($dfRows | Where-Object { -not $_.D.IntervalsOrdered }).Count -eq 0)
    }
    if ($dfRows.Count) {
        $res.DfLengthDistinct = @($dfRows | ForEach-Object { $_.D.Length } | Sort-Object -Unique).Count
        $res.DfMaxIntervals = ($dfRows | ForEach-Object { $_.D.Count } | Measure-Object -Maximum).Maximum
        $res.DfSession4_5Values = @($dfRows | ForEach-Object { '{0:X4}' -f $_.D.Session4_5 } | Sort-Object -Unique)
        $f10 = @($dfRows | ForEach-Object { $_.D.Field10_U64BE }); $mono=$true; for($i=1;$i -lt $f10.Count;$i++){ if($f10[$i] -lt $f10[$i-1]){$mono=$false} }
        $res.DfField10Monotonic = $mono; $res.DfField10Min=($f10|Measure-Object -Minimum).Minimum; $res.DfField10Max=($f10|Measure-Object -Maximum).Maximum
        $f18 = @($dfRows | ForEach-Object { $_.D.Field18_U64BE } | Sort-Object -Unique); $res.DfField18Distinct = $f18.Count
        $res.DfField18Values = @($f18 | Select-Object -First 5)
    }
    if ($dmU.Count) {
        $res.DmSession5_6Values = @($dmU | ForEach-Object { '{0:X4}' -f $_.Session5_6 } | Sort-Object -Unique)
        $res.DmSession4_5Values = @($dmU | ForEach-Object { '{0:X4}' -f $_.Session4_5 } | Sort-Object -Unique)
        $res.DmCounterMin=$dmU[0].Counter; $res.DmCounterMax=$dmU[-1].Counter
        $res.DmBlockValues = @($dmU | ForEach-Object { $_.Block } | Sort-Object -Unique)
    }
    if ($daRows.Count) {
        $last = $daRows[-1].D
        $res.DaLast = [pscustomobject]@{ Name=$last.Name; PowerOn=$last.PowerOn; Muted=$last.Muted; Channel=$last.Channel; Volume=$last.Volume; InputLabels=@($last.Inputs | ForEach-Object { $_.Label }) }
        $res.DaDistinctStates = @($daRows | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.D.PowerOn,$_.D.Muted,$_.D.Channel,$_.D.VolumeRaw } | Sort-Object -Unique).Count
    }
    $res.Correlation = Get-AirDfDmCorrelation $dfRows $dmU
    $res.Dfs = $dfRows; $res.DmSorted = $dmU
    [pscustomobject]$res
}

