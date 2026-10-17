param([string]$Out = (Join-Path $PSScriptRoot 'air-test-multitone.wav'))
$ErrorActionPreference = 'Stop'
$rate = 48000; $sec = 10; $n = $rate * $sec
# Peak is about 600 LSB (-35 dBFS): 30 dB above the earlier 997 Hz test, still moderate.
$left = @(@(220, 100), @(997, 120), @(3001, 110), @(7003, 90), @(12011, 80))
$right = @(@(330, 110), @(1499, 120), @(4001, 100), @(9001, 90), @(15013, 70))
$ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
$bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $n * 4)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]2); $bw.Write([int]$rate); $bw.Write([int]($rate * 4)); $bw.Write([int16]4); $bw.Write([int16]16)
$bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]($n * 4))
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    # fade in/out over 0.5 s and slow 0.5 Hz amplitude swell so level changes across blocks
    $env = [Math]::Min(1.0, [Math]::Min($t, $sec - $t) / 0.5) * (0.75 + 0.25 * [Math]::Sin(2 * [Math]::PI * 0.5 * $t))
    $l = 0.0; foreach ($c in $left) { $l += $c[1] * [Math]::Sin(2 * [Math]::PI * $c[0] * $t) }
    $r = 0.0; foreach ($c in $right) { $r += $c[1] * [Math]::Sin(2 * [Math]::PI * $c[0] * $t + 1.0) }
    $bw.Write([int16][Math]::Round($l * $env)); $bw.Write([int16][Math]::Round($r * $env))
}
$bw.Flush(); [IO.File]::WriteAllBytes($Out, $ms.ToArray())
(Get-FileHash $Out -Algorithm SHA256).Hash
