param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [string]$Wav = (Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$ts = 'C:\Program Files\Wireshark\tshark.exe'
$hexes = & $ts -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==192.0.2.20' -T fields -e udp.payload
$seen = @{}; $ok = 0; $bad = 0; $badReasons = @{}; $blocks = @()
foreach ($h in $hexes) {
    $c = [Convert]::ToInt64($h.Substring(24, 16), 16)
    if ($seen.ContainsKey($c)) { continue }
    $seen[$c] = 1
    try { $p = [ReferenceBlockDecoder]::Decode($h); $blocks += $p; $ok++ }
    catch { $bad++; $m = $_.Exception.Message -replace '^.*?: ', ''; $badReasons[$m] = 1 + [int]$badReasons[$m] }
}
"Unique blocks: $($seen.Count); decoded: $ok; rejected: $bad"
$badReasons.GetEnumerator() | ForEach-Object { "  rejected x$($_.Value): $($_.Key)" }
$w = [IO.File]::ReadAllBytes($Wav)
$n = 0; $sxy = 0.0; $sxx = 0.0; $syy = 0.0; $lrDiff = 0; $silentNonzero = 0; $silent = 0
$dec = New-Object 'System.Collections.Generic.Dictionary[long,int]'
foreach ($b in $blocks) {
    for ($i = 0; $i -lt $b.Left.Length; $i++) {
        $f = $b.Counter + $i
        if ($f -lt 0 -or $f -ge 480000) { continue }
        $x = [double]$b.Left[$i]; $y = [double][BitConverter]::ToInt16($w, 44 + 4 * $f)
        $sxy += $x * $y; $sxx += $x * $x; $syy += $y * $y; $n++
        if ($b.Left[$i] -ne $b.Right[$i]) { $lrDiff++ }
        if ($y -eq 0) { $silent++; if ($x -ne 0) { $silentNonzero++ } }
        $dec[$f] = $b.Left[$i]
    }
}
$gain = $sxy / $sxx
$corr = $sxy / [Math]::Sqrt($sxx * $syy)
$res = 0.0; $maxErr = 0.0
foreach ($b in $blocks) { for ($i = 0; $i -lt $b.Left.Length; $i++) { $f = $b.Counter + $i; if ($f -ge 480000) { continue }
    $y = [double][BitConverter]::ToInt16($w, 44 + 4 * $f); $e = [Math]::Abs($b.Left[$i] * $gain - $y); $res += $e * $e; if ($e -gt $maxErr) { $maxErr = $e } } }
"Frames compared: $n of 480000 (coverage $([Math]::Round(100.0*$dec.Count/480000,2))%)"
"Fit: gain(ref16 per decoded unit)=$([Math]::Round($gain,6)); correlation=$([Math]::Round($corr,6)); rms residual=$([Math]::Round([Math]::Sqrt($res/$n),3)) 16-bit LSB; max abs residual=$([Math]::Round($maxErr,2))"
"Left!=Right frames: $lrDiff; source-silent frames: $silent, decoded nonzero there: $silentNonzero"
