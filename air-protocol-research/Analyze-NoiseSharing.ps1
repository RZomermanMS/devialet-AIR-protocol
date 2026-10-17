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
public static class Noise {
 public static string Run(int[] dec,int[] src,int lag,int from,int to){
  var sb=new StringBuilder();
  // 4th difference high-pass removes tone (997Hz) and the per-block ramp to first order
  Func<int[],int,double> hp=(a,i)=>a[i]-4.0*a[i-1]+6.0*a[i-2]-4.0*a[i-3]+a[i-4];
  sb.AppendLine("cross-correlation of 4th-difference(dec) with 4th-difference(src) at integer lags around alignment:");
  for(int dl=-3;dl<=3;dl++){double sxy=0,sxx=0,syy=0;
   for(int f=from;f<to;f++){int d=f+lag+dl;if(d%200<5)continue;double x=hp(src,f),y=hp(dec,d);sxy+=x*y;sxx+=x*x;syy+=y*y;}
   sb.AppendLine("  lag "+(lag+dl)+": r="+(sxy/Math.Sqrt(sxx*syy)).ToString("F3"));}
  // lattice test: is dec on a lattice of spacing g?
  foreach(double g in new[]{77.26}){var h=new int[10];int n=0;
   for(int f=from;f<to;f++){double r=(dec[f+lag]+47.14)/g;double fr=r-Math.Floor(r);h[(int)(fr*10)]++;n++;}
   sb.Append("frac((dec+47)/77.26) deciles: ");foreach(var v in h)sb.Append((100.0*v/n).ToString("F1")+"% ");sb.AppendLine();}
  // sample-to-sample: histogram of dec delta mod something? delta distribution parity
  int odd=0,tot=0;for(int f=from;f<to;f++){int d=dec[f+lag]-dec[f+lag-1];if((f+lag)%200==0)continue;if((d&1)!=0)odd++;tot++;}
  sb.AppendLine("fraction of odd deltas: "+((double)odd/tot).ToString("F3"));
  return sb.ToString();}
}
'@
[Noise]::Run($dec, $src, $Lag, 200000, 260000)
