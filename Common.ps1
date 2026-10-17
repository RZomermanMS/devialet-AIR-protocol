Set-StrictMode -Version 2
function Assert-AirRange([byte[]]$Bytes, [int]$Offset, [int]$Count) {
    if ($null -eq $Bytes -or $Offset -lt 0 -or $Count -lt 0 -or $Offset -gt $Bytes.Length - $Count) { throw 'Truncated or invalid byte range' }
}
function ConvertFrom-AirHex([string]$Hex) {
    if ($null -eq $Hex -or ($Hex.Length % 2) -ne 0 -or $Hex -notmatch '^[0-9a-fA-F]*$') { throw 'Invalid hex payload' }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($Hex.Substring(2*$i,2),16) }
    return ,$bytes
}
function Get-AirUIntBE([byte[]]$Bytes, [int]$Offset, [int]$Width) {
    if ($Width -lt 1 -or $Width -gt 8) { throw 'Integer width must be 1..8' }
    Assert-AirRange $Bytes $Offset $Width
    [UInt64]$value = 0
    for ($i=0; $i -lt $Width; $i++) { $value = ($value -shl 8) -bor [UInt64]$Bytes[$Offset+$i] }
    return $value
}
function Get-AirCrc16([byte[]]$Bytes, [int]$Count) {
    Assert-AirRange $Bytes 0 $Count
    [int]$crc = 65535
    for ($i=0; $i -lt $Count; $i++) {
        $crc = $crc -bxor ([int]$Bytes[$i] -shl 8)
        for ($bit=0; $bit -lt 8; $bit++) {
            if ($crc -band 32768) { $crc = (($crc -shl 1) -bxor 4129) -band 65535 }
            else { $crc = ($crc -shl 1) -band 65535 }
        }
    }
    return [UInt16]$crc
}
