$ErrorActionPreference = 'Stop'
$b = [IO.File]::ReadAllBytes('C:\Program Files (x86)\Devialet\AIR\DevialetAIR.exe')
$pe = [BitConverter]::ToInt32($b, 60)
$sectionCount = [BitConverter]::ToUInt16($b, $pe + 6)
$optionalSize = [BitConverter]::ToUInt16($b, $pe + 20)
$sections = for ($i = 0; $i -lt $sectionCount; $i++) {
    $o = $pe + 24 + $optionalSize + $i * 40
    [pscustomobject]@{
        RVA = [BitConverter]::ToUInt32($b, $o + 12)
        Size = [BitConverter]::ToUInt32($b, $o + 16)
        Offset = [BitConverter]::ToUInt32($b, $o + 20)
        Name = [Text.Encoding]::ASCII.GetString($b, $o, 8).Trim([char]0)
    }
}
$image = New-Object byte[] ([BitConverter]::ToUInt32($b, $pe + 24 + 56))
foreach ($s in $sections) { [Array]::Copy($b, $s.Offset, $image, $s.RVA, $s.Size) }
$text = [Text.Encoding]::ASCII.GetString($image)
$targets = @{}
foreach ($match in [regex]::Matches($text, '[\x20-\x7E]{8,}')) {
    if ($match.Value -match 'DeltaRLEPacketizer|DacodecPacketizer|Dacodec|DeltaRLE') {
        $targets[$match.Index] = $match.Value
    }
}
$code = $sections | Where-Object Name -eq '.text'
$results = for ($i = [int]$code.RVA; $i -lt $code.RVA + $code.Size - 7; $i++) {
    if ($image[$i] -in @(0x48, 0x4C) -and $image[$i + 1] -eq 0x8D -and ($image[$i + 2] -band 0xC7) -eq 5) {
        $target = $i + 7 + [BitConverter]::ToInt32($image, $i + 3)
        if ($targets.ContainsKey($target)) {
            [pscustomobject]@{ InstructionRVA = '0x{0:X}' -f $i; StringRVA = '0x{0:X}' -f $target; Identifier = $targets[$target] }
        }
    }
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'encoder-references.json')
$results | Where-Object { $_.Identifier -notmatch '\.cpp$' } | Format-List
