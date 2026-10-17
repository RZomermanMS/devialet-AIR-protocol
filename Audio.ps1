Set-StrictMode -Version 2

$script:AirAudioCommonPath = Join-Path $PSScriptRoot 'Common.ps1'
if (-not (Test-Path -LiteralPath $script:AirAudioCommonPath)) { throw 'Common.ps1 is required beside Audio.ps1' }
. $script:AirAudioCommonPath

function Get-AirAudioBodyFingerprint([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AirAudioGreatestCommonDivisor([UInt64]$Left, [UInt64]$Right) {
    while ($Right -ne 0) {
        [UInt64]$remainder = $Left % $Right
        $Left = $Right
        $Right = $remainder
    }
    return $Left
}

function ConvertFrom-AirDm([byte[]]$Bytes) {
    Assert-AirRange $Bytes 0 22
    if ($Bytes[0] -ne 0x44 -or $Bytes[1] -ne 0x6d) { throw 'Expected Dm packet magic (44 6D)' }

    [UInt64]$sampleCounter = Get-AirUIntBE $Bytes 12 8
    [UInt64]$sampleCount = Get-AirUIntBE $Bytes 20 2
    $bodyLength = $Bytes.Length - 22
    $body = New-Object byte[] $bodyLength
    if ($bodyLength -gt 0) { [Array]::Copy($Bytes, 22, $body, 0, $bodyLength) }

    return [pscustomobject]@{
        Magic = 'Dm'
        Mode = [int]$Bytes[11]
        SampleCounter = $sampleCounter
        SampleCount = $sampleCount
        HeaderLength = 22
        PayloadLength = $Bytes.Length
        BodyLength = $bodyLength
        BodyBytes = $body
        BodyFingerprint = Get-AirAudioBodyFingerprint $body
        PayloadFingerprint = Get-AirAudioBodyFingerprint $Bytes
    }
}

function Get-AirAudioAnalysis([object[]]$Packets) {
    if ($null -eq $Packets) { $Packets = @() }

    $parsed = New-Object System.Collections.ArrayList
    $skippedNoPayload = 0
    $skippedNonDm = 0
    $packetIndex = 0
    foreach ($packet in $Packets) {
        $payloadProperty = $packet.PSObject.Properties['PayloadHex']
        if ($null -eq $payloadProperty -or [String]::IsNullOrWhiteSpace([string]$payloadProperty.Value)) {
            $skippedNoPayload++
            $packetIndex++
            continue
        }
        $bytes = ConvertFrom-AirHex ([string]$payloadProperty.Value)
        if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x44 -or $bytes[1] -ne 0x6d) {
            $skippedNonDm++
            $packetIndex++
            continue
        }
        $dm = ConvertFrom-AirDm $bytes
        $timestampProperty = $packet.PSObject.Properties['TimestampRaw']
        $timestamp = if ($null -eq $timestampProperty) { $null } else { [string]$timestampProperty.Value }
        [void]$parsed.Add([pscustomobject]@{
            PacketIndex = $packetIndex
            TimestampRaw = $timestamp
            Dm = $dm
        })
        $packetIndex++
    }

    $counterRecords = @{}
    $arrivalDecreases = 0
    [UInt64]$previousCounter = 0
    $hasPreviousCounter = $false
    foreach ($item in $parsed) {
        [UInt64]$counter = $item.Dm.SampleCounter
        if ($hasPreviousCounter -and $counter -lt $previousCounter) { $arrivalDecreases++ }
        $previousCounter = $counter
        $hasPreviousCounter = $true

        $key = [string]$counter
        if (-not $counterRecords.ContainsKey($key)) {
            $counterRecords[$key] = New-Object System.Collections.ArrayList
        }
        [void]$counterRecords[$key].Add($item)
    }

    $uniqueCounters = @($counterRecords.Keys | ForEach-Object { [UInt64]$_ } | Sort-Object)
    [UInt64]$gridStep = 0
    for ($i = 1; $i -lt $uniqueCounters.Count; $i++) {
        [UInt64]$difference = $uniqueCounters[$i] - $uniqueCounters[$i - 1]
        if ($difference -gt 0) {
            if ($gridStep -eq 0) { $gridStep = $difference }
            else { $gridStep = Get-AirAudioGreatestCommonDivisor $gridStep $difference }
        }
    }

    [UInt64]$gridPositions = 0
    [UInt64]$missingGridPositions = 0
    if ($uniqueCounters.Count -gt 0 -and $gridStep -gt 0) {
        $gridPositions = (($uniqueCounters[-1] - $uniqueCounters[0]) / $gridStep) + 1
        $missingGridPositions = $gridPositions - [UInt64]$uniqueCounters.Count
    }

    $duplicateCounters = 0
    $identicalDuplicateCounters = 0
    $conflictingDuplicateCounters = 0
    foreach ($records in $counterRecords.Values) {
        if ($records.Count -gt 1) {
            $duplicateCounters += $records.Count - 1
            $fingerprints = @($records | ForEach-Object { $_.Dm.PayloadFingerprint } | Select-Object -Unique)
            if ($fingerprints.Count -eq 1) { $identicalDuplicateCounters += $records.Count - 1 }
            else { $conflictingDuplicateCounters += $records.Count - 1 }
        }
    }

    $lengthCounts = @{}
    $modeCounts = @{}
    foreach ($item in $parsed) {
        $lengthKey = [string]$item.Dm.PayloadLength
        $modeKey = [string]$item.Dm.Mode
        if (-not $lengthCounts.ContainsKey($lengthKey)) { $lengthCounts[$lengthKey] = 0 }
        if (-not $modeCounts.ContainsKey($modeKey)) { $modeCounts[$modeKey] = 0 }
        $lengthCounts[$lengthKey]++
        $modeCounts[$modeKey]++
    }

    $bodyObservations = New-Object System.Collections.ArrayList
    foreach ($lengthKey in @($lengthCounts.Keys | Sort-Object { [int]$_ })) {
        $payloadLength = [int]$lengthKey
        $bodyLength = $payloadLength - 22
        $recordsAtLength = @($parsed | Where-Object { $_.Dm.PayloadLength -eq $payloadLength })
        $sampleCounts = @($recordsAtLength | ForEach-Object { $_.Dm.SampleCount } | Select-Object -Unique)
        $bytesPerFrame = if ($sampleCounts.Count -eq 1 -and $sampleCounts[0] -ne 0) {
            [Math]::Round($bodyLength / [double]$sampleCounts[0], 3)
        } else { $null }
        [void]$bodyObservations.Add([pscustomobject]@{
            PayloadLength = $payloadLength
            BodyLength = $bodyLength
            PacketCount = $lengthCounts[$lengthKey]
            SampleCounts = $sampleCounts
            BytesPerFrame = $bytesPerFrame
            FirstCounter = @($recordsAtLength | ForEach-Object { $_.Dm.SampleCounter } | Sort-Object)[0]
            LastCounter = @($recordsAtLength | ForEach-Object { $_.Dm.SampleCounter } | Sort-Object)[-1]
        })
    }

    $orderedCounterItems = @(
        foreach ($counter in $uniqueCounters) {
            $counterRecords[[string]$counter][0]
        }
    )
    $lengthTransitions = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $orderedCounterItems.Count; $i++) {
        $previous = $orderedCounterItems[$i - 1].Dm
        $current = $orderedCounterItems[$i].Dm
        if ($previous.PayloadLength -ne $current.PayloadLength) {
            [void]$lengthTransitions.Add([pscustomobject]@{
                PreviousCounter = $previous.SampleCounter
                CurrentCounter = $current.SampleCounter
                CounterGap = $current.SampleCounter - $previous.SampleCounter
                PreviousPayloadLength = $previous.PayloadLength
                CurrentPayloadLength = $current.PayloadLength
            })
        }
    }

    $fixedPcmCandidates = @(
        [pscustomobject]@{ Name = 'PCM16LE stereo'; BytesPerFrame = 4 },
        [pscustomobject]@{ Name = 'PCM16LE mono'; BytesPerFrame = 2 },
        [pscustomobject]@{ Name = 'PCM24BE stereo'; BytesPerFrame = 6 }
    ) | ForEach-Object {
        $candidate = $_
        $matching = @($parsed | Where-Object {
            $_.Dm.BodyLength -eq ([UInt64]$_.Dm.SampleCount * [UInt64]$candidate.BytesPerFrame)
        }).Count
        [pscustomobject]@{
            Name = $candidate.Name
            ExpectedBytesPerFrame = $candidate.BytesPerFrame
            MatchingPackets = $matching
            TotalPackets = $parsed.Count
            Result = if ($matching -eq $parsed.Count -and $parsed.Count -gt 0) { 'compatible' } else { 'incompatible' }
        }
    }

    $firstCounter = if ($uniqueCounters.Count -gt 0) { $uniqueCounters[0] } else { $null }
    $lastCounter = if ($uniqueCounters.Count -gt 0) { $uniqueCounters[-1] } else { $null }
    return [pscustomobject]@{
        InputPacketCount = $Packets.Count
        ParsedDmPacketCount = $parsed.Count
        SkippedNoPayloadCount = $skippedNoPayload
        SkippedNonDmCount = $skippedNonDm
        Modes = $modeCounts
        PayloadLengths = $lengthCounts
        UniqueCounterCount = $uniqueCounters.Count
        DuplicateCounterOccurrences = $duplicateCounters
        IdenticalDuplicateOccurrences = $identicalDuplicateCounters
        ConflictingDuplicateOccurrences = $conflictingDuplicateCounters
        ArrivalCounterDecreases = $arrivalDecreases
        CounterGridStep = $gridStep
        CounterRange = [pscustomobject]@{ First = $firstCounter; Last = $lastCounter }
        ObservedGridPositions = $gridPositions
        MissingGridPositionsWithinRange = $missingGridPositions
        BodyObservations = $bodyObservations
        PayloadLengthTransitionsByCounter = $lengthTransitions
        FixedIntegerPackingCandidates = $fixedPcmCandidates
        CodecConclusion = 'Unknown. Variable body sizes are incompatible with the tested fixed-width PCM layouts; no PCM is emitted.'
        DuplicateConclusion = 'Identical duplicate counter/body observations are measured evidence only; they are not labelled retransmissions.'
        ReorderConclusion = 'ArrivalCounterDecreases counts observed capture-order reversals; it does not infer sender order or network cause.'
    }
}
