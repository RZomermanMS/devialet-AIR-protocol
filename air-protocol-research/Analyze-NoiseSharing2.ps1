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
public static class Noise2 {
 static void SineRes(double[] x,double hz,double[] res){int n=x.Length;double w=2*Math.PI*hz/48000;double ss=0,cc=0,sc=0,sy=0,cy=0;
  for(int i=0;i<n;i++){double s=Math.Sin(w*i),c=Math.Cos(w*i);ss+=s*s;cc+=c*c;sc+=s*c;sy+=s*x[i];cy+=c*x[i];}
  double det=ss*cc-sc*sc;double a=(sy*cc-cy*sc)/det,b=(cy*ss-sy*sc)/det;for(int i=0;i<n;i++)res[i]=x[i]-(a*Math.Sin(w*i)+b*Math.Cos(w*i));}
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  int n=to-from;var s=new double[n];var d=new double[n+16];var rs=new double[n];var rd=new double[n+16];
  for(int i=0;i<n;i++)s[i]=src[from+i];
  // decoded aligned so index i corresponds to src from+i with lag; keep +-8 margin
  var dd=new double[n+16];for(int i=0;i<n+16;i++)dd[i]=dec[from+i+lag-8];
  SineRes(s,997.0,rs);
  // decoded: need same-phase model; fit with its own phase at same 997 (indices consistent since shift is integer)
  // remove per-block linear trend (blocks aligned on counter multiples of 200)
  int off0=(from+lag-8);
  SineRes(dd,997.0,rd);
  for(int b0=0;b0<n+16;){int g0=off0+b0;int len=200-(((g0%200)+200)%200);if(b0+len>n+16)len=n+16-b0;
   double sx=0,sy=0,sxx=0,sxy=0;for(int k=0;k<len;k++){sx+=k;sy+=rd[b0+k];sxx+=k*k;sxy+=k*rd[b0+k];}
   double m=len*sxx-sx*sx;double slope=m==0?0:(len*sxy-sx*sy)/m;double ic=(sy-slope*sx)/len;
   for(int k=0;k<len;k++)rd[b0+k]-=ic+slope*k;b0+=len;}
  sb(0);
  var o=new StringBuilder();o.AppendLine("cross-correlation of tone-free,ramp-free decoded noise vs source quantization noise:");
  for(int dl=-3;dl<=3;dl++){double sxy=0,sxx=0,syy=0;for(int i=8;i<n-8;i++){double x=rs[i],y=rd[i+8+dl];sxy+=x*y;sxx+=x*x;syy+=y*y;}
   o.AppendLine("  shift "+dl+": r="+(sxy/Math.Sqrt(sxx*syy)).ToString("F3"));}
  double e1=0,e2=0;for(int i=8;i<n-8;i++){e1+=rs[i]*rs[i];e2+=rd[i+8]*rd[i+8];}
  o.AppendLine("rms src noise (LSB)="+Math.Sqrt(e1/(n-16)).ToString("F3")+"  rms decoded noise (units)="+Math.Sqrt(e2/(n-16)).ToString("F2")+" -> "+(Math.Sqrt(e2/(n-16))/77.26).ToString("F3")+" LSB");
  return o.ToString();}
 static void sb(int x){}
}
'@
[Noise2]::Run($dec, $src, $Lag, 200000, 260000)
