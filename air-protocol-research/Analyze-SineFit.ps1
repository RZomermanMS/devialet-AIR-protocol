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
using System.Text;
public static class SineFit {
 // LS fit a*sin+b*cos+c at frequency hz over [from,to) of series x (index f+shift); returns residual rms and params
 static double Fit(Func<int,double> x,int from,int to,double hz,out double a,out double b,out double c){
  double w=2*Math.PI*hz/48000; double[,] M=new double[3,3]; double[] r=new double[3];
  for(int f=from;f<to;f++){double s=Math.Sin(w*f),co=Math.Cos(w*f),v=x(f);double[] p={s,co,1};
   for(int i=0;i<3;i++){r[i]+=p[i]*v;for(int j=0;j<3;j++)M[i,j]+=p[i]*p[j];}}
  // solve 3x3
  double[,] A=(double[,])M.Clone();double[] y=(double[])r.Clone();
  for(int i=0;i<3;i++){int piv=i;for(int k=i+1;k<3;k++)if(Math.Abs(A[k,i])>Math.Abs(A[piv,i]))piv=k;
   for(int j=0;j<3;j++){double t=A[i,j];A[i,j]=A[piv,j];A[piv,j]=t;}double ty=y[i];y[i]=y[piv];y[piv]=ty;
   for(int k=i+1;k<3;k++){double m=A[k,i]/A[i,i];for(int j=i;j<3;j++)A[k,j]-=m*A[i,j];y[k]-=m*y[i];}}
  double[] sol=new double[3];for(int i=2;i>=0;i--){double s=y[i];for(int j=i+1;j<3;j++)s-=A[i,j]*sol[j];sol[i]=s/A[i,i];}
  a=sol[0];b=sol[1];c=sol[2];double e=0;
  for(int f=from;f<to;f++){double d=x(f)-(a*Math.Sin(w*f)+b*Math.Cos(w*f)+c);e+=d*d;}
  return Math.Sqrt(e/(to-from)); }
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  var sb=new StringBuilder();
  foreach(var item in new[]{"source","decoded"}){
   Func<int,double> x=item=="source"?(Func<int,double>)(f=>src[f]):(f=>dec[f+lag]);
   double bestHz=0,bestE=1e99,ba=0,bb=0,bc=0;
   for(double hz=996.5;hz<=997.5;hz+=0.002){double a,b,c;double e=Fit(x,from,to,hz,out a,out b,out c);if(e<bestE){bestE=e;bestHz=hz;ba=a;bb=b;bc=c;}}
   double amp=Math.Sqrt(ba*ba+bb*bb);
   sb.AppendLine(item+": best freq "+bestHz.ToString("F3")+" Hz, amplitude "+amp.ToString("F2")+", offset "+bc.ToString("F2")+", phase "+Math.Atan2(bb,ba).ToString("F5")+" rad, residual-to-pure-sine rms="+bestE.ToString("F3")+(item=="decoded"?" decoded units ("+(bestE/77.26).ToString("F3")+" source LSB)":" LSB"));
   // residual autocorrelation + distribution
   double w=2*Math.PI*bestHz/48000;int n=to-from;var r=new double[n];
   for(int f=from;f<to;f++)r[f-from]=x(f)-(ba*Math.Sin(w*f)+bb*Math.Cos(w*f)+bc);
   double a0=0,a1=0,a2=0;for(int i=2;i<n;i++){a0+=r[i]*r[i];a1+=r[i]*r[i-1];a2+=r[i]*r[i-2];}
   sb.AppendLine("   residual autocorr lag1="+(a1/a0).ToString("F3")+" lag2="+(a2/a0).ToString("F3"));
   if(item=="source"){var h=new System.Collections.Generic.SortedDictionary<int,int>();foreach(var v in r){int k=(int)Math.Round(v*4);if(!h.ContainsKey(k))h[k]=0;h[k]++;}
     sb.Append("   source residual hist (quarter-LSB): ");foreach(var kv in h)if(Math.Abs(kv.Key)<=6)sb.Append(kv.Key+":"+kv.Value+" ");sb.AppendLine();}
  }
  return sb.ToString(); }
}
'@
[SineFit]::Run($dec, $src, $Lag, 150000, 330000)
