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
public static class Spec {
 static void Fft(double[] re,double[] im){int n=re.Length;
  for(int i=1,j=0;i<n;i++){int bit=n>>1;for(;(j&bit)!=0;bit>>=1)j^=bit;j^=bit;if(i<j){double t=re[i];re[i]=re[j];re[j]=t;t=im[i];im[i]=im[j];im[j]=t;}}
  for(int len=2;len<=n;len<<=1){double ang=-2*Math.PI/len;double wr=Math.Cos(ang),wi=Math.Sin(ang);
   for(int i=0;i<n;i+=len){double cr=1,ci=0;for(int k=0;k<len/2;k++){int a=i+k,b=i+k+len/2;double xr=re[b]*cr-im[b]*ci,xi=re[b]*ci+im[b]*cr;re[b]=re[a]-xr;im[b]=im[a]-xi;re[a]+=xr;im[a]+=xi;double t=cr*wr-ci*wi;ci=cr*wi+ci*wr;cr=t;}}}}
 static double[] Psd(double[] x){int n=x.Length;var re=new double[n];var im=new double[n];double m=0;foreach(var v in x)m+=v;m/=n;
  for(int i=0;i<n;i++){double w=0.5-0.5*Math.Cos(2*Math.PI*i/(n-1));re[i]=(x[i]-m)*w;}
  Fft(re,im);var p=new double[n/2];for(int i=0;i<n/2;i++)p[i]=(re[i]*re[i]+im[i]*im[i]);return p;}
 public static string Run(int[] dec,int[] src,int lag,int from){
  int n=131072;var d=new double[n];var s=new double[n];
  for(int i=0;i<n;i++){d[i]=dec[from+i+lag]/77.26;s[i]=src[from+i];}
  var pd=Psd(d);var ps=Psd(s);var sb=new StringBuilder();
  // mask out the tone bins (997 Hz +-3 bins around)
  int tone=(int)Math.Round(997.0/48000*n);
  sb.AppendLine("band(kHz)    source_noise(dB re LSB^2)  decoded_noise(dB re LSB^2)  diff");
  for(int b=0;b<12;b++){double lo=b*2000.0,hi=lo+2000.0;int i0=(int)(lo/48000*n),i1=(int)(hi/48000*n);double es=0,ed=0;int c=0;
   for(int i=Math.Max(i0,1);i<i1;i++){if(Math.Abs(i-tone)<8)continue;es+=ps[i];ed+=pd[i];c++;}
   es/=c;ed/=c;sb.AppendLine(String.Format("{0,2}-{1,2}   {2,8:F1}   {3,8:F1}   {4,6:F1}",b*2,b*2+2,10*Math.Log10(es),10*Math.Log10(ed),10*Math.Log10(ed/es)));}
  // harmonics of the tone in decoded
  sb.Append("decoded harmonic levels re fundamental (dB): ");double f1=pd[tone]+pd[tone-1]+pd[tone+1];
  for(int h=2;h<=6;h++){int k=tone*h;double e=0;for(int q=-2;q<=2;q++)e+=pd[k+q];sb.Append("H"+h+"="+(10*Math.Log10(e/f1)).ToString("F1")+" ");}
  sb.AppendLine();
  return sb.ToString(); }
}
'@
[Spec]::Run($dec, $src, $Lag, 160000)
