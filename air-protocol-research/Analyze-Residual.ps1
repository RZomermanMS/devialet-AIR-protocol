param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [string]$Wav = (Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'),
      [int]$Lag = -1569)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==192.0.2.20' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] } }
$w = [IO.File]::ReadAllBytes($Wav)
$src = New-Object 'int[]' 480000; for ($f = 0; $f -lt 480000; $f++) { $src[$f] = [BitConverter]::ToInt16($w, 44 + 4 * $f) }
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class Resid {
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  var sb=new System.Text.StringBuilder();
  // LS gain+offset
  double sx=0,sy=0,sxx=0,sxy=0;int n=0;
  for(int f=from;f<to;f++){double x=src[f],y=dec[f+lag];sx+=x;sy+=y;sxx+=x*x;sxy+=x*y;n++;}
  double g=(sxy-sx*sy/n)/(sxx-sx*sx/n), o=(sy-g*sx)/n;
  sb.AppendLine("gain="+g.ToString("F4")+" offset="+o.ToString("F2")+" (gain/256="+(g/256).ToString("F5")+")");
  // residual in source-LSB units
  var r=new double[to-from];double s2=0;for(int f=from;f<to;f++){r[f-from]=(dec[f+lag]-o)/g-src[f];s2+=r[f-from]*r[f-from];}
  sb.AppendLine("residual rms (source LSB) = "+Math.Sqrt(s2/r.Length).ToString("F3"));
  // histogram of residual rounded
  var h=new SortedDictionary<int,int>();foreach(var v in r){int k=(int)Math.Round(v);if(!h.ContainsKey(k))h[k]=0;h[k]++;}
  sb.Append("histogram (LSB:count) ");int shown=0;foreach(var kv in h){if(Math.Abs(kv.Key)<=6)sb.Append(kv.Key+":"+kv.Value+" ");shown++;}
  sb.AppendLine("; distinct="+h.Count+" max|r|="+Math.Abs(r[0]));
  // lag-1 autocorrelation of residual and correlation with src, d(src)
  double a0=0,a1=0,a2=0,cs=0,cd=0,ss=0,sdd=0;
  for(int i=2;i<r.Length-1;i++){a0+=r[i]*r[i];a1+=r[i]*r[i-1];a2+=r[i]*r[i-2];double s=src[from+i];double d=src[from+i+1]-src[from+i-1];cs+=r[i]*s;cd+=r[i]*d;ss+=s*s;sdd+=d*d;}
  sb.AppendLine("residual autocorr lag1="+(a1/a0).ToString("F3")+" lag2="+(a2/a0).ToString("F3"));
  sb.AppendLine("corr(resid,src)="+(cs/Math.Sqrt(a0*ss)).ToString("F3")+" corr(resid,src slope)="+(cd/Math.Sqrt(a0*sdd)).ToString("F3"));
  // fractional delay estimate: resid ~ -tau*slope  => tau = -cd/sdd
  sb.AppendLine("implied fractional delay (frames) = "+(-cd/sdd*2).ToString("F4"));
  // per-segment gain/lag stability
  int seg=(to-from)/6;
  for(int k=0;k<6;k++){double a=0,b=0,c=0;int f0=from+k*seg;for(int f=f0;f<f0+seg;f++){double x=src[f],y=dec[f+lag]-o;a+=x*y;b+=x*x;c+=y*y;}
   sb.AppendLine("  seg"+k+": gain="+(a/b).ToString("F3")+" rms_res_LSB="+Math.Sqrt((c-a*a/b)/seg/ (g*g)).ToString("F3"));}
  return sb.ToString();}
 public static string Decimals(int[] dec,int[] src,int lag,int from){
  var sb=new System.Text.StringBuilder();
  for(int f=from;f<from+12;f++)sb.AppendLine("src="+src[f]+" dec="+dec[f+lag]+" dec/src="+(src[f]!=0?(dec[f+lag]/(double)src[f]).ToString("F2"):"-"));
  // low bits of decoded: are they mostly multiples of something?
  var m=new Dictionary<int,int>();for(int f=from;f<from+20000;f++){int k=((dec[f+lag]%256)+256)%256;if(!m.ContainsKey(k))m[k]=0;m[k]++;}
  sb.AppendLine("distinct values of dec mod 256 in 20000 frames: "+m.Count);
  return sb.ToString();}
}
'@
[Resid]::Run($dec, $src, $Lag, 150000, 330000)
[Resid]::Decimals($dec, $src, $Lag, 200000)
