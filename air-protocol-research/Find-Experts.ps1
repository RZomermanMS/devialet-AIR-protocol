param(
    [int]$CaptureInterface=5,
    [string]$ExpertAddress,
    [string]$ExpertName,
    [ValidateRange(-1,14)][int]$NetworkInputIndex=-1
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Discovery.ps1')
$inventory=Find-AirExperts -CaptureInterface $CaptureInterface
$devices=@($inventory.Devices)
if($ExpertAddress -or $ExpertName) {
    $devices=@(Select-AirExpert -Devices $devices -ExpertAddress $ExpertAddress -ExpertName $ExpertName)
}
if($devices.Count -eq 0) { throw 'No valid Expert status observed on this interface' }
$busy=@(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object LocalPort -eq 45456).Count -gt 0
foreach($device in $devices) {
    [pscustomobject]@{
        Address=$device.Address; Name=$device.Name; Fresh=$device.Fresh
        PowerOn=$device.Status.PowerOn; Muted=$device.Status.Muted
        VolumeDb=$device.Status.Volume; SelectedInput=$device.Status.Channel
        EnabledInputs=@($device.Status.Inputs | Where-Object Enabled)
        Readiness=(Get-AirReadiness -Device $device -NetworkInputIndex $NetworkInputIndex -LocalPortBusy $busy)
    }
}
