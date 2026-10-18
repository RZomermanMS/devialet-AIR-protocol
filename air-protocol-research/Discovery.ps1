Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'Feedback.ps1')

function Get-AirDeviceInventory {
    param([object[]]$Packets, [double]$NowSeconds, [ValidateRange(0.1,60)][double]$StatusMaxAge=2)
    $devices=@{}; $streams=@{}; $rejected=0
    foreach($packet in $Packets) {
        if([double]$packet.Time -gt $NowSeconds) { throw 'Observation timestamp is in the future' }
        $hex=[string]$packet.Hex
        if($hex.StartsWith('446d',[StringComparison]::OrdinalIgnoreCase) -and $packet.DestinationPort -eq 45455 -and $hex.Length -ge 44) {
            $destination=[string]$packet.Destination
            if(-not $streams.ContainsKey($destination)) { $streams[$destination]=@{} }
            $streams[$destination][[string]$packet.Source]=[double]$packet.Time
        }
        if($packet.SourcePort -ne 45454 -or -not $hex.StartsWith('4461',[StringComparison]::OrdinalIgnoreCase)) { continue }
        try { $status=ConvertFrom-AirDa (ConvertFrom-AirHex $hex) }
        catch { $rejected++; Write-Warning "Rejected status from $($packet.Source): $($_.Exception.Message)"; continue }
        $ip=[string]$packet.Source
        if(-not $devices.ContainsKey($ip) -or $devices[$ip].LastSeen -le [double]$packet.Time) {
            $devices[$ip]=[pscustomobject]@{
                Address=$ip; Name=$status.Name; LastSeen=[double]$packet.Time
                Fresh=$false; Status=$status; ObservedSenders=@()
            }
        }
    }
    foreach($device in $devices.Values) {
        $device.Fresh=($NowSeconds-$device.LastSeen -le $StatusMaxAge)
        if($streams.ContainsKey($device.Address)) {
            # Any stream observed during this preflight blocks a new sender.
            $device.ObservedSenders=@($streams[$device.Address].Keys | Sort-Object)
        }
    }
    [pscustomobject]@{ Devices=@($devices.Values | Sort-Object Address); RejectedStatus=$rejected }
}

function Select-AirExpert {
    param([object[]]$Devices, [string]$ExpertAddress, [string]$ExpertName)
    $matches=@($Devices | Where-Object {
        ([string]::IsNullOrEmpty($ExpertAddress) -or $_.Address -eq $ExpertAddress) -and
        ([string]::IsNullOrEmpty($ExpertName) -or $_.Name -eq $ExpertName)
    })
    if($matches.Count -eq 0) { throw 'No matching Expert discovered; check power, network and capture interface.' }
    if($matches.Count -gt 1) { throw 'Multiple Experts match; specify -ExpertAddress or a unique -ExpertName.' }
    $matches[0]
}

function Get-AirReadiness {
    param($Device, [ValidateRange(-1,14)][int]$NetworkInputIndex=-1, [bool]$LocalPortBusy=$false)
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    if(-not $Device.Fresh) { $reasons.Add('Status is stale') }
    if(-not $Device.Status.PowerOn) { $reasons.Add('Expert is in standby') }
    if($Device.Status.Muted) { $reasons.Add('Expert is muted') }
    if($Device.ObservedSenders.Count -gt 0) { $reasons.Add('AIR traffic observed from '+($Device.ObservedSenders -join ', ')) }
    if($LocalPortBusy) { $reasons.Add('Local UDP 45456 is occupied') }
    $inputs=@($Device.Status.Inputs | Where-Object { $_.Enabled })
    if($NetworkInputIndex -lt 0) {
        $network=@($inputs | Where-Object { $_.Label -match '^(Wi[ -]?Fi|Ethernet|AIR)$' })
        if($network.Count -eq 1) { $NetworkInputIndex=$network[0].Index }
        else { $reasons.Add('Network input is ambiguous; specify -NetworkInputIndex explicitly') }
    }
    if($NetworkInputIndex -ge 0) {
        if(@($inputs | Where-Object Index -eq $NetworkInputIndex).Count -ne 1) { $reasons.Add('Requested network input is not enabled') }
        if($Device.Status.Channel -ne $NetworkInputIndex) { $reasons.Add('Expert is not on the requested network input') }
    }
    [pscustomobject]@{
        Eligible=($reasons.Count -eq 0); Reasons=@($reasons.ToArray())
        NetworkInputIndex=$NetworkInputIndex
        Scope='Passive startup preflight only; not an AIR handshake or network-wide ownership proof'
    }
}

function Find-AirExperts {
    param(
        [ValidateRange(1,10000)][int]$CaptureInterface=5,
        [ValidateRange(3,15)][int]$Seconds=4,
        [string]$WiresharkDirectory='C:\Program Files\Wireshark'
    )
    $dumpcap=Join-Path $WiresharkDirectory 'dumpcap.exe'
    $tshark=Join-Path $WiresharkDirectory 'tshark.exe'
    foreach($tool in @($dumpcap,$tshark)) { if(-not(Test-Path -LiteralPath $tool)) { throw "Missing capture tool: $tool" } }
    $capture=Join-Path ([IO.Path]::GetTempPath()) ("air-discovery-"+[Guid]::NewGuid().ToString('N')+'.pcapng')
    $errors=$capture+'.stderr'; $process=$null
    try {
        $process=Start-Process -FilePath $dumpcap -ArgumentList @('-i',"$CaptureInterface",'-a',"duration:$Seconds",'-f','"udp port 45454 or udp dst port 45455"','-w',('"' + $capture + '"'),'-q') -PassThru -WindowStyle Hidden -RedirectStandardError $errors
        # Cache the handle before exit so Windows PowerShell retains ExitCode.
        $null=$process.Handle
        if(-not $process.WaitForExit(($Seconds+15)*1000)) { throw 'Passive discovery capture timed out' }
        $process.Refresh()
        if($process.ExitCode -ne 0) { throw "Passive discovery capture failed: $(Get-Content -LiteralPath $errors -Raw)" }
        $now=([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()/1000.0)
        $rows=@(& $tshark -n -r $capture -T fields -e frame.time_epoch -e ip.src -e ip.dst -e udp.srcport -e udp.dstport -e udp.payload 2> $errors)
        if($LASTEXITCODE -ne 0) { throw "Discovery parsing failed: $(Get-Content -LiteralPath $errors -Raw)" }
        $packets=@(foreach($row in $rows) {
            $f=$row -split "`t"
            if($f.Count -ne 6 -or [string]::IsNullOrEmpty($f[1])) { continue }
            [pscustomobject]@{
                Time=[double]::Parse($f[0],[Globalization.CultureInfo]::InvariantCulture)
                Source=$f[1]; Destination=$f[2]; SourcePort=[int]$f[3]; DestinationPort=[int]$f[4]; Hex=$f[5]
            }
        })
        Get-AirDeviceInventory -Packets $packets -NowSeconds $now
    } finally {
        if($null -ne $process) {
            if(-not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction Stop }
            $process.Dispose()
        }
        foreach($path in @($capture,$errors)) { if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop } }
    }
}

function Get-AirSenderTarget {
    param([int]$CaptureInterface=5, [string]$ExpertAddress, [string]$ExpertName, [int]$NetworkInputIndex=-1)
    $inventory=Find-AirExperts -CaptureInterface $CaptureInterface
    $device=Select-AirExpert -Devices $inventory.Devices -ExpertAddress $ExpertAddress -ExpertName $ExpertName
    $busy=@(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object LocalPort -eq 45456).Count -gt 0
    $readiness=Get-AirReadiness -Device $device -NetworkInputIndex $NetworkInputIndex -LocalPortBusy $busy
    if(-not $readiness.Eligible) { throw ('AIR preflight refused: '+($readiness.Reasons -join '; ')) }
    $route=Find-NetRoute -RemoteIPAddress $device.Address -ErrorAction Stop
    $local=@($route | Where-Object { $_.PSObject.Properties.Name -contains 'IPAddress' } | Select-Object -ExpandProperty IPAddress -Unique)
    if($local.Count -ne 1) { throw 'Could not determine a unique local IPv4 source for the selected Expert' }
    [pscustomobject]@{ ExpertAddress=$device.Address; LocalAddress=$local[0]; Device=$device; Readiness=$readiness }
}
