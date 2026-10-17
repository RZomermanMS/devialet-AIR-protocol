param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [int]$From = 200000, [int]$To = 260000)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==172.16.5.90' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] } }
Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class Lattice {
 // For each block: u[i]=(dec[i]-dec[0]+bias*i)/g ; measure how close u[i] is to an integer for i in 1..N
 static double Score(int[] dec,int from,int to,double g,double bias,int N){
  double acc=0;int n=0;
  for(int b=from-from%200;b+200<=to;b+=200){for(int i=1;i<=N;i++){double u=(dec[b+i]-dec[b]+bias*i)/g;double fr=u-Math.Round(u);acc+=fr*fr;n++;}}
  return Math.Sqrt(acc/n);}
 public static string Run(int[] dec,int from,int to){
  var sb=new StringBuilder();double bg=0,bb=0,be=1e9;
  for(double g=77.0;g<=77.5;g+=0.002)for(double bias=-1.0;bias<=0.01;bias+=0.1){double e=Score(dec,from,to,g,bias,8);if(e<be){be=e;bg=g;bb=bias;}}
  sb.AppendLine("lattice search (first 8 samples of each block): best g="+bg.ToString("F3")+" bias="+bb.ToString("F2")+" rms distance from integer lattice = "+be.ToString("F3")+" (random would be 0.289)");
  double ee=Score(dec,from,to,77.26,0,8);sb.AppendLine("at g=77.26,bias 0: "+ee.ToString("F3"));
  return sb.ToString();}
}
'@
[Lattice]::Run($dec, $From, $To)
