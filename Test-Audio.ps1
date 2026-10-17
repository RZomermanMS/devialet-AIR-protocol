Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Audio.ps1')

function Assert-AudioEqual($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message. Expected '$Expected', got '$Actual'." }
}

function New-TestDmHex([UInt64]$Counter, [byte[]]$Body) {
    $bytes = New-Object byte[] (22 + $Body.Length)
    $bytes[0] = 0x44
    $bytes[1] = 0x6d
    $bytes[2] = 0x02
    $bytes[11] = 0x02
    for ($i = 0; $i -lt 8; $i++) { $bytes[12 + $i] = [byte](($Counter -shr (56 - (8 * $i))) -band 255) }
    $bytes[20] = 0
    $bytes[21] = 0xc8
    [Array]::Copy($Body, 0, $bytes, 22, $Body.Length)
    return ([BitConverter]::ToString($bytes)).Replace('-', '')
}

$testCount = 0
try { ConvertFrom-AirDm ([byte[]](0x44, 0x6d)) | Out-Null; throw 'Truncated input was accepted' } catch { if ($_.Exception.Message -eq 'Truncated input was accepted') { throw }; $testCount++ }
try { ConvertFrom-AirDm ([byte[]](0x00, 0x6d) + (New-Object byte[] 20)) | Out-Null; throw 'Bad magic was accepted' } catch { if ($_.Exception.Message -eq 'Bad magic was accepted') { throw }; $testCount++ }
$parsed = ConvertFrom-AirDm (ConvertFrom-AirHex (New-TestDmHex 200 ([byte[]](1, 2, 3, 4))))
Assert-AudioEqual $parsed.SampleCounter 200 'BE64 counter parse'
Assert-AudioEqual $parsed.SampleCount 200 'BE16 sample count parse'
Assert-AudioEqual $parsed.BodyLength 4 'Body length parse'
Assert-AudioEqual $parsed.Mode 2 'Mode byte 11 parse'
$testCount += 4

$synthetic = @(
    [pscustomobject]@{ TimestampRaw = '1'; PayloadHex = New-TestDmHex 200 ([byte[]](1, 2, 3, 4)) },
    [pscustomobject]@{ TimestampRaw = '2'; PayloadHex = New-TestDmHex 0 ([byte[]](5, 6, 7, 8)) },
    [pscustomobject]@{ TimestampRaw = '3'; PayloadHex = New-TestDmHex 200 ([byte[]](1, 2, 3, 4)) }
)
$syntheticResult = Get-AirAudioAnalysis $synthetic
Assert-AudioEqual $syntheticResult.UniqueCounterCount 2 'Unique counter count'
Assert-AudioEqual $syntheticResult.DuplicateCounterOccurrences 1 'Duplicate occurrence count'
Assert-AudioEqual $syntheticResult.IdenticalDuplicateOccurrences 1 'Identical duplicate count'
Assert-AudioEqual $syntheticResult.ArrivalCounterDecreases 1 'Reordered arrival count'
Assert-AudioEqual $syntheticResult.CounterGridStep 200 'Counter grid step'
Assert-AudioEqual $syntheticResult.MissingGridPositionsWithinRange 0 'Missing grid count'
$testCount += 6

$inputRoot = 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09'
$sessionPackets = @(Import-Csv -LiteralPath (Join-Path $inputRoot 'air-session-packets.csv'))
$actual = Get-AirAudioAnalysis $sessionPackets
Assert-AudioEqual $actual.ParsedDmPacketCount 951 'Controlled Dm packet count'
Assert-AudioEqual $actual.UniqueCounterCount 746 'Controlled unique counter count'
Assert-AudioEqual $actual.IdenticalDuplicateOccurrences 205 'Controlled identical duplicate count'
Assert-AudioEqual $actual.ConflictingDuplicateOccurrences 0 'Controlled conflicting duplicate count'
Assert-AudioEqual $actual.Modes['2'] 951 'Controlled mode byte 11 count'
$testCount += 5

$baselinePrefix = @(
    Import-Csv -LiteralPath (Join-Path $inputRoot 'air-baseline-packets.csv') |
        Where-Object { $_.Prefix -and $_.Prefix.Replace('-', '').StartsWith('446D', 'OrdinalIgnoreCase') } |
        Select-Object -First 1
)[0]
if ($null -eq $baselinePrefix) { throw 'No baseline Dm prefix was found' }
$baselineMode = (ConvertFrom-AirDm (ConvertFrom-AirHex $baselinePrefix.Prefix.Replace('-', ''))).Mode
Assert-AudioEqual $baselineMode 3 'Baseline prefix mode byte 11'
$testCount++

$output = [pscustomobject]@{
    TestStatus = 'Passed'
    FocusedTestCount = $testCount
    Input = 'air-session-packets.csv'
    BaselinePrefixMode = $baselineMode
    Analysis = $actual
}
$output | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'audio-results.json') -Encoding UTF8
Write-Output ("PASS: {0} focused tests; Dm={1}; uniqueCounters={2}" -f $testCount, $actual.ParsedDmPacketCount, $actual.UniqueCounterCount)
