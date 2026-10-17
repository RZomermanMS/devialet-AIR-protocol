param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'))
$ErrorActionPreference = 'Stop'
$ts = 'C:\Program Files\Wireshark\tshark.exe'
$rows = & $ts -r $Pcap -Y 'udp' -T fields -e frame.number -e frame.time_relative -e ip.src -e ip.dst -e udp.payload |
    ForEach-Object { $f = $_ -split "`t"; if ($f.Count -ge 5) { [pscustomobject]@{ N = [int]$f[0]; T = [double]$f[1]; Src = $f[2]; Dst = $f[3]; Hex = $f[4] } } }
$dm = foreach ($r in $rows) {
    if ($r.Hex.StartsWith('446d') -and $r.Hex.Length -ge 44) {
        [pscustomobject]@{ N = $r.N; T = $r.T; Src = $r.Src; Dst = $r.Dst; Mode = [Convert]::ToInt32($r.Hex.Substring(22, 2), 16)
            Counter = [Convert]::ToUInt64($r.Hex.Substring(24, 16), 16); Count = [Convert]::ToInt32($r.Hex.Substring(40, 4), 16); Hex = $r.Hex }
    }
}
$df = $rows | Where-Object { $_.Hex.StartsWith('4466') }
"UDP records: $($rows.Count); Dm: $(@($dm).Count); Df: $(@($df).Count); Da: $(@($rows | Where-Object { $_.Hex.StartsWith('4461') }).Count)"
"Dm direction: " + ((@($dm) | Group-Object { "$($_.Src)->$($_.Dst)" } | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join '; ')
"Df direction: " + ((@($df) | Group-Object { "$($_.Src)->$($_.Dst)" } | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join '; ')
$uniq = @($dm | Group-Object Counter)
$sorted = @($uniq | ForEach-Object { [uint64]$_.Name } | Sort-Object)
"Unique counters: $($sorted.Count); duplicate occurrences: $(@($dm).Count - $sorted.Count)"
$step = 200
$gaps = @()
for ($i = 1; $i -lt $sorted.Count; $i++) {
    $d = $sorted[$i] - $sorted[$i - 1]
    if ($d -ne $step) { $gaps += [pscustomobject]@{ After = $sorted[$i - 1]; Next = $sorted[$i]; Delta = $d } }
}
"Counter range: $($sorted[0]) .. $($sorted[-1]); non-200 steps: $($gaps.Count)"
$gaps | Select-Object -First 10 | Format-Table -AutoSize | Out-String
"Mode values: " + ((@($dm) | Group-Object Mode | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join '; ')
