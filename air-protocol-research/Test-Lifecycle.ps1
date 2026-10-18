param(
    [Parameter(Mandatory=$true)][string]$Mp3,
    [int]$CaptureInterface = 5,
    [Parameter(Mandatory=$true)][string]$ExpertAddress,
    [ValidateRange(0,14)][int]$NetworkInputIndex,
    [double]$Gain = 0.25
)
$ErrorActionPreference='Stop'
function Quote-Literal([string]$Value) { "'"+$Value.Replace("'","''")+"'" }
$Mp3=(Get-Item -LiteralPath $Mp3).FullName
$id=[Guid]::NewGuid().ToString('N')
$stem=Join-Path $PSScriptRoot "air-lifecycle-$id"
$stop="$stem.stop"
$output="$stem.log"
$errors="$stem-error.log"
$playlist=Quote-Literal (Join-Path $PSScriptRoot 'Send-Playlist.ps1')
$source=Quote-Literal $Mp3
$command="& $playlist -Mp3 @($source,$source) -MaxSeconds 30 -SampleRate 44100 -ExperimentalRate"+
    " -Gain $Gain -CaptureInterface $CaptureInterface -ExpertAddress $(Quote-Literal $ExpertAddress)"+
    " -NetworkInputIndex $NetworkInputIndex -StopFile $(Quote-Literal $stop)"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$child=$null
try {
    $child=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) `
        -RedirectStandardOutput $output -RedirectStandardError $errors -PassThru -WindowStyle Hidden
    $null=$child.Handle
    $wait=[Diagnostics.Stopwatch]::StartNew()
    $started=$false
    while(-not $child.HasExited -and $wait.Elapsed.TotalSeconds -lt 60) {
        if(Test-Path -LiteralPath $output) {
            if(Select-String -LiteralPath $output -Pattern 'elapsed=5\.' -Quiet) { $started=$true;break }
        }
        Start-Sleep -Milliseconds 100
    }
    if(-not $started) { throw "Playback did not reach five seconds; inspect $output and $errors" }
    [IO.File]::WriteAllText($stop,'stop')
    if(-not $child.WaitForExit(15000)) { throw 'Stop request did not terminate playlist within 15 seconds.' }
    $child.Refresh()
    if($child.ExitCode -eq 0) { throw 'Stopped playlist incorrectly reported success.' }
    if(Select-String -LiteralPath $output -Pattern 'TRACK 2/2' -Quiet) { throw 'Second track started after stop.' }
    if(-not (Select-String -LiteralPath $errors -Pattern 'Playback stopped' -Quiet)) {
        throw "Playlist failed for an unexpected reason; inspect $errors"
    }
    if(@(Get-NetUDPEndpoint | Where-Object LocalPort -eq 45456).Count) { throw 'Sender socket still bound after stop.' }
    'PASS: live stop propagated as cancellation/failure, suppressed second track, released socket.'
    Remove-Item -LiteralPath $stop
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Send-Mp3.ps1') `
        -Mp3 $Mp3 -MaxSeconds 6 -SampleRate 44100 -ExperimentalRate -Gain $Gain `
        -CaptureInterface $CaptureInterface -ExpertAddress $ExpertAddress -NetworkInputIndex $NetworkInputIndex `
        -Stem "air-lifecycle-$id-reconnect"
    if($LASTEXITCODE -ne 0) { throw 'Reconnect playback failed.' }
    if(@(Get-NetUDPEndpoint | Where-Object LocalPort -eq 45456).Count) { throw 'Sender socket still bound after reconnect.' }
    'PASS: fresh automatic session reconnected and acknowledged playback after explicit stop.'
    "Lifecycle logs: $output and $errors"
} finally {
    if($null -ne $child -and -not $child.HasExited) { Stop-Process -Id $child.Id }
    if(Test-Path -LiteralPath $stop) { Remove-Item -LiteralPath $stop }
}
