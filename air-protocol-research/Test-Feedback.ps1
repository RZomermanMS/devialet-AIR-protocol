param([string]$CsvPath='C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-session-packets.csv',[string]$OutputPath=(Join-Path $PSScriptRoot 'feedback-results.json'))
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'Feedback.ps1')
$script:tests=@()
function T([string]$Name,[scriptblock]$Body){ try { $r=& $Body; if($r -eq $false){throw 'assertion false'}; $script:tests+=[pscustomobject]@{Name=$Name;Passed=$true;Error=$null} } catch { $script:tests+=[pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message} } }
function Rejects([scriptblock]$Body,[string]$Pattern){ try { & $Body | Out-Null } catch { return ($_.Exception.Message -match $Pattern) }; return $false }
function SetCrc([byte[]]$b){ $c=Get-AirCrc16 $b ($b.Length-2); $b[$b.Length-2]=[byte]($c -shr 8); $b[$b.Length-1]=[byte]($c -band 255); ,$b }
function NewDf([int[]]$iv,[UInt64]$f10=11999){
    $n=$iv.Count/2; $b=New-Object byte[] (41+4*$n); $b[0]=0x44;$b[1]=0x66;$b[4]=0x11;$b[5]=0xBE;$b[9]=3
    for($i=0;$i -lt 8;$i++){ $b[10+$i]=[byte](($f10 -shr (8*(7-$i))) -band 255) }
    $b[24]=0x2E;$b[25]=0x18; $b[37]=[byte]($n -shr 8);$b[38]=[byte]($n -band 255)
    for($i=0;$i -lt $iv.Count;$i++){ $b[39+2*$i]=[byte]($iv[$i] -shr 8); $b[40+2*$i]=[byte]($iv[$i] -band 255) }
    SetCrc $b }
function NewDa(){ $b=New-Object byte[] 345; $b[0]=0x44;$b[1]=0x61
    $nm=[Text.Encoding]::ASCII.GetBytes('Test-Unit'); [Array]::Copy($nm,0,$b,19,$nm.Length)
    for($i=0;$i -lt 15;$i++){ $b[52+17*$i]=0x30; $l=[Text.Encoding]::ASCII.GetBytes("In$i"); [Array]::Copy($l,0,$b,53+17*$i,$l.Length) }
    $b[307]=0x80; $b[308]=(2 -bor (5 -shl 2)); $b[310]=139; SetCrc $b }

T 'CRC16 123456789 = 29B1' { (Get-AirCrc16 ([Text.Encoding]::ASCII.GetBytes('123456789')) 9) -eq 0x29B1 }
$exHex='4466000011BE000000030000000000002EDF0000000000002E1800000000000000000000000000FF8F'
T 'Df n0 documented example parses' { $x=ConvertFrom-AirDf (ConvertFrom-AirHex $exHex); $x.Count -eq 0 -and $x.Length -eq 41 -and $x.Field10_U64BE -eq 11999 -and $x.Field18_U64BE -eq 11800 -and $x.Session4_5 -eq 0x11BE }
T 'Df n2 synthetic intervals' { $x=ConvertFrom-AirDf (NewDf @(60,69,71,86)); $x.Count -eq 2 -and $x.Length -eq 49 -and $x.Intervals[1].Start -eq 71 -and $x.Intervals[1].End -eq 86 -and $x.IntervalsOrdered }
T 'Df unordered intervals flagged' { -not (ConvertFrom-AirDf (NewDf @(70,60))).IntervalsOrdered }
T 'Df overlapping intervals flagged' { -not (ConvertFrom-AirDf (NewDf @(60,70,70,80))).IntervalsOrdered }
T 'Df reject null' { Rejects { ConvertFrom-AirDf $null } 'null' }
T 'Df reject truncated <41' { Rejects { ConvertFrom-AirDf (New-Object byte[] 40) } 'truncated' }
T 'Df reject bad magic' { $b=NewDf @(); $b[1]=0x67; $b=SetCrc $b; Rejects { ConvertFrom-AirDf $b } 'magic' }
T 'Df reject length not 41+4n' { $b=NewDf @(60,69); $c=New-Object byte[] ($b.Length+1); [Array]::Copy($b,$c,$b.Length); Rejects { ConvertFrom-AirDf $c } '41\+4n' }
T 'Df reject truncated entry' { $b=NewDf @(60,69,71,86); $c=New-Object byte[] ($b.Length-4); [Array]::Copy($b,$c,$c.Length); Rejects { ConvertFrom-AirDf $c } 'count|CRC|41' }
T 'Df reject count mismatch (valid CRC)' { $b=NewDf @(60,69); $b[38]=2; $b=SetCrc $b; Rejects { ConvertFrom-AirDf $b } 'count' }
T 'Df reject CRC corruption in body' { $b=NewDf @(60,69); $b[40]=$b[40] -bxor 1; Rejects { ConvertFrom-AirDf $b } 'CRC' }
T 'Df reject CRC corruption in trailer' { $b=NewDf @(60,69); $b[$b.Length-1]=$b[$b.Length-1] -bxor 0x80; Rejects { ConvertFrom-AirDf $b } 'CRC' }
T 'Df interval range is full u16 BE' { $x=ConvertFrom-AirDf (NewDf @(65000,65535)); $x.Intervals[0].Start -eq 65000 -and $x.Intervals[0].End -eq 65535 }
T 'Da synthetic decode' { $x=ConvertFrom-AirDa (NewDa); $x.Name -eq 'Test-Unit' -and $x.Inputs.Count -eq 15 -and $x.Inputs[14].Label -eq 'In14' -and $x.PowerOn -and $x.Muted -and $x.Channel -eq 5 -and $x.Volume -eq -28 }
T 'Da masks off' { $b=NewDa; $b[307]=0x7F; $b[308]=0xC1; $b=SetCrc $b; $x=ConvertFrom-AirDa $b; (-not $x.PowerOn) -and (-not $x.Muted) -and $x.Channel -eq 0 }
T 'Da channel max 15' { $b=NewDa; $b[308]=0x3C; $b=SetCrc $b; (ConvertFrom-AirDa $b).Channel -eq 15 }
T 'Da reject length 344/346' { (Rejects { ConvertFrom-AirDa (New-Object byte[] 344) } 'length') -and (Rejects { ConvertFrom-AirDa (New-Object byte[] 346) } 'length') }
T 'Da reject bad magic' { $b=NewDa; $b[1]=0x62; $b=SetCrc $b; Rejects { ConvertFrom-AirDa $b } 'magic' }
T 'Da reject CRC corruption' { $b=NewDa; $b[100]=$b[100] -bxor 1; Rejects { ConvertFrom-AirDa $b } 'CRC' }
T 'Analysis rejects bad packets and does not throw' { $p=@([pscustomobject]@{TimestampRaw=1;PayloadHex='44660000';PayloadLength=4}); $r=Get-AirFeedbackAnalysis $p; $r.Rejected -eq 1 -and $r.DfValid -eq 0 }
T 'Analysis rejects odd hex' { $r=Get-AirFeedbackAnalysis @([pscustomobject]@{TimestampRaw=1;PayloadHex='446';PayloadLength=2}); $r.OtherPackets -eq 1 -or $r.Rejected -eq 1 }

$real=$null
if(Test-Path -LiteralPath $CsvPath){
    $pk=Import-Csv -LiteralPath $CsvPath; $real=Get-AirFeedbackAnalysis $pk
    $before=(Get-FileHash -LiteralPath $CsvPath).Hash
    T 'Real: Df 162/162 valid CRC/count, none rejected' { $real.DfValid -eq 162 -and $real.Rejected -eq 0 }
    T 'Real: Da 63/63 valid CRC' { $real.DaValid -eq 63 }
    T 'Real: Df intervals ordered' { $real.DfIntervalsAllOrdered }
    T 'Real: Df session 11BE at 4..5 equals Dm session at 5..6' { $real.DfSession4_5Values -contains '11BE' -and $real.DmSession5_6Values -contains '11BE' -and $real.DmSession5_6Values.Count -eq 1 }
    T 'Real: Dm block width 200' { $real.DmBlockValues.Count -eq 1 -and $real.DmBlockValues[0] -eq 200 }
    T 'Real: first interval start == Field18/200+1 in all non-empty Df' { $real.Correlation.FirstIntervalStartEqualsField18Div200Plus1 -eq $real.Correlation.DfConsidered }
    T 'Real: correlation confidence is low' { $real.Correlation.Confidence -eq 'low' }
    T 'Real: input CSV unchanged' { (Get-FileHash -LiteralPath $CsvPath).Hash -eq $before }
} else { T 'Real CSV present' { $false } }

$summary=[ordered]@{ GeneratedUtc=(Get-Date).ToUniversalTime().ToString('o'); Input=$CsvPath; Total=$tests.Count; Passed=@($tests|?{$_.Passed}).Count; Failed=@($tests|?{-not $_.Passed}).Count; Tests=$tests }
if($real){ $summary.Analysis = $real | Select-Object * -ExcludeProperty Dfs,DmSorted,RejectedDetail
  $summary.Analysis | Add-Member -NotePropertyName DfLengthHistogram -NotePropertyValue @($real.Dfs|Group-Object {$_.D.Length}|Sort-Object {[int]$_.Name}|%{[pscustomobject]@{Length=[int]$_.Name;Count=$_.Count}}) -Force }
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
"Tests: $($summary.Passed)/$($summary.Total) passed"; $tests|?{-not $_.Passed}|%{ "FAIL $($_.Name): $($_.Error)" }
if($summary.Failed){ exit 1 }

