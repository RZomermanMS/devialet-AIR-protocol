param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [string]$Wav = (Join-Path $PSScriptRoot 'air-test-48k16-stereo-997hz.wav'),
      [int]$Lag = -1569)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==172.16.5.90' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] } }
$w = [IO.File]::ReadAllBytes($Wav)
$src = New-Object 'int[]' 480000; for ($f = 0; $f -lt 480000; $f++) { $src[$f] = [BitConverter]::ToInt16($w, 44 + 4 * $f) }
Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class Frac {
 // windowed-sinc fractional delay: out(f)=src(f-tau)
 static double Interp(int[] s,int f,double tau,int half){
  double acc=0; double pos=f-tau; int c=(int)Math.Floor(pos);
  for(int k=c-half+1;k<=c+half;k++){ if(k<0||k>=s.Length)continue; double x=pos-k; double sinc=Math.Abs(x)<1e-12?1:Math.Sin(Math.PI*x)/(Math.PI*x);
   double win=0.5*(1+Math.Cos(Math.PI*x/half)); acc+=s[k]*sinc*win; }
  return acc; }
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  var sb=new StringBuilder(); double bestT=0,bestE=1e99,bestG=0,bestO=0;
  for(double tau=-1;tau<=1.0001;tau+=0.01){
   double sx=0,sy=0,sxx=0,sxy=0;int n=0;
   for(int f=from;f<to;f+=3){double x=Interp(src,f,tau,16),y=dec[f+lag];sx+=x;sy+=y;sxx+=x*x;sxy+=x*y;n++;}
   double g=(sxy-sx*sy/n)/(sxx-sx*sx/n),o=(sy-g*sx)/n,e=0;
   for(int f=from;f<to;f+=3){double x=Interp(src,f,tau,16);double d=dec[f+lag]-(g*x+o);e+=d*d;}
   e=Math.Sqrt(e/n); if(e<bestE){bestE=e;bestT=tau;bestG=g;bestO=o;} }
  // refine
  double t0=bestT;for(double tau=t0-0.01;tau<=t0+0.01;tau+=0.0005){
   double sx=0,sy=0,sxx=0,sxy=0;int n=0;
   for(int f=from;f<to;f+=3){double x=Interp(src,f,tau,16),y=dec[f+lag];sx+=x;sy+=y;sxx+=x*x;sxy+=x*y;n++;}
   double g=(sxy-sx*sy/n)/(sxx-sx*sx/n),o=(sy-g*sx)/n,e=0;
   for(int f=from;f<to;f+=3){double x=Interp(src,f,tau,16);double d=dec[f+lag]-(g*x+o);e+=d*d;}
   e=Math.Sqrt(e/n); if(e<bestE){bestE=e;bestT=tau;bestG=g;bestO=o;} }
  sb.AppendLine("best fractional delay tau="+bestT.ToString("F4")+" frames, gain="+bestG.ToString("F4")+" offset="+bestO.ToString("F2")+" rms residual (decoded units)="+bestE.ToString("F3")+" (="+(bestE/bestG).ToString("F4")+" source LSB)");
  // residual stats and per-segment tau stability at best gain/offset
  var hist=new System.Collections.Generic.SortedDictionary<int,int>();
  for(int f=from;f<to;f++){double d=dec[f+lag]-(bestG*Interp(src,f,bestT,16)+bestO);int k=(int)Math.Round(d);if(!hist.ContainsKey(k))hist[k]=0;hist[k]++;}
  sb.Append("residual histogram (decoded units, |v|<=8): ");foreach(var kv in hist)if(Math.Abs(kv.Key)<=8)sb.Append(kv.Key+":"+kv.Value+" ");sb.AppendLine();
  // per-segment tau
  int seg=(to-from)/6;
  for(int k=0;k<6;k++){int a=from+k*seg;double bt=0,be=1e99;
   for(double tau=bestT-0.15;tau<=bestT+0.15;tau+=0.005){double e=0;int n=0;for(int f=a;f<a+seg;f+=3){double d=dec[f+lag]-(bestG*Interp(src,f,tau,16)+bestO);e+=d*d;n++;} if(e<be){be=e;bt=tau;}}
   sb.AppendLine("  seg"+k+" tau="+bt.ToString("F3"));}
  // does the decoded signal sit on a coarser grid? check unique-value density
  return sb.ToString(); }
}
'@
[Frac]::Run($dec, $src, $Lag, 150000, 330000)
