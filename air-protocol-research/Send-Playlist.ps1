param(
    [Parameter(Mandatory=$true)][string[]]$Mp3,
    [double]$Gain = 0.25,
    [ValidateRange(0,2147483647)][int]$MaxSeconds = 0,
    [int]$CaptureInterface = 5,
    [string]$ExpertAddress,
    [string]$ExpertName,
    [ValidateRange(-1,14)][int]$NetworkInputIndex = -1,
    [ValidateSet(44100,48000)][int]$SampleRate = 48000,
    [switch]$ExperimentalRate,
    [string]$StopFile
)
$ErrorActionPreference='Stop'
if($Mp3.Count -eq 0) { throw 'Playlist is empty.' }
if([double]::IsNaN($Gain) -or [double]::IsInfinity($Gain) -or $Gain -le 0 -or $Gain -gt 3) {
    throw 'Require finite gain in (0,3].'
}
if($SampleRate -eq 44100 -and -not $ExperimentalRate) { throw '44.1k mode requires -ExperimentalRate.' }
$tracks=@($Mp3 | ForEach-Object {
    $item=Get-Item -LiteralPath $_
    if($item.PSIsContainer) { throw "Not an audio file: $_" }
    $item.FullName
})
if($StopFile) {
    $StopFile=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StopFile)
    if(Test-Path -LiteralPath $StopFile) { throw 'Stop file already exists; remove it explicitly before starting.' }
}
$runId=[Guid]::NewGuid().ToString('N')
for($i=0;$i -lt $tracks.Count;$i++) {
    if($StopFile -and (Test-Path -LiteralPath $StopFile)) { throw 'Playlist stopped before next track.' }
    $arguments=@(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Send-Mp3.ps1'),
        '-Mp3',$tracks[$i],'-Gain',$Gain,'-MaxSeconds',$MaxSeconds,
        '-CaptureInterface',$CaptureInterface,'-NetworkInputIndex',$NetworkInputIndex,
        '-SampleRate',$SampleRate,'-Stem',("air-playlist-$runId-track"+($i+1))
    )
    if($ExpertAddress) { $arguments+=@('-ExpertAddress',$ExpertAddress) }
    if($ExpertName) { $arguments+=@('-ExpertName',$ExpertName) }
    if($ExperimentalRate) { $arguments+='-ExperimentalRate' }
    if($StopFile) { $arguments+=@('-StopFile',$StopFile) }
    "TRACK $($i+1)/$($tracks.Count): $($tracks[$i])"
    & powershell.exe @arguments
    if($LASTEXITCODE -ne 0) { throw "Track $($i+1) failed or was stopped (exit $LASTEXITCODE); remaining tracks were not started." }
}
"PLAYLIST ACKNOWLEDGED: $($tracks.Count) tracks; separate sessions, not gapless; acoustic playout not verified."
