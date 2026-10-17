$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
function Update-Crc([byte[]]$Bytes) {
    $end = $Bytes.Length - 128
    $crc = 65535
    for ($i = 0; $i -lt $end - 2; $i++) {
        $crc = $crc -bxor ([int]$Bytes[$i] -shl 8)
        for ($k = 0; $k -lt 8; $k++) {
            if ($crc -band 32768) { $crc = (($crc -shl 1) -bxor 0x1021) -band 65535 }
            else { $crc = ($crc -shl 1) -band 65535 }
        }
    }
    $Bytes[$end - 2] = $crc -shr 8
    $Bytes[$end - 1] = $crc -band 255
}
function Convert-Hex([byte[]]$Bytes) { [BitConverter]::ToString($Bytes).Replace('-', '') }
function New-Packet([int]$First, [int]$Delta, [int]$Width) {
    $size = 7 + [int][Math]::Ceiling(199 * $Width / 8.0)
    $b = New-Object byte[] (22 + 2 * $size + 2 + 128)
    $b[0] = 0x44
    $b[1] = 0x6D
    $b[21] = 200
    for ($channel = 0; $channel -lt 2; $channel++) {
        $start = 22 + $channel * $size
        $value = $First -band 0xFFFFFF
        $b[$start] = ($value -shr 16) -band 255
        $b[$start + 1] = ($value -shr 8) -band 255
        $b[$start + 2] = $value -band 255
        $b[$start + 5] = $Width
        $b[$start + 6] = $Width
        $bit = ($start + 7) * 8
        $code = ($Delta -shl 1) -bxor ($Delta -shr 31)
        for ($frame = 1; $frame -lt 200; $frame++) {
            for ($k = $Width - 1; $k -ge 0; $k--) {
                $index = [int][Math]::Floor($bit / 8)
                $b[$index] = $b[$index] -bor ((($code -shr $k) -band 1) -shl (7 - ($bit % 8)))
                $bit++
            }
        }
    }
    Update-Crc $b
    return ,$b
}
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    & $Body
    $results.Add([pscustomobject]@{ Name = $Name; Passed = $true })
}
function Reject([byte[]]$Bytes) {
    $rejected = $false
    try { [void][ReferenceBlockDecoder]::Decode((Convert-Hex $Bytes)) }
    catch [System.Management.Automation.MethodInvocationException] {
        if ($_.Exception.InnerException -isnot [IO.InvalidDataException]) { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'Malformed packet accepted.' }
}
Check 'Signed 24-bit seed, zero-width constant channel' {
    $p = [ReferenceBlockDecoder]::Decode((Convert-Hex (New-Packet -123456 0 0)))
    if ($p.Left.Count -ne 200 -or @($p.Left | Where-Object { $_ -ne -123456 }).Count) { throw 'Constant decode mismatch.' }
}
foreach ($delta in @(-4, -1, 0, 1, 3)) {
    $d = $delta
    Check "MSB-first three-bit zigzag delta $d" {
        $p = [ReferenceBlockDecoder]::Decode((Convert-Hex (New-Packet 1000 $d 3)))
        for ($i = 0; $i -lt 200; $i++) {
            if ($p.Left[$i] -ne 1000 + $i * $d -or $p.Right[$i] -ne $p.Left[$i]) { throw 'Delta reconstruction mismatch.' }
        }
    }
}
Check 'Reject changed audio byte with stale CRC' {
    $b = New-Packet 0 1 3
    $b[32] = $b[32] -bxor 1
    Reject $b
}
Check 'Reject nonzero trailing padding' {
    $b = New-Packet 0 0 0
    $b[-1] = 1
    Reject $b
}
Check 'Reject unsupported width configuration with valid CRC' {
    $b = New-Packet 0 1 3
    $b[27] = 4
    Update-Crc $b
    Reject $b
}
Check 'Reject unsupported frame count with valid CRC' {
    $b = New-Packet 0 0 0
    $b[21] = 199
    Update-Crc $b
    Reject $b
}
Check 'Reject nonzero unused packed bit with valid CRC' {
    $b = New-Packet 0 1 3
    $size = 7 + [int][Math]::Ceiling(199 * 3 / 8.0)
    $b[22 + $size - 1] = $b[22 + $size - 1] -bor 1
    Update-Crc $b
    Reject $b
}
Check 'Reject signed 24-bit reconstruction overflow' { Reject (New-Packet 8388607 1 3) }
Check 'Reject truncation' {
    $b = New-Packet 0 0 0
    Reject ([byte[]]$b[0..100])
}
Check 'Independent widths and ordered blocks in synthetic asymmetric stereo' {
    $first = New-Packet 100 1 3
    $second = New-Packet -37 0 0
    $size = 7 + [int][Math]::Ceiling(199 * 3 / 8.0)
    $b = New-Object byte[] (22 + $size + 7 + 2 + 128)
    [Array]::Copy($first, 0, $b, 0, 22 + $size)
    [Array]::Copy($second, 22, $b, 22 + $size, 7)
    Update-Crc $b
    $p = [ReferenceBlockDecoder]::Decode((Convert-Hex $b))
    if ($p.Width -ne 3 -or $p.RightWidth -ne 0) { throw 'Independent channel widths not preserved.' }
    for ($i = 0; $i -lt 200; $i++) {
        if ($p.Left[$i] -ne 100 + $i -or $p.Right[$i] -ne -37) { throw 'Asymmetric block boundary mismatch.' }
    }
}
Check 'Stereo ramp capture decodes every packet including unequal widths' {
    $ramp = @(Import-Csv -LiteralPath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-stereo-ramp-packets.csv' |
        Where-Object { $_.PayloadHex.StartsWith('446D') })
    if ($ramp.Count -ne 372) { throw 'Unexpected stereo ramp count.' }
    $unequal = 0
    foreach ($row in $ramp) {
        $p = [ReferenceBlockDecoder]::Decode($row.PayloadHex)
        if ($p.Width -ne $p.RightWidth) { $unequal++ }
    }
    if ($unequal -ne 1) { throw 'Unequal-width capture evidence changed.' }
}
Check 'Nonperiodic alignment validated on both channels and separate windows' {
    $result = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stereo-ramp-comparison.json') -Raw | ConvertFrom-Json
    foreach ($match in $result.Matches) {
        if ($match.Block -eq $match.SourceChannel) {
            if ($match.Lag -ne 1376 -or $match.Correlation -lt 0.9999) { throw 'Expected channel correspondence failed.' }
        } elseif ($match.Correlation -gt 0.2) { throw 'Unexpected cross-channel correlation.' }
    }
    foreach ($validation in $result.Validation) {
        $best = $validation.Neighbors | Sort-Object Correlation -Descending | Select-Object -First 1
        if ($best.Lag -ne 1376 -or $validation.HeldOutFrames -lt 40000) { throw 'Held-out alignment failed.' }
        foreach ($window in $validation.HalfWindowBest) {
            if ($window.Lag -ne 1376 -or $window.Correlation -lt 0.9999) { throw 'Time-window alignment failed.' }
        }
    }
    if ($result.VolumeBytes.Count -ne 1) { throw 'Amplifier volume changed within ramp capture.' }
}
$rows = Import-Csv -LiteralPath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-reference-wifi-packets.csv'
Check 'All 561 captured Dm packets decode and have matching channels' {
    $audio = @($rows | Where-Object { $_.PayloadHex.StartsWith('446D') })
    if ($audio.Count -ne 561) { throw 'Unexpected capture size.' }
    foreach ($row in $audio) {
        $p = [ReferenceBlockDecoder]::Decode($row.PayloadHex)
        for ($i = 0; $i -lt 200; $i++) {
            if ($p.Left[$i] -ne $p.Right[$i]) { throw 'Channel mismatch.' }
        }
    }
}
$measured = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reference-decoded-results.json') -Raw | ConvertFrom-Json
Check 'Earlier capture independently accepts widths 0, 9, 10 and 11 across 951 packets' {
    $earlier = @(Import-Csv -LiteralPath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-session-packets.csv' |
        Where-Object { $_.PayloadHex.StartsWith('446D') })
    if ($earlier.Count -ne 951) { throw 'Earlier capture size changed.' }
    $widths = @($earlier | ForEach-Object { ([ReferenceBlockDecoder]::Decode($_.PayloadHex)).Width } |
        Sort-Object -Unique)
    if (($widths -join ',') -ne '0,9,10,11') { throw 'Unexpected independently decoded widths.' }
}
Check 'Persisted recovered tone measures 997 Hz with R-squared above 0.998' {
    if ($measured.BestFrequencyHz -ne 997 -or $measured.ToneFitRSquared -lt 0.998 -or
        $measured.UniqueDecodedFrames -ne 112200) { throw 'Recovered-signal validation failed.' }
}
[pscustomobject]@{ Passed = $results.Count; Failed = 0; Tests = @($results.ToArray()) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'reference-decoder-tests.json')
$results | Format-Table -AutoSize
