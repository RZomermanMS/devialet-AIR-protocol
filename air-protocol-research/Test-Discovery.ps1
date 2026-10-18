$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Discovery.ps1')
$script:passed=0
function Check($Name,[scriptblock]$Test) {
    if(-not (& $Test)) { throw "FAIL: $Name" }
    $script:passed++
    "PASS: $Name"
}
function Rejects([scriptblock]$Action,$Message) {
    try { & $Action | Out-Null } catch { return $_.Exception.Message -like "*$Message*" }
    return $false
}
function StatusHex([int]$Length=345,[bool]$Powered=$true,[bool]$Muted=$false,[int]$Channel=10) {
    $bytes=New-Object byte[] $Length
    $bytes[0]=0x44; $bytes[1]=0x61
    [Text.Encoding]::ASCII.GetBytes('FixtureExpert').CopyTo($bytes,19)
    for($i=0;$i -lt 15;$i++) { $bytes[52+17*$i]=0x30 }
    $bytes[52+17*10]=0x31
    [Text.Encoding]::ASCII.GetBytes('WiFi').CopyTo($bytes,53+17*10)
    if($Powered) { $bytes[307]=0x80 }
    $bytes[308]=($Channel -shl 2)
    if($Muted) { $bytes[308]=$bytes[308] -bor 2 }
    $bytes[310]=115
    $crc=Get-AirCrc16 $bytes ($Length-2)
    $bytes[$Length-2]=[byte]($crc -shr 8); $bytes[$Length-1]=[byte]($crc -band 255)
    ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
}
function Observation($Hex,$Source='192.0.2.10',$Time=99,$Port=45454,$Destination='192.0.2.255',$DestinationPort=45454) {
    [pscustomobject]@{Hex=$Hex; Source=$Source; Time=$Time; SourcePort=$Port; Destination=$Destination; DestinationPort=$DestinationPort}
}
$hex=StatusHex
$inventory=Get-AirDeviceInventory @(Observation $hex) 100
$device=Select-AirExpert $inventory.Devices
Check '345-byte status decodes fields and enabled flags' {
    $device.Name -eq 'FixtureExpert' -and $device.Status.Volume -eq -40 -and
    $device.Status.Inputs[10].Enabled -and -not $device.Status.Inputs[0].Enabled
}
Check '512-byte status has trailing CRC and matching field layout' {
    $status=ConvertFrom-AirDa (ConvertFrom-AirHex (StatusHex 512))
    $status.Length -eq 512 -and $status.Channel -eq 10 -and $status.CrcValid
}
Check 'Bad CRC rejected' {
    Rejects { ConvertFrom-AirDa (ConvertFrom-AirHex ($hex.Substring(0,$hex.Length-4)+'0000')) } 'CRC'
}
Check 'Truncated status rejected' { Rejects { ConvertFrom-AirDa (New-Object byte[] 344) } 'length' }
Check 'Powered unmuted WiFi is startup eligible' { (Get-AirReadiness $device).Eligible }
Check 'Occupied local port blocks startup' { -not (Get-AirReadiness $device -LocalPortBusy $true).Eligible }
Check 'Stale status blocks startup' {
    $stale=(Get-AirDeviceInventory @(Observation $hex) 102).Devices[0]
    -not (Get-AirReadiness $stale).Eligible
}
Check 'Standby blocks startup' {
    $off=(Get-AirDeviceInventory @(Observation (StatusHex -Powered $false)) 100).Devices[0]
    -not (Get-AirReadiness $off).Eligible
}
Check 'Mute blocks startup' {
    $muted=(Get-AirDeviceInventory @(Observation (StatusHex -Muted $true)) 100).Devices[0]
    -not (Get-AirReadiness $muted).Eligible
}
Check 'Wrong input blocks startup' {
    $other=(Get-AirDeviceInventory @(Observation (StatusHex -Channel 1)) 100).Devices[0]
    -not (Get-AirReadiness $other).Eligible
}
Check 'Renamed input requires explicit selection' {
    $renamed=(Get-AirDeviceInventory @(Observation $hex) 100).Devices[0]
    $renamed.Status.Inputs[10].Label='My input'
    -not (Get-AirReadiness $renamed).Eligible -and (Get-AirReadiness $renamed -NetworkInputIndex 10).Eligible
}
Check 'Disabled explicit input blocks startup' { -not (Get-AirReadiness $device -NetworkInputIndex 1).Eligible }
Check 'Multiple Experts require selection' {
    $many=(Get-AirDeviceInventory @((Observation $hex),(Observation $hex '192.0.2.11')) 100).Devices
    (Rejects { Select-AirExpert $many } 'Multiple') -and
    (Select-AirExpert $many -ExpertAddress '192.0.2.11').Address -eq '192.0.2.11'
}
Check 'Duplicate names remain ambiguous' {
    $many=(Get-AirDeviceInventory @((Observation $hex),(Observation $hex '192.0.2.11')) 100).Devices
    Rejects { Select-AirExpert $many -ExpertName 'FixtureExpert' } 'Multiple'
}
Check 'Missing requested Expert fails explicitly' { Rejects { Select-AirExpert $inventory.Devices -ExpertAddress '192.0.2.99' } 'No matching' }
Check 'Future timestamp rejected' { Rejects { Get-AirDeviceInventory @(Observation $hex) 98 } 'future' }
$dm='446d'+('00'*20)
Check 'Observed Dm blocks target but not unrelated Expert' {
    $busy=(Get-AirDeviceInventory @((Observation $hex),(Observation $dm '192.0.2.20' 98 45456 '192.0.2.10' 45455)) 100).Devices[0]
    $other=(Get-AirDeviceInventory @((Observation $hex),(Observation $dm '192.0.2.20' 98 45456 '192.0.2.11' 45455)) 100).Devices[0]
    -not (Get-AirReadiness $busy).Eligible -and (Get-AirReadiness $other).Eligible
}
Check 'Status from wrong UDP port ignored' { (Get-AirDeviceInventory @(Observation $hex -Port 1234) 100).Devices.Count -eq 0 }
Check 'Latest valid state wins even with out-of-order input' {
    $latest=(Get-AirDeviceInventory @((Observation $hex -Time 99),(Observation (StatusHex -Powered $false) -Time 98)) 100).Devices[0]
    $latest.Status.PowerOn
}
function Find-AirExperts { param([int]$CaptureInterface) $script:fixtureInventory }
function Get-NetUDPEndpoint { [CmdletBinding()] param() if($script:fixtureBusy) { [pscustomobject]@{LocalPort=45456} } }
function Find-NetRoute { [CmdletBinding()] param([string]$RemoteIPAddress) [pscustomobject]@{IPAddress='192.0.2.20'} }
$script:fixtureInventory=$inventory
$script:fixtureBusy=$false
Check 'Sender target resolves discovered address and local route' {
    $target=Get-AirSenderTarget
    $target.ExpertAddress -eq '192.0.2.10' -and $target.LocalAddress -eq '192.0.2.20'
}
Check 'Sender target refuses occupied port before returning a destination' {
    $script:fixtureBusy=$true
    Rejects { Get-AirSenderTarget } 'preflight refused'
}
$script:fixtureBusy=$false
Check 'Sender target refuses observed competing traffic' {
    $script:fixtureInventory=Get-AirDeviceInventory @((Observation $hex),(Observation $dm '192.0.2.20' 98 45456 '192.0.2.10' 45455)) 100
    Rejects { Get-AirSenderTarget } 'AIR traffic observed'
}
"Tests: $script:passed passed"
