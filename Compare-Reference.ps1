$ErrorActionPreference = 'Stop'
$csv = 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-reference-wifi-packets.csv'
$rows = Import-Csv -LiteralPath $csv
$packets = @($rows | Where-Object { $_.PayloadHex.StartsWith('446D') } | ForEach-Object {
    [pscustomobject]@{
        Counter = [Convert]::ToInt64($_.PayloadHex.Substring(24, 16), 16)
        Count = [Convert]::ToInt32($_.PayloadHex.Substring(40, 4), 16)
        Mode = $_.PayloadHex.Substring(22, 2)
        Length = [int]$_.PayloadLength
        Hex = $_.PayloadHex
    }
})
if (!$packets.Count) { throw 'No audio packets found.' }
$unique = @($packets | Group-Object Counter | ForEach-Object {
    if (@($_.Group.Hex | Sort-Object -Unique).Count -ne 1) { throw "Conflicting payloads at counter $($_.Name)." }
    $_.Group[0]
} | Sort-Object Counter)
$wavPath = Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'
$wav = [IO.File]::ReadAllBytes($wavPath)
if ((Get-FileHash -LiteralPath $wavPath).Hash -ne 'EFCED6291888A928155BD2F5C6DBE7114C45B0D7861CC3D452CA769E9E727B05') {
    throw 'Reference source changed.'
}
$counts = @($unique | ForEach-Object { $_.Count } | Sort-Object -Unique)
if ($counts.Count -ne 1 -or $counts[0] -ne 200) { throw 'Unexpected packet frame counts.' }
$comparisons = foreach ($packet in $unique) {
    $nonzero = 0
    $peak = 0
    for ($i = 0; $i -lt 200; $i++) {
        $frame = $packet.Counter + $i
        if ($frame -lt 0 -or $frame -ge 480000) { throw 'Counter outside reference signal.' }
        $sample = [int][BitConverter]::ToInt16($wav, 44 + 4 * $frame)
        if ($sample -ne 0) { $nonzero++ }
        $peak = [Math]::Max($peak, [Math]::Abs($sample))
    }
    [pscustomobject]@{
        Counter = $packet.Counter
        Seconds = $packet.Counter / 48000.0
        Mode = $packet.Mode
        Length = $packet.Length
        ReferenceNonzeroFrames = $nonzero
        ReferencePeak = $peak
        ClassificationAgrees = (($nonzero -eq 0 -and $packet.Length -eq 166) -or
            ($nonzero -gt 0 -and $packet.Length -gt 166))
    }
}
$transitions = for ($i = 1; $i -lt $unique.Count; $i++) {
    if ($unique[$i].Mode -ne $unique[$i - 1].Mode) {
        [pscustomobject]@{
            PreviousCounter = $unique[$i - 1].Counter
            PreviousMode = $unique[$i - 1].Mode
            Counter = $unique[$i].Counter
            Mode = $unique[$i].Mode
            GapFrames = $unique[$i].Counter - $unique[$i - 1].Counter - 200
        }
    }
}
$groups = @($unique | Group-Object Mode, Length | ForEach-Object {
    [pscustomobject]@{
        Mode = $_.Group[0].Mode
        Length = $_.Group[0].Length
        UniquePackets = $_.Count
        FirstCounter = $_.Group[0].Counter
        LastCounter = $_.Group[-1].Counter
    }
})
$previous = @(Import-Csv -LiteralPath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-session-packets.csv' |
    Where-Object { $_.PayloadHex.StartsWith('446D') })
$lookup = @{}
foreach ($row in $previous) { $lookup[$row.PayloadHex.Substring(24, 16)] = $row }
$common = 0
$identicalBodies = 0
foreach ($packet in $unique) {
    $key = $packet.Hex.Substring(24, 16)
    if ($lookup.ContainsKey($key)) {
        $common++
        if ($lookup[$key].PayloadHex.Substring(44) -eq $packet.Hex.Substring(44)) { $identicalBodies++ }
    }
}
$first = $unique[0].Counter
$last = $unique[-1].Counter
$result = [pscustomobject]@{
    ReferenceSHA256 = (Get-FileHash -LiteralPath $wavPath).Hash
    AudioObservations = $packets.Count
    UniquePositions = $unique.Count
    DuplicateObservations = $packets.Count - $unique.Count
    FirstCounter = $first
    LastCounter = $last
    MissingPositionsInObservedSpan = (($last - $first) / 200 + 1) - $unique.Count
    HeaderFrameCount = 200
    ModeGroups = $groups
    ModeTransitions = @($transitions)
    ExpectedToneStartFrame = 144000
    ExpectedToneEndFrameExclusive = 336000
    ComparedPositions = @($comparisons).Count
    PayloadLengthMatchesReferenceSilenceOrNonzero = @($comparisons | Where-Object ClassificationAgrees).Count
    Mismatches = @($comparisons | Where-Object { !$_.ClassificationAgrees })
    PreviousCaptureCommonCounters = $common
    PreviousCaptureIdenticalOpaqueBodiesAtSameCounter = $identicalBodies
    Interpretation = 'Comparison assumes packet counter equals WAV frame index; association is not decoded audio or proof of codec/sample alignment.'
    PCMComparison = 'Blocked: encoded payloads not decoded. No recovered-frequency or sample-equality claim.'
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'reference-comparison.json')
$comparisons | Export-Csv -LiteralPath (Join-Path $PSScriptRoot 'reference-comparison-packets.csv') -NoTypeInformation
$result | Select-Object AudioObservations, UniquePositions, MissingPositionsInObservedSpan,
    ComparedPositions, PayloadLengthMatchesReferenceSilenceOrNonzero,
    PreviousCaptureCommonCounters, PreviousCaptureIdenticalOpaqueBodiesAtSameCounter | Format-List
$groups | Format-Table -AutoSize
$transitions | Format-Table -AutoSize
$result.Mismatches | Select-Object -First 8 | Format-Table -AutoSize
