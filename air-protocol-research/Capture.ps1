. (Join-Path $PSScriptRoot 'Common.ps1')
function ConvertFrom-AirWifiFrame([byte[]]$Frame, [UInt64]$TimestampRaw, [int]$PacketIndex) {
    Assert-AirRange $Frame 0 24
    if (($Frame[0] -band 15) -ne 8) { throw 'Unsupported WiFi frame type/version' }
    if ($Frame[0] -ne 8 -and $Frame[0] -ne 136) { throw 'Unsupported WiFi data subtype' }
    if ($Frame[1] -band 0x40) { throw 'Encrypted WiFi frame unsupported' }
    if (($Frame[1] -band 4) -or ($Frame[22] -band 15)) { throw 'Fragmented WiFi requires reassembly' }
    $header = 24
    if (($Frame[1] -band 3) -eq 3) { $header += 6 }
    $qos = ($Frame[0] -band 128) -ne 0
    if ($qos) {
        Assert-AirRange $Frame $header 2
        if ($Frame[$header] -band 128) { throw 'WiFi A-MSDU aggregation unsupported' }
        $header += 2
    }
    if ($Frame[1] -band 128) {
        if (-not $qos) { throw 'Unsupported ordered non-QoS WiFi frame' }
        $header += 4
    }
    Assert-AirRange $Frame $header 8
    if ([BitConverter]::ToString($Frame,$header,6) -ne 'AA-AA-03-00-00-00') { throw 'Unsupported LLC header' }
    $ether = Get-AirUIntBE $Frame ($header+6) 2
    $record = [ordered]@{ PacketIndex=$PacketIndex; TimestampRaw=$TimestampRaw; Kind='NonIPv4'; Reason=('EtherType 0x{0:X4}' -f $ether) }
    if ($ether -ne 0x0800) { return [pscustomobject]$record }
    $ip = $header+8
    Assert-AirRange $Frame $ip 20
    $ihl = ($Frame[$ip] -band 15)*4
    if (($Frame[$ip] -shr 4) -ne 4 -or $ihl -lt 20) { throw 'Invalid IPv4 version/header length' }
    Assert-AirRange $Frame $ip $ihl
    $ipLength = [int](Get-AirUIntBE $Frame ($ip+2) 2)
    if ($ipLength -lt $ihl) { throw 'Invalid IPv4 total length' }
    Assert-AirRange $Frame $ip $ipLength
    $record.Source = $Frame[($ip+12)..($ip+15)] -join '.'
    $record.Destination = $Frame[($ip+16)..($ip+19)] -join '.'
    $record.Protocol = [int]$Frame[$ip+9]
    if ($record.Protocol -ne 17) { $record.Kind='NonUDP'; $record.Reason="IP protocol $($record.Protocol)"; return [pscustomobject]$record }
    if ((Get-AirUIntBE $Frame ($ip+6) 2) -band 0x3FFF) { throw 'Fragmented IPv4 UDP requires reassembly' }
    if ($ipLength -lt $ihl+8) { throw 'Truncated UDP header' }
    $udp = $ip+$ihl
    $length = [int](Get-AirUIntBE $Frame ($udp+4) 2)
    if ($length -lt 8 -or $length -ne $ipLength-$ihl) { throw 'Invalid UDP length' }
    Assert-AirRange $Frame $udp $length
    $record.Kind='UDP'; $record.Reason=''
    $record.SourcePort=Get-AirUIntBE $Frame $udp 2
    $record.DestinationPort=Get-AirUIntBE $Frame ($udp+2) 2
    $record.PayloadLength=$length-8
    $record.PayloadHex=[BitConverter]::ToString($Frame,$udp+8,$length-8).Replace('-','')
    return [pscustomobject]$record
}
function Read-AirCapture([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $reader=New-Object IO.BinaryReader($stream)
    $links=New-Object 'Collections.Generic.List[int]'
    $section=$false; $index=0
    try {
        while ($stream.Position -lt $stream.Length) {
            if ($stream.Length-$stream.Position -lt 12) { throw 'Truncated pcapng block' }
            $type=$reader.ReadUInt32(); $length=$reader.ReadUInt32()
            if ($length -lt 12 -or $length%4 -ne 0 -or $length-8 -gt $stream.Length-$stream.Position) { throw 'Invalid pcapng block length' }
            $body=$reader.ReadBytes($length-12)
            if ($reader.ReadUInt32() -ne $length) { throw 'Invalid pcapng block trailer' }
            if ($type -eq 0x0A0D0D0A) {
                Assert-AirRange $body 0 16
                if ([BitConverter]::ToUInt32($body,0) -ne 0x1A2B3C4D) { throw 'Only little-endian pcapng supported' }
                if ([BitConverter]::ToUInt16($body,4) -ne 1) { throw 'Unsupported pcapng version' }
                $links.Clear(); $section=$true
            } elseif (-not $section) { throw 'Missing pcapng section header' }
            elseif ($type -eq 1) {
                Assert-AirRange $body 0 8
                $link=[BitConverter]::ToUInt16($body,0)
                if ($link -ne 105) { throw "Unsupported linktype $link; use corrected native-WiFi linktype105 capture, not mislabeled original" }
                # Only default microsecond timestamp resolution is accepted.
                $option=8
                while ($option -lt $body.Length) {
                    Assert-AirRange $body $option 4
                    $code=[BitConverter]::ToUInt16($body,$option); $size=[BitConverter]::ToUInt16($body,$option+2); $option+=4
                    Assert-AirRange $body $option $size
                    if ($code -eq 0) { if ($size -ne 0) { throw 'Invalid end-of-options' }; break }
                    if ($code -eq 9 -and ($size -ne 1 -or $body[$option] -ne 6)) { throw 'Non-microsecond timestamps unsupported' }
                    if ($code -eq 14) { throw 'Timestamp offset option unsupported' }
                    $option += [int](4*[Math]::Ceiling($size/4.0))
                }
                $links.Add($link)
            } elseif ($type -eq 6) {
                Assert-AirRange $body 0 20
                $interface=[BitConverter]::ToUInt32($body,0)
                if ($interface -ge $links.Count) { throw 'Invalid capture interface index' }
                $captured=[BitConverter]::ToUInt32($body,12); $original=[BitConverter]::ToUInt32($body,16)
                if ($captured -ne $original) { throw 'Snaplen-truncated capture packet unsupported' }
                Assert-AirRange $body 20 ([int]$captured)
                $frame=New-Object byte[] $captured; [Array]::Copy($body,20,$frame,0,$captured)
                [UInt64]$timestamp=([UInt64][BitConverter]::ToUInt32($body,4)*4294967296)+[BitConverter]::ToUInt32($body,8)
                $index++
                ConvertFrom-AirWifiFrame $frame $timestamp $index
            } elseif ($type -eq 2 -or $type -eq 3) { throw 'Unsupported legacy/simple packet block' }
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
}
