$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'air-stereo-nonperiodic-ramp.wav'
$stream = [IO.File]::Create($path)
$writer = New-Object IO.BinaryWriter($stream)
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([uint32]1920036)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $writer.Write([uint32]16)
    $writer.Write([uint16]1)
    $writer.Write([uint16]2)
    $writer.Write([uint32]48000)
    $writer.Write([uint32]192000)
    $writer.Write([uint16]4)
    $writer.Write([uint16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([uint32]1920000)
    $leftRandom = New-Object Random(7319)
    $rightRandom = New-Object Random(19427)
    $leftPrevious = 0
    $leftNext = $leftRandom.Next(-32, 33)
    $rightPrevious = 0
    $rightNext = $rightRandom.Next(-24, 25)
    for ($frame = 0; $frame -lt 480000; $frame++) {
        [int16]$left = 0
        [int16]$right = 0
        if ($frame -ge 96000 -and $frame -lt 384000) {
            $index = $frame - 96000
            if ($index -gt 0 -and $index % 137 -eq 0) {
                $leftPrevious = $leftNext
                $leftNext = $leftRandom.Next(-32, 33)
            }
            if ($index -gt 0 -and $index % 211 -eq 0) {
                $rightPrevious = $rightNext
                $rightNext = $rightRandom.Next(-24, 25)
            }
            $fade = [Math]::Min(1, [Math]::Min($index / 2400.0, (383999 - $frame) / 2400.0))
            $left = [int16][Math]::Round(($leftPrevious + ($leftNext - $leftPrevious) * ($index % 137) / 137.0) * $fade)
            $right = [int16][Math]::Round(($rightPrevious + ($rightNext - $rightPrevious) * ($index % 211) / 211.0) * $fade)
        }
        $writer.Write($left)
        $writer.Write($right)
    }
} finally { $writer.Dispose() }
$bytes = [IO.File]::ReadAllBytes($path)
if ($bytes.Length -ne 1920044) { throw 'Invalid WAV size.' }
$leftPeak = 0
$rightPeak = 0
$different = 0
for ($frame = 0; $frame -lt 480000; $frame++) {
    $l = [int][BitConverter]::ToInt16($bytes,44+4*$frame)
    $r = [int][BitConverter]::ToInt16($bytes,46+4*$frame)
    if (($frame -lt 96000 -or $frame -ge 384000) -and ($l -ne 0 -or $r -ne 0)) { throw 'Silence validation failed.' }
    $leftPeak = [Math]::Max($leftPeak,[Math]::Abs($l))
    $rightPeak = [Math]::Max($rightPeak,[Math]::Abs($r))
    if ($l -ne $r) { $different++ }
}
if ($leftPeak -ne 32 -or $rightPeak -ne 24 -or $different -lt 250000) { throw 'Stereo signal validation failed.' }
$result = [pscustomobject]@{
    File = [IO.Path]::GetFileName($path)
    SHA256 = (Get-FileHash -LiteralPath $path).Hash
    Frames = 480000
    SampleRate = 48000
    Bits = 16
    Channels = 2
    ActiveStartFrame = 96000
    ActiveEndFrameExclusive = 384000
    LeftKnotSpacing = 137
    RightKnotSpacing = 211
    LeftPeak = $leftPeak
    RightPeak = $rightPeak
    DifferentChannelFrames = $different
    Construction = 'Independent seeded random knot values joined by linear ramps, rounded to PCM16; 50ms fades; 2s silence before and after.'
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'stereo-ramp-manifest.json')
$result | Format-List
