param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [string]$Wav = (Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==192.0.2.20' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400; $early = @()
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] }
    if ($c -lt 7000) { $early += "{0} mode={1} width={2}/{3} len={4} max={5}" -f $c, $h.Substring(22, 2), $p.Width, $p.RightWidth, ($h.Length / 2), (($p.Left | % { [Math]::Abs($_) } | Measure-Object -Maximum).Maximum) } }
"--- first blocks with non-trivial content (counter<7000) ---"
$early | Select-Object -First 8
$w = [IO.File]::ReadAllBytes($Wav)
$src = New-Object 'int[]' 480000; for ($f = 0; $f -lt 480000; $f++) { $src[$f] = [BitConverter]::ToInt16($w, 44 + 4 * $f) }
function Edge($a, $from, $limit) { $first = -1; $last = -1; for ($i = $from; $i -lt $a.Length; $i++) { if ([Math]::Abs($a[$i]) -gt $limit) { if ($first -lt 0) { $first = $i }; $last = $i } }; @($first, $last) }
$se = Edge $src 0 2; $de = Edge $dec 8000 50
"source tone $($se[0])..$($se[1]) (len $($se[1]-$se[0]+1)); decoded tone $($de[0])..$($de[1]) (len $($de[1]-$de[0]+1))"
$est = $de[0] - $se[0]
"estimated lag (decoded - source) = $est frames"
$best = $null
foreach ($lag in ($est - 40)..($est + 40)) {
    $sxy = 0.0; $sxx = 0.0; $syy = 0.0
    for ($f = 150000; $f -lt 330000; $f++) { $x = [double]$dec[$f + $lag]; $y = [double]$src[$f]; $sxy += $x * $y; $sxx += $x * $x; $syy += $y * $y }
    $r = $sxy / [Math]::Sqrt($sxx * $syy); if (-not $best -or $r -gt $best.R) { $best = [pscustomobject]@{ Lag = $lag; R = $r; Gain = $sxy / $syy } }
}
"best lag $($best.Lag): correlation $([Math]::Round($best.R,6)); decoded/source gain $([Math]::Round($best.Gain,3))"
$lag = $best.Lag; $res = 0.0; $n = 0; $maxe = 0.0; $silentBad = 0
for ($f = 0; $f -lt 470000; $f++) { if ($f + $lag -lt 8000 -or $f + $lag -ge 480000) { continue }; $e = $dec[$f + $lag] - $best.Gain * $src[$f]; $res += $e * $e; $n++; if ([Math]::Abs($e) -gt $maxe) { $maxe = [Math]::Abs($e) }
    if ($src[$f] -eq 0 -and $dec[$f + $lag] -ne 0) { $silentBad++ } }
"rms residual over aligned span: $([Math]::Round([Math]::Sqrt($res/$n),2)) decoded units (tone rms ~ $([Math]::Round($best.Gain*11.7,0))); max residual $([Math]::Round($maxe,1)); decoded nonzero where source exactly 0: $silentBad"
