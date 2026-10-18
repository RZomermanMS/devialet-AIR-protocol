param([string]$Pcap = (Join-Path $PSScriptRoot 'air-multitone.pcapng'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==192.0.2.20' -T fields -e udp.payload
$segs = New-Object System.Collections.ArrayList; $cur = $null; $prev = -1
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16)
    if ($prev -ge 1000 -and $c -le 400) { $cur = $null }
    if ($null -eq $cur) { $cur = @{}; [void]$segs.Add($cur) }
    $prev = $c; if (-not $cur.ContainsKey($c)) { $cur[$c] = $h } }
$seg = $segs[$segs.Count - 1]
"segments: $($segs.Count); using last with $($seg.Count) unique blocks, max counter $(($seg.Keys | Measure-Object -Maximum).Maximum)"
$L = @{}; $R = @{}; $wl = @{}; $wr = @{}; $rej = 0
foreach ($c in $seg.Keys) { try { $p = [ReferenceBlockDecoder]::Decode($seg[$c]); $L[$c] = $p.Left; $R[$c] = $p.Right; $wl[$p.Width]++; $wr[$p.RightWidth]++ } catch { $rej++ } }
"decoded $($L.Count), rejected $rej"
"left widths: " + (($wl.GetEnumerator() | sort Name | % { "$($_.Name)x$($_.Value)" }) -join ' ')
"right widths: " + (($wr.GetEnumerator() | sort Name | % { "$($_.Name)x$($_.Value)" }) -join ' ')
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class Lat {
 public static string Run(Dictionary<long,int[]> blocks,string name){
  var keys=new List<long>(blocks.Keys);keys.Sort();
  // only blocks that are not all-zero
  var use=new List<int[]>();foreach(var k in keys){var b=blocks[k];bool nz=false;foreach(var v in b)if(v!=0){nz=true;break;}if(nz)use.Add(b);}
  Func<double,double,double> score=(g,bias)=>{double acc=0;long n=0;foreach(var b in use){for(int i=1;i<200;i++){double u=(b[i]-b[0]+bias*i)/g;double fr=u-Math.Round(u);acc+=fr*fr;n++;}}return Math.Sqrt(acc/n);};
  double bg=0,bb=0,be=1e9;
  for(double g=76.0;g<=78.5;g+=0.004)for(double bias=0.40;bias<=0.56;bias+=0.01){double e=score(g,bias);if(e<be){be=e;bg=g;bb=bias;}}
  double g0=bg,b0=bb;for(double g=g0-0.006;g<=g0+0.006;g+=0.0005)for(double bias=b0-0.01;bias<=b0+0.01;bias+=0.001){double e=score(g,bias);if(e<be){be=e;bg=g;bb=bias;}}
  double fx=score(77.276,0.48);
    return name+": non-silent blocks="+use.Count+" best g="+bg.ToString("F3")+" bias="+bb.ToString("F3")+" rms lattice distance="+be.ToString("F3")+"  | at g=77.276,bias=0.48: "+fx.ToString("F3");}
}
'@
$dl = New-Object 'System.Collections.Generic.Dictionary[long,int[]]'; $dr = New-Object 'System.Collections.Generic.Dictionary[long,int[]]'
foreach ($c in $L.Keys) { $dl[[long]$c] = [int[]]$L[$c]; $dr[[long]$c] = [int[]]$R[$c] }
[Lat]::Run($dl, 'LEFT'); [Lat]::Run($dr, 'RIGHT')
$peak = 0; foreach ($c in $L.Keys) { foreach ($v in $L[$c]) { if ([Math]::Abs($v) -gt $peak) { $peak = [Math]::Abs($v) } } }
"left peak decoded magnitude: $peak  (= $([Math]::Round($peak/77.276,1)) source LSB)"
