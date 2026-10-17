$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'
$rate = 48000
$frames = $rate * 10
$channels = 2
$dataLength = $frames * $channels * 2
$stream = [IO.File]::Create($path)
$writer = New-Object IO.BinaryWriter($stream)
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([uint32](36 + $dataLength))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $writer.Write([uint32]16)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$channels)
    $writer.Write([uint32]$rate)
    $writer.Write([uint32]($rate * $channels * 2))
    $writer.Write([uint16]($channels * 2))
    $writer.Write([uint16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([uint32]$dataLength)
    for ($frame = 0; $frame -lt $frames; $frame++) {
        [int16]$sample = 0
        if ($frame -ge 144000 -and $frame -lt 336000) {
            $edge = [Math]::Min(1.0, [Math]::Min(
                ($frame - 144000) / 2400.0,
                (335999 - $frame) / 2400.0))
            $sample = [int16][Math]::Round(
                32767 * 0.001 * $edge * [Math]::Sin(2 * [Math]::PI * 997 * $frame / $rate))
        }
        $writer.Write($sample)
        $writer.Write($sample)
    }
} finally {
    $writer.Dispose()
}

$bytes = [IO.File]::ReadAllBytes($path)
if ($bytes.Length -ne 1920044 -or
    [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
    [Text.Encoding]::ASCII.GetString($bytes, 8, 8) -ne 'WAVEfmt ' -or
    [Text.Encoding]::ASCII.GetString($bytes, 36, 4) -ne 'data' -or
    [BitConverter]::ToUInt32($bytes, 4) -ne $bytes.Length - 8 -or
    [BitConverter]::ToUInt32($bytes, 16) -ne 16 -or
    [BitConverter]::ToUInt16($bytes, 20) -ne 1 -or
    [BitConverter]::ToUInt16($bytes, 22) -ne 2 -or
    [BitConverter]::ToUInt32($bytes, 24) -ne 48000 -or
    [BitConverter]::ToUInt32($bytes, 28) -ne 192000 -or
    [BitConverter]::ToUInt16($bytes, 32) -ne 4 -or
    [BitConverter]::ToUInt16($bytes, 34) -ne 16 -or
    [BitConverter]::ToUInt32($bytes, 40) -ne 1920000) {
    throw 'Generated WAV failed header validation.'
}
$peak = 0
$crossings = 0
$previous = 0
for ($frame = 0; $frame -lt $frames; $frame++) {
    $left = [int][BitConverter]::ToInt16($bytes, 44 + $frame * 4)
    $right = [int][BitConverter]::ToInt16($bytes, 46 + $frame * 4)
    if ($left -ne $right) { throw "Channel mismatch at frame $frame." }
    if (($frame -lt 144000 -or $frame -ge 336000) -and $left -ne 0) {
        throw "Nonzero sample in silence at frame $frame."
    }
    $peak = [Math]::Max($peak, [Math]::Abs($left))
    if ($frame -ge 192000 -and $frame -lt 288000) {
        if ($previous -le 0 -and $left -gt 0) { $crossings++ }
        $previous = $left
    }
}
$measuredHz = $crossings / 2.0
if ($peak -ne 33 -or [Math]::Abs($measuredHz - 997) -gt 0.5) {
    throw "Signal validation failed: peak=$peak, frequency=$measuredHz Hz."
}
$result = [pscustomobject]@{
    File = [IO.Path]::GetFileName($path)
    SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Bytes = $bytes.Length
    Encoding = 'PCM signed 16-bit little-endian'
    SampleRate = $rate
    Channels = $channels
    Frames = $frames
    DurationSeconds = 10
    SilenceBeforeSeconds = 3
    ToneSeconds = 4
    SilenceAfterSeconds = 3
    FrequencyHz = 997
    MeasuredPositiveCrossingFrequencyHz = $measuredHz
    NominalPeakDbFS = -60
    ActualPeakSample = $peak
    FadeSeconds = 0.05
    ChannelRelationship = 'Identical left and right'
    Validation = 'Header, duration, silence samples, channel equality, peak and tone frequency passed'
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'air-test-tone-manifest.json')
$result | Format-List
