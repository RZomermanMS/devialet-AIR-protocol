param(
    [int]$CaptureInterface=5,
    [string]$ExpertAddress,
    [string]$ExpertName,
    [switch]$DefinitionsOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Discovery.ps1')

function New-AirInputCommand {
    param([ValidateRange(0,14)][int]$InputIndex, [byte]$Sequence)
    $packet=New-Object byte[] 142
    $packet[0]=0x44; $packet[1]=0x72
    $packet[3]=$Sequence; $packet[5]=$Sequence -shr 1
    $packet[7]=5
    $value=0x4000 -bor ($InputIndex -shl 5)
    $packet[8]=[byte]($value -shr 8)
    $low=$value -band 255
    if($InputIndex -gt 7) { $low=$low -shr 1 }
    $packet[9]=[byte]$low
    $crc=Get-AirCrc16 $packet 12
    $packet[12]=[byte]($crc -shr 8); $packet[13]=[byte]($crc -band 255)
    ,$packet
}

if($DefinitionsOnly) { return }
$inventory=Find-AirExperts -CaptureInterface $CaptureInterface
$device=Select-AirExpert -Devices $inventory.Devices -ExpertAddress $ExpertAddress -ExpertName $ExpertName
if(-not $device.Fresh) { throw 'Selected Expert status is stale' }
if(-not $device.Status.PowerOn) { throw 'Expert is in standby; power will not be changed' }
$wifi=@($device.Status.Inputs | Where-Object { $_.Enabled -and $_.Label -match '^Wi[ -]?Fi$' })
if($wifi.Count -ne 1) { throw 'Exactly one enabled Wi-Fi input is required; refusing to guess' }
$index=$wifi[0].Index
$before=$device.Status
"Expert $($device.Name) at $($device.Address): input $($before.Channel), volume $($before.Volume) dB, muted=$($before.Muted)"
if($before.Channel -ne $index) {
    $udp=New-Object Net.Sockets.UdpClient
    try {
        $endpoint=New-Object Net.IPEndPoint ([Net.IPAddress]::Parse($device.Address)),45455
        for($sequence=0;$sequence -lt 4;$sequence++) {
            $command=New-AirInputCommand -InputIndex $index -Sequence $sequence
            [void]$udp.Send($command,$command.Length,$endpoint)
        }
    } finally { $udp.Dispose() }
    "Sent input-selection command for Wi-Fi (input $index)."
} else { "Already on Wi-Fi (input $index); no command sent." }
$afterInventory=Find-AirExperts -CaptureInterface $CaptureInterface
$after=Select-AirExpert -Devices $afterInventory.Devices -ExpertAddress $device.Address
if(-not $after.Fresh -or $after.Status.Channel -ne $index) { throw 'Wi-Fi selection was not confirmed by fresh status' }
if($after.Status.Volume -ne $before.Volume -or $after.Status.Muted -ne $before.Muted -or $after.Status.PowerOn -ne $before.PowerOn) {
    throw 'Wi-Fi selected, but another device state changed during verification; no automatic correction attempted'
}
"Confirmed Wi-Fi input $index. Volume remains $($after.Status.Volume) dB; mute and power unchanged."
