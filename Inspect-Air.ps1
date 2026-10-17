param(
    [Parameter(Mandatory=$true)][string]$CapturePath,
    [string]$OutputPath=(Join-Path $PSScriptRoot 'inspection.json')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Capture.ps1')
. (Join-Path $PSScriptRoot 'Audio.ps1')
. (Join-Path $PSScriptRoot 'Feedback.ps1')
$frames=@(Read-AirCapture $CapturePath)
$udp=@($frames | Where-Object Kind -eq 'UDP')
$result=[ordered]@{
    CapturePath=$CapturePath
    SHA256=(Get-FileHash -LiteralPath $CapturePath -Algorithm SHA256).Hash
    FrameCount=$frames.Count
    Kinds=@($frames | Group-Object Kind,Reason | Select-Object Name,Count)
    UdpCount=$udp.Count
    Audio=Get-AirAudioAnalysis $udp
    Feedback=(Get-AirFeedbackAnalysis $udp | Select-Object * -ExcludeProperty Dfs,DmSorted,RejectedDetail)
    Limitations=@('Audio codec unestablished; no PCM output','Capture gaps do not prove network loss','Df interval semantics unproven')
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Inspected $($frames.Count) frames / $($udp.Count) UDP; saved $OutputPath"
