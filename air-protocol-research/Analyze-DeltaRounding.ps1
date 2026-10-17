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
public static class DeltaTest {
 static double Interp(int[] s,double pos,int half){double acc=0;int c=(int)Math.Floor(pos);
  for(int k=c-half+1;k<=c+half;k++){if(k<0||k>=s.Length)continue;double x=pos-k;double sinc=Math.Abs(x)<1e-12?1:Math.Sin(Math.PI*x)/(Math.PI*x);double win=0.5*(1+Math.Cos(Math.PI*x/half));acc+=s[k]*sinc*win;}return acc;}
 static double Stat(int[] dec,int[] src,int lag,int from,int to,double g,double tau,out double mean,out double mn,out double mx,bool detail,StringBuilder sb){
  double s=0,s2=0;int n=0;var hist=new int[12];double prev=0;mn=1e9;mx=-1e9;
  for(int d=from;d<to;d++){double cur=Interp(src,d-lag-tau,16); if(d%200==0){prev=cur;continue;}
   double e=(dec[d]-dec[d-1])-g*(cur-prev);prev=cur;s+=e;s2+=e*e;n++;int b=(int)Math.Floor(e*4)+6;if(b<0)b=0;if(b>11)b=11;hist[b]++;if(e<mn)mn=e;if(e>mx)mx=e;}
  mean=s/n;if(detail){sb.Append("hist of e=(delta_dec - g*delta_src) in quarter units from -1.5: ");for(int i=0;i<12;i++)sb.Append(hist[i]+" ");sb.AppendLine();}
  return Math.Sqrt(s2/n-mean*mean);}
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  var sb=new StringBuilder();double bg=77.26,bt=0.423,bsd=1e9;
  for(double g=77.20;g<=77.32;g+=0.005)for(double t=0.41;t<=0.435;t+=0.001){double m,a,b;double sd=Stat(dec,src,lag,from,to,g,t,out m,out a,out b,false,sb);if(sd<bsd){bsd=sd;bg=g;bt=t;}}
  double mean,lo,hi;double sd2=Stat(dec,src,lag,from,to,bg,bt,out mean,out lo,out hi,true,sb);
  sb.AppendLine("best g="+bg.ToString("F3")+" tau="+bt.ToString("F3")+": per-sample delta error mean="+mean.ToString("F3")+" sd="+sd2.ToString("F3")+" min="+lo.ToString("F2")+" max="+hi.ToString("F2"));
  return sb.ToString();}
}
'@
[DeltaTest]::Run($dec, $src, $Lag, 200000, 260000)
