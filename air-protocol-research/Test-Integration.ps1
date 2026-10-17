param([string]$InputRoot='C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Capture.ps1')
. (Join-Path $PSScriptRoot 'Audio.ps1')
. (Join-Path $PSScriptRoot 'Feedback.ps1')
$tests=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[scriptblock]$Body) {
    try { if (-not (& $Body)) { throw 'Assertion false' }; $tests.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=$null}) }
    catch { $tests.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message}) }
}
function Reject([scriptblock]$Body) { try { & $Body | Out-Null } catch { return $true }; return $false }
function Block([UInt32]$Type,[byte[]]$Body) {
    $size=12+$Body.Length
    if ($size%4) { throw 'Test block alignment' }
    return ,([BitConverter]::GetBytes($Type)+[BitConverter]::GetBytes([UInt32]$size)+$Body+[BitConverter]::GetBytes([UInt32]$size))
}
$files=@('air-session-wifi.pcapng','air-session.pcapng','air-session-packets.csv','air-session-test.log','air-baseline-wifi.pcapng','air-baseline.pcapng','air-baseline-packets.csv','inspect-air-capture.ps1')
$hashes=@{}
foreach ($file in $files) { $hashes[$file]=(Get-FileHash -LiteralPath (Join-Path $InputRoot $file)).Hash }
Check 'CRC standard vector' { (Get-AirCrc16 ([Text.Encoding]::ASCII.GetBytes('123456789')) 9) -eq 0x29B1 }
Check 'Big-endian UInt64 maximum' { (Get-AirUIntBE ([byte[]](255,255,255,255,255,255,255,255)) 0 8) -eq [UInt64]::MaxValue }
Check 'Big-endian range rejects' { Reject { Get-AirUIntBE ([byte[]](0,1)) 1 2 } }
Check 'Hex rejects odd/nonhex' { (Reject { ConvertFrom-AirHex 'ABC' }) -and (Reject { ConvertFrom-AirHex 'GG' }) }
$frame=New-Object byte[] 64
$frame[0]=8; $llc=[byte[]](170,170,3,0,0,0,8,0); [Array]::Copy($llc,0,$frame,24,8)
$frame[32]=0x45; $frame[35]=32; $frame[41]=17
$frame[44]=172; $frame[45]=16; $frame[46]=5; $frame[47]=252
$frame[48]=172; $frame[49]=16; $frame[50]=5; $frame[51]=90
$frame[52]=0xB1; $frame[53]=0x90; $frame[54]=0xB1; $frame[55]=0x8F; $frame[57]=12
$frame[60]=0x44; $frame[61]=0x6D; $frame[62]=1; $frame[63]=2
Check 'Synthetic WiFi IPv4 UDP payload exact' { $p=ConvertFrom-AirWifiFrame $frame 123 1; $p.PayloadHex -eq '446D0102' -and $p.SourcePort -eq 45456 -and $p.TimestampRaw -eq 123 }
Check 'Truncated WiFi rejects' { Reject { ConvertFrom-AirWifiFrame (New-Object byte[] 10) 1 1 } }
Check 'Bad LLC rejects' { $f=$frame.Clone(); $f[24]=0; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'Bad IPv4 IHL rejects' { $f=$frame.Clone(); $f[32]=0x44; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'IPv4 fragment rejects' { $f=$frame.Clone(); $f[38]=0x20; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'Bad UDP length rejects' { $f=$frame.Clone(); $f[57]=13; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'Encrypted WiFi rejects' { $f=$frame.Clone(); $f[1]=0x40; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'Fragmented WiFi rejects' { $f=$frame.Clone(); $f[22]=1; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'WiFi A-MSDU rejects' { $f=$frame.Clone(); $f[0]=136; $f[24]=128; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
Check 'WiFi null data subtype rejects' { $f=$frame.Clone(); $f[0]=72; Reject { ConvertFrom-AirWifiFrame $f 1 1 } }
$fixture=Join-Path $PSScriptRoot 'integration-fixture.pcapng'
$section=Block 0x0A0D0D0A ([BitConverter]::GetBytes([UInt32]0x1A2B3C4D)+[byte[]](1,0,0,0)+[byte[]](255,255,255,255,255,255,255,255))
$idb=Block 1 ([byte[]](105,0,0,0,255,255,0,0))
$epb=Block 6 ([byte[]](0,0,0,0,0,0,0,0,123,0,0,0,64,0,0,0,64,0,0,0)+$frame)
$valid=$section+$idb+$epb
try {
    Check 'Synthetic pcapng reads exact frame' { [IO.File]::WriteAllBytes($fixture,$valid); $p=@(Read-AirCapture $fixture); $p.Count -eq 1 -and $p[0].PayloadHex -eq '446D0102' }
    Check 'Pcapng trailer mismatch rejects' { $f=$valid.Clone(); $f[$f.Length-1]=1; [IO.File]::WriteAllBytes($fixture,$f); Reject { Read-AirCapture $fixture } }
    Check 'Pcapng truncation rejects' { [IO.File]::WriteAllBytes($fixture,$valid[0..($valid.Length-2)]); Reject { Read-AirCapture $fixture } }
    Check 'Pcapng invalid block size rejects' { $f=$valid.Clone(); $f[4]=11; [IO.File]::WriteAllBytes($fixture,$f); Reject { Read-AirCapture $fixture } }
    Check 'Pcapng unknown interface rejects' { $f=$valid.Clone(); $f[$section.Length+$idb.Length+8]=1; [IO.File]::WriteAllBytes($fixture,$f); Reject { Read-AirCapture $fixture } }
    $df=New-Object byte[] 26; $df[0]=0x44; $df[1]=0x6D; $df[21]=200
    Check 'Dedupe distinguishes differing headers with identical body' {
        $a=[BitConverter]::ToString($df).Replace('-',''); $df[3]=1; $b=[BitConverter]::ToString($df).Replace('-','')
        $r=Get-AirAudioAnalysis @([pscustomobject]@{PayloadHex=$a},[pscustomobject]@{PayloadHex=$b})
        $r.ConflictingDuplicateOccurrences -eq 1 -and $r.IdenticalDuplicateOccurrences -eq 0
    }
    Check 'Original mislabeled controlled capture rejected' { Reject { Read-AirCapture (Join-Path $InputRoot 'air-session.pcapng') } }
    Check 'Original mislabeled baseline capture rejected' { Reject { Read-AirCapture (Join-Path $InputRoot 'air-baseline.pcapng') } }
    $controlled=@(Read-AirCapture (Join-Path $InputRoot 'air-session-wifi.pcapng'))
    $udp=@($controlled | Where-Object Kind -eq 'UDP')
    $csv=@(Import-Csv -LiteralPath (Join-Path $InputRoot 'air-session-packets.csv'))
    Check 'Controlled frame accounting 1180=1176UDP+4ARP' { $controlled.Count -eq 1180 -and $udp.Count -eq 1176 -and @($controlled | Where-Object { $_.Kind -eq 'NonIPv4' -and $_.Reason -eq 'EtherType 0x0806' }).Count -eq 4 }
    Check 'Every UDP record matches existing CSV payload/time/tuple' {
        if ($udp.Count -ne $csv.Count) { return $false }
        for ($i=0; $i -lt $udp.Count; $i++) {
            foreach ($key in @('TimestampRaw','Source','Destination','Protocol','SourcePort','DestinationPort','PayloadLength','PayloadHex')) {
                if ([string]$udp[$i].$key -cne [string]$csv[$i].$key) { return $false }
            }
        }; return $true
    }
    $baseline=@(Read-AirCapture (Join-Path $InputRoot 'air-baseline-wifi.pcapng'))
    Check 'Baseline frame accounting 2495UDP' { $baseline.Count -eq 2495 -and @($baseline | Where-Object Kind -eq 'UDP').Count -eq 2495 }
    $ba=Get-AirAudioAnalysis $baseline; $bf=Get-AirFeedbackAnalysis $baseline
    Check 'Baseline Dm1833 Df526 Da136 no rejected feedback' { $ba.ParsedDmPacketCount -eq 1833 -and $bf.DfValid -eq 526 -and $bf.DaValid -eq 136 -and $bf.Rejected -eq 0 }
    $ca=Get-AirAudioAnalysis $udp; $cf=Get-AirFeedbackAnalysis $udp
    Check 'Controlled Dm951 Df162 Da63 no rejected feedback' { $ca.ParsedDmPacketCount -eq 951 -and $cf.DfValid -eq 162 -and $cf.DaValid -eq 63 -and $cf.Rejected -eq 0 }
    Check 'All eight original inputs unchanged throughout integration' {
        foreach ($file in $files) { if ((Get-FileHash -LiteralPath (Join-Path $InputRoot $file)).Hash -ne $hashes[$file]) { return $false } }; return $true
    }
} finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
$result=[ordered]@{ GeneratedUtc=(Get-Date).ToUniversalTime().ToString('o'); Runtime=$PSVersionTable.PSVersion.ToString(); Total=$tests.Count; Passed=@($tests | Where-Object Passed).Count; Failed=@($tests | Where-Object { -not $_.Passed }).Count; Tests=$tests.ToArray(); InputSHA256=$hashes; ControlledFrames=$controlled.Count; ControlledUdp=$udp.Count; BaselineFrames=$baseline.Count; CodecStatus='Blocked: codec not established; no PCM generated' }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'integration-results.json') -Encoding UTF8
"Integration tests: $($result.Passed)/$($result.Total) passed"
$tests | Where-Object { -not $_.Passed } | ForEach-Object { "FAIL $($_.Name): $($_.Error)" }
if ($result.Failed) { exit 1 }
