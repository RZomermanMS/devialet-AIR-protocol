param([string]$Pcap = (Join-Path $PSScriptRoot 'air-dumpcap-ref.pcapng'),
      [int]$From = 150000, [int]$To = 330000)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
$rows = & 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'udp.payload[0:2]==44:6d && ip.dst==172.16.5.90' -T fields -e udp.payload
$seen = @{}; $dec = New-Object 'int[]' 480400
foreach ($h in $rows) { $c = [Convert]::ToInt64($h.Substring(24, 16), 16); if ($seen[$c]) { continue }; $seen[$c] = 1
    $p = [ReferenceBlockDecoder]::Decode($h); for ($i = 0; $i -lt 200; $i++) { $dec[$c + $i] = $p.Left[$i] } }
Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class RampFit {
 static double[] Solve(double[,] M,double[] r){int n=r.Length;var A=(double[,])M.Clone();var y=(double[])r.Clone();
  for(int i=0;i<n;i++){int piv=i;for(int k=i+1;k<n;k++)if(Math.Abs(A[k,i])>Math.Abs(A[piv,i]))piv=k;
   for(int j=0;j<n;j++){double t=A[i,j];A[i,j]=A[piv,j];A[piv,j]=t;}double ty=y[i];y[i]=y[piv];y[piv]=ty;
   for(int k=i+1;k<n;k++){double m=A[k,i]/A[i,i];for(int j=i;j<n;j++)A[k,j]-=m*A[i,j];y[k]-=m*y[i];}}
  var s=new double[n];for(int i=n-1;i>=0;i--){double v=y[i];for(int j=i+1;j<n;j++)v-=A[i,j]*s[j];s[i]=v/A[i,i];}return s;}
 public static string Run(int[] dec,int from,int to){
  var sb=new StringBuilder();double w=2*Math.PI*997.0/48000;
  foreach(int mode in new[]{0,1,2}){ // 0 sine+offset, 1 +additive ramp, 2 +ramp and ramp*sine terms (gain ramp)
   int np=mode==0?3:mode==1?4:6;var M=new double[np,np];var r=new double[np];
   for(int f=from;f<to;f++){double p=(f%200)-99.5;double s=Math.Sin(w*f),c=Math.Cos(w*f);double[] b=mode==0?new[]{s,c,1.0}:mode==1?new[]{s,c,1.0,p}:new[]{s,c,1.0,p,p*s,p*c};
    for(int i=0;i<np;i++){r[i]+=b[i]*dec[f];for(int j=0;j<np;j++)M[i,j]+=b[i]*b[j];}}
   var x=Solve(M,r);double e=0;int n=0;
   for(int f=from;f<to;f++){double p=(f%200)-99.5;double s=Math.Sin(w*f),c=Math.Cos(w*f);double[] b=mode==0?new[]{s,c,1.0}:mode==1?new[]{s,c,1.0,p}:new[]{s,c,1.0,p,p*s,p*c};
    double m=0;for(int i=0;i<np;i++)m+=x[i]*b[i];double d=dec[f]-m;e+=d*d;n++;}
   sb.Append("model "+mode+": rms residual="+Math.Sqrt(e/n).ToString("F2")+" params:");foreach(var v in x)sb.Append(" "+v.ToString("F4"));sb.AppendLine();}
  return sb.ToString();}
}
'@
[RampFit]::Run($dec, $From, $To)
