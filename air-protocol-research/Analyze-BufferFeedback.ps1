$ErrorActionPreference = 'Stop'
$paths = @(
    'C:\Evidence\air-session-packets.csv',
    'C:\Evidence\air-reference-wifi-packets.csv',
    'C:\Evidence\air-stereo-ramp-packets.csv')
$results = foreach ($path in $paths) {
    $rows = @(Import-Csv -LiteralPath $path | Sort-Object { [long]$_.TimestampRaw })
    $latest = $null
    $seen = @{}
    $repeats = 0
    $repeatInside = 0
    $newInside = 0
    $newAfterFeedback = 0
    $feedback = [Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $h = $row.PayloadHex
        if ($h.StartsWith('4466')) {
            $count = [Convert]::ToInt32($h.Substring(74,4),16)
            $ranges = @(for ($i=0; $i -lt $count; $i++) {
                [pscustomobject]@{
                    Start = [Convert]::ToInt32($h.Substring((39+4*$i)*2,4),16)
                    End = [Convert]::ToInt32($h.Substring((41+4*$i)*2,4),16)
                }
            })
            $latest = [pscustomobject]@{
                Time = [long]$row.TimestampRaw
                A = [Convert]::ToInt64($h.Substring(20,16),16)
                B = [Convert]::ToInt64($h.Substring(36,16),16)
                Ranges = $ranges
            }
            $feedback.Add($latest)
        } elseif ($h.StartsWith('446D')) {
            $counter = [Convert]::ToInt64($h.Substring(24,16),16)
            $block = $counter/200
            $inside = $false
            if ($latest) {
                foreach ($range in $latest.Ranges) {
                    if ($block -ge $range.Start -and $block -le $range.End) { $inside=$true; break }
                }
            }
            if ($seen.ContainsKey($counter)) {
                $repeats++
                if ($inside) { $repeatInside++ }
            } elseif ($latest) {
                $newAfterFeedback++
                if ($inside) { $newInside++ }
            }
            $seen[$counter] = $true
        }
    }
    $active = @($feedback | Where-Object { $_.Time -ge $feedback[0].Time -and $_.A -lt $feedback[-1].A })
    $rate = $null
    if ($active.Count -gt 1) {
        $rate = ($active[-1].A-$active[0].A)/(($active[-1].Time-$active[0].Time)/1000000.0)
    }
    [pscustomobject]@{
        Capture = [IO.Path]::GetFileName($path)
        FeedbackPackets = $feedback.Count
        ActiveCursorRateUnitsPerSecond = $rate
        RepeatedAudioObservations = $repeats
        RepeatsInsideLatestFeedbackRanges = $repeatInside
        FirstObservedPositionsAfterFeedback = $newAfterFeedback
        FirstObservedPositionsInsideLatestRanges = $newInside
        EmptyRangePackets = @($feedback | Where-Object { $_.Ranges.Count -eq 0 }).Count
        EmptyRangesWithBEqualsAMinus199 = @($feedback | Where-Object { $_.Ranges.Count -eq 0 -and $_.B -eq $_.A-199 }).Count
        NonemptyRangePackets = @($feedback | Where-Object { $_.Ranges.Count -gt 0 }).Count
        NonemptyFirstRangeEqualsBBlockPlusOne = @($feedback | Where-Object {
            $_.Ranges.Count -gt 0 -and $_.Ranges[0].Start -eq $_.B/200+1 }).Count
        LastA = $feedback[-1].A
        LastB = $feedback[-1].B
        LastRangeCount = $feedback[-1].Ranges.Count
        Interpretation = 'Range membership correlation uses latest captured feedback only; sparse capture cannot establish causation or a complete sender buffer model.'
    }
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'buffer-feedback-results.json')
$results | Format-List
