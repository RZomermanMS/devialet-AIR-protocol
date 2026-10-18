$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Send-Mp3.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count) { throw 'Sender syntax invalid' }
$source=@($ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
    $n.Value.Contains('public static class Snd2')
},$true))
Add-Type -TypeDefinition $source[0].Value
. (Join-Path $PSScriptRoot 'Common.ps1')
function MustFail([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch {
        if($_.Exception.ToString().Contains($Message)) { return }
        throw
    }
    throw "Expected failure: $Message"
}
[Snd2]::CheckHealth(1999,0,0,200,0)
MustFail { [Snd2]::CheckHealth(2000,0,1999,200,0) } 'Feedback absent'
MustFail { [Snd2]::CheckHealth(2000,1999,0,200,0) } 'progress stalled'
[Snd2]::CheckHealth(2000,1999,0,200,200)
$d=New-Object byte[] 41
$d[0]=0x44; $d[1]=0x66; $d[9]=142
$crc=Get-AirCrc16 $d 39
$d[39]=[byte]($crc -shr 8);$d[40]=[byte]($crc -band 255)
if(-not [Snd2]::ValidFeedback($d,142)) { throw 'Valid feedback rejected' }
if(-not [Snd2]::ValidSessionFeedback($d,142,0)) { throw 'Matching session rejected' }
if([Snd2]::ValidSessionFeedback($d,142,1)) { throw 'Foreign session accepted' }
if([Snd2]::ValidFeedback($d,140)) { throw 'Wrong generation accepted' }
$d[26]=1
if([Snd2]::ValidFeedback($d,142)) { throw 'Corrupt feedback accepted' }
if([Snd2]::ValidFeedback((New-Object byte[] 40),142)) { throw 'Truncated feedback accepted' }
if([Snd2]::ValidFeedback((New-Object byte[] 42),142)) { throw 'Malformed length accepted' }
$d[26]=0;$d[38]=1
$crc=Get-AirCrc16 $d 39
$d[39]=[byte]($crc -shr 8);$d[40]=[byte]($crc -band 255)
if([Snd2]::ValidFeedback($d,142)) { throw 'CRC-valid inconsistent interval count accepted' }
$fixtures=@(
    @{B=119800;A=120799;F=70495;Start=248;End=248;First=120000;Last=120000},
    @{B=279800;A=280799;F=230841;Start=246;End=247;First=280000;Last=280200},
    @{B=319800;A=320799;F=272671;Start=237;End=237;First=320000;Last=320000},
    @{B=320600;A=323599;F=275071;Start=229;End=229;First=320800;Last=320800},
    @{B=563000;A=564799;F=523377;Start=200;End=203;First=563200;Last=563800},
    @{B=3063600;A=3064999;F=3024078;Start=199;End=200;First=3063800;Last=3064000},
    @{B=3063600;A=3067599;F=3026283;Start=188;End=189;First=3063800;Last=3064000}
)
foreach($f in $fixtures) {
    $repair=[Snd2]::RepairCounters($f.B,$f.A,$f.F,$f.A-199,[int[]]@($f.Start,$f.End))
    if($repair[0] -ne $f.First -or $repair[-1] -ne $f.Last -or
        $repair.Count -ne ($f.End-$f.Start+1)) { throw 'Captured interval mapping mismatch' }
}
$separated=[Snd2]::RepairCounters(0,999,0,800,[int[]]@(1,1,3,4))
if(($separated -join ',') -ne '200,600,800') { throw 'Separated intervals mismatch' }
MustFail { [Snd2]::RepairCounters(0,80599,0,80400,[int[]]@(1,401)) } 'safety limit'
$limit=[Snd2]::RepairCounters(0,80199,0,80000,[int[]]@(1,400))
if($limit.Count -ne 400 -or $limit[-1] -ne 80000) { throw 'Resend-cache boundary rejected' }
MustFail { [Snd2]::RepairCounters(200,1000,0,1000,[int[]]@(2,2)) } 'Invalid feedback'
MustFail { [Snd2]::RepairCounters(200,999,0,400,[int[]]@(2,2)) } 'Invalid feedback'
MustFail { [Snd2]::RepairCounters(200,999,0,800,[int[]]@(1,1)) } 'outside feedback'
MustFail { [Snd2]::RepairCounters(0,999,0,800,[int[]]@(2,1)) } 'Invalid feedback intervals'
MustFail { [Snd2]::RepairCounters(0,999,0,800,[int[]]@(1,2,2,3)) } 'Invalid feedback intervals'
'PASS: sender compiles; 2-second watchdog boundaries, caught-up progress, CRC, generation and length guards.'
'PASS: seven captured relative-F mappings, separated intervals, invalid bounds/order and recovery safety limit.'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
foreach($rate in @(44100,48000)) {
    $packets=[Snd2]::GenerateStartup(26128,30,$rate)
    if($packets.Count -ne 38) { throw 'Generated startup count mismatch' }
    for($i=0;$i -lt $packets.Count;$i++) {
        $decoded=[ReferenceBlockDecoder]::Decode($packets[$i])
        $bytes=ConvertFrom-AirHex $packets[$i]
        if($decoded.Counter -ne 200*$i -or ($decoded.Left | Measure-Object -Maximum).Maximum -ne 0 -or
            ($decoded.Right | Measure-Object -Minimum).Minimum -ne 0 -or
            $bytes[5] -ne 0x66 -or $bytes[6] -ne 0x10 -or $bytes[10] -ne 30 -or
            $bytes[11] -ne $(if($rate -eq 44100){0}else{2})) { throw 'Generated startup content mismatch' }
    }
}
MustFail { [Snd2]::GenerateStartup(0,30,44100) } 'startup'
MustFail { [Snd2]::GenerateStartup(1,254,44100) } 'startup'
$stop=[IO.Path]::GetTempFileName()
$pcm=New-Object IO.MemoryStream(,(New-Object byte[] 800))
$read=[Delegate]::CreateDelegate([Snd2+ReadPcm],$pcm,'Read')
try {
    MustFail {
        [Snd2]::Run([Snd2]::GenerateStartup(1,30,44100),[double[]](0..37),
            $read,0.25,1,'127.0.0.1','127.0.0.1',30,44100,$stop)
    } 'Playback stopped'
    $socket=New-Object Net.Sockets.UdpClient
    try {
        $socket.ExclusiveAddressUse=$true
        $socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,45456)))
    } finally { $socket.Dispose() }
} finally { $pcm.Dispose(); Remove-Item -LiteralPath $stop }
'PASS: generated silence startup CRC/counters/headers at both rates; cancellation releases sender socket.'
$receiver=New-Object Net.Sockets.UdpClient
$pcm=New-Object IO.MemoryStream(,(New-Object byte[] 800))
$read=[Delegate]::CreateDelegate([Snd2+ReadPcm],$pcm,'Read')
try {
    $receiver.ExclusiveAddressUse=$true
    $receiver.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,45455)))
    MustFail {
        [Snd2]::Run([Snd2]::GenerateStartup(1,30,44100),[double[]](0..37 | ForEach-Object {$_*200.0/44100}),
            $read,0.25,1,'127.0.0.1','127.0.0.1',30,44100,$null)
    } 'Startup not acknowledged'
    $received=0
    while($receiver.Available -gt 0) {
        $endpoint=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)
        $packet=$receiver.Receive([ref]$endpoint)
        if($packet[10] -ne 30) { throw 'Audio sent before startup readiness was confirmed' }
        $received++
    }
    if($received -ne 38) { throw "Expected 38 generated startup packets, received $received" }
} finally { $pcm.Dispose(); $receiver.Dispose() }
'PASS: missing startup acknowledgement aborts without sending music.'
