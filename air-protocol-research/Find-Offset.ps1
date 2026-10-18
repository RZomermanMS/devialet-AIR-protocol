param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [string]$Wav = (Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$hexes = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==192.0.2.20' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400
foreach ($h in $hexes) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] } }
$w = [IO.File]::ReadAllBytes($Wav)
$src = New-Object 'int[]' 480000; for ($f = 0; $f -lt 480000; $f++) { $src[$f] = [BitConverter]::ToInt16($w, 44 + 4 * $f) }
function Edge($a, $limit) { $first = -1; $last = -1; for ($i = 0; $i -lt $a.Length; $i++) { if ([Math]::Abs($a[$i]) -gt $limit) { if ($first -lt 0) { $first = $i }; $last = $i } }; "$first..$last" }
$mx = ($dec | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Maximum).Maximum
$sp = ($src | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Maximum).Maximum
"source peak $sp edges(>2): $(Edge $src 2)"
"decoded peak $mx edges(>5% max): $(Edge $dec ($mx * 0.05))"
"--- decoded RMS per 0.25s ---"
for ($s = 0; $s -lt 480000; $s += 12000) { $sum = 0.0; for ($i = $s; $i -lt $s + 12000; $i++) { $sum += [double]$dec[$i] * $dec[$i] }; "{0,5:N2}s rms={1,12:N1} max={2}" -f ($s/48000.0), [Math]::Sqrt($sum/12000), (($dec[$s..($s+11999)] | % {[Math]::Abs($_)} | measure -Max).Maximum) }
