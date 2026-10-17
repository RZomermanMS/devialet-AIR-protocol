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
public static class Ramp {
 static double Interp(int[] s,double pos,int half){
  double acc=0;int c=(int)Math.Floor(pos);
  for(int k=c-half+1;k<=c+half;k++){if(k<0||k>=s.Length)continue;double x=pos-k;double sinc=Math.Abs(x)<1e-12?1:Math.Sin(Math.PI*x)/(Math.PI*x);double win=0.5*(1+Math.Cos(Math.PI*x/half));acc+=s[k]*sinc*win;}
  return acc;}
 // model: dec[f+lag] = g*src(pos) + o, pos = f - tau0 - kappa*((f+lag)%200 - 99.5)
 static double Err(int[] dec,int[] src,int lag,int from,int to,double tau0,double kappa,out double g,out double o){
  double sx=0,sy=0,sxx=0,sxy=0;int n=0;
  for(int f=from;f<to;f+=3){int d=f+lag;double pos=f-tau0-kappa*(((d%200)+200)%200-99.5);double x=Interp(src,pos,16),y=dec[d];sx+=x;sy+=y;sxx+=x*x;sxy+=x*y;n++;}
  g=(sxy-sx*sy/n)/(sxx-sx*sx/n);o=(sy-g*sx)/n;double e=0;
  for(int f=from;f<to;f+=3){int d=f+lag;double pos=f-tau0-kappa*(((d%200)+200)%200-99.5);double r=dec[d]-(g*Interp(src,pos,16)+o);e+=r*r;}
  return Math.Sqrt(e/n);}
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  var sb=new StringBuilder();double bt=0.423,bk=0,be=1e99,bg=0,bo=0;
  for(double k=-0.006;k<=0.006001;k+=0.0005){for(double t=0.40;t<=0.45;t+=0.005){double g,o;double e=Err(dec,src,lag,from,to,t,k,out g,out o);if(e<be){be=e;bt=t;bk=k;bg=g;bo=o;}}}
  double k0=bk,t0=bt;for(double k=k0-0.0005;k<=k0+0.0005;k+=0.00005){for(double t=t0-0.005;t<=t0+0.005;t+=0.0005){double g,o;double e=Err(dec,src,lag,from,to,t,k,out g,out o);if(e<be){be=e;bt=t;bk=k;bg=g;bo=o;}}}
  sb.AppendLine("best: tau0="+bt.ToString("F4")+" kappa="+bk.ToString("F5")+" frames/frame (ramp of "+(bk*200).ToString("F3")+" frames per block) gain="+bg.ToString("F3")+" offset="+bo.ToString("F2")+" rms residual="+be.ToString("F2")+" decoded units");
  double g0,o0;sb.AppendLine("kappa=0 reference residual: "+Err(dec,src,lag,from,to,bt,0,out g0,out o0).ToString("F2"));
  return sb.ToString();}
}
'@
[Ramp]::Run($dec, $src, $Lag, 150000, 330000)
