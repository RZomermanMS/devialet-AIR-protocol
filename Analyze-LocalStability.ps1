param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [string]$Wav = (Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'),
      [int]$Lag = -1569)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==172.16.5.90' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] } }
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
public static class Local {
 public static string Run(int[] dec,int from,int to){
  var sb=new StringBuilder(); double w=2*Math.PI*997.0/48000; int W=960; // 20 ms = 20 cycles of 997Hz approx
  var amps=new List<double>();var phs=new List<double>();
  for(int a=from;a+W<=to;a+=W){double ss=0,cc=0,sc=0,sy=0,cy=0;
   for(int f=a;f<a+W;f++){double s=Math.Sin(w*f),c=Math.Cos(w*f),y=dec[f];ss+=s*s;cc+=c*c;sc+=s*c;sy+=s*y;cy+=c*y;}
   double det=ss*cc-sc*sc;double A=(sy*cc-cy*sc)/det,B=(cy*ss-sy*sc)/det;amps.Add(Math.Sqrt(A*A+B*B));phs.Add(Math.Atan2(B,A));}
  double ma=0;foreach(var v in amps)ma+=v;ma/=amps.Count;double sa=0;foreach(var v in amps)sa+=(v-ma)*(v-ma);sa=Math.Sqrt(sa/amps.Count);
  double mp=0;foreach(var v in phs)mp+=v;mp/=phs.Count;double sp=0;foreach(var v in phs)sp+=(v-mp)*(v-mp);sp=Math.Sqrt(sp/phs.Count);
  sb.AppendLine("windows="+amps.Count+" amp mean="+ma.ToString("F2")+" std="+sa.ToString("F3")+" ("+(100*sa/ma).ToString("F4")+"%)  phase mean="+mp.ToString("F5")+" std="+sp.ToString("F5")+" rad = "+(sp/w).ToString("F4")+" frames");
  // residual by position in block (frame mod 200) after global sine fit
  double S=0,Cc=0,SS=0,CCs=0,SC=0,SY=0,CY=0,Y=0,N=0;
  for(int f=from;f<to;f++){double s=Math.Sin(w*f),c=Math.Cos(w*f),y=dec[f];SS+=s*s;CCs+=c*c;SC+=s*c;SY+=s*y;CY+=c*y;S+=s;Cc+=c;Y+=y;N++;}
  // simple LS with offset ignoring cross-offset terms (small): fit a,b
  double det2=SS*CCs-SC*SC;double a2=(SY*CCs-CY*SC)/det2,b2=(CY*SS-SY*SC)/det2,off=Y/N;
  var byPos=new double[200];var cnt=new int[200];
  for(int f=from;f<to;f++){double e=dec[f]-(a2*Math.Sin(w*f)+b2*Math.Cos(w*f)+off);byPos[f%200]+=e*e;cnt[f%200]++;}
  sb.Append("profile: ");for(int i=0;i<200;i+=1){if(i<12||i>=188||i%20==0)sb.Append(i+":"+Math.Sqrt(byPos[i]/cnt[i]).ToString("F0")+" ");}sb.AppendLine();double mn=1e99,mx=0;int imn=0,imx=0;for(int i=0;i<200;i++){double r=Math.Sqrt(byPos[i]/cnt[i]);if(r<mn){mn=r;imn=i;}if(r>mx){mx=r;imx=i;}}
  sb.AppendLine("residual rms by frame position in 200-frame block: min="+mn.ToString("F1")+"@"+imn+" max="+mx.ToString("F1")+"@"+imx);
  // windowed residual rms over time (20ms windows): show first few and spread
  var rr=new List<double>();for(int a=from;a+W<=to;a+=W){double e=0;for(int f=a;f<a+W;f++){double d=dec[f]-(a2*Math.Sin(w*f)+b2*Math.Cos(w*f)+off);e+=d*d;}rr.Add(Math.Sqrt(e/W));}
  rr.Sort();sb.AppendLine("windowed residual rms: min="+rr[0].ToString("F1")+" median="+rr[rr.Count/2].ToString("F1")+" max="+rr[rr.Count-1].ToString("F1"));
  // phase trend (drift)
  var ph=phs.ToArray();for(int i=1;i<ph.Length;i++){double d=ph[i]-ph[i-1];while(d>Math.PI)d-=2*Math.PI;while(d<-Math.PI)d+=2*Math.PI;ph[i]=ph[i-1]+d;}
  sb.AppendLine("phase first/last window: "+ph[0].ToString("F4")+" -> "+ph[ph.Length-1].ToString("F4")+" rad over "+(ph.Length*20)+" ms");
  sb.Append("phase of first 12 windows: ");for(int i=0;i<12&&i<ph.Length;i++)sb.Append(ph[i].ToString("F4")+" ");sb.AppendLine();
  sb.Append("amp of first 12 windows: ");for(int i=0;i<12&&i<amps.Count;i++)sb.Append(amps[i].ToString("F1")+" ");sb.AppendLine();
  return sb.ToString(); }
}
'@
[Local]::Run($dec, 150000+$Lag*0+ (-0), 330000)

