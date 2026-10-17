param([string]$Log)
$d = $PSScriptRoot
& "$d\Drop-Mode.ps1" -Mode resend -Target 360000 -TimeoutSeconds 80 -PostDropSeconds 12
Start-Sleep 25
& "$d\Drop-Mode.ps1" -Mode df -Target 400000 -TimeoutSeconds 80 -PostDropSeconds 12
