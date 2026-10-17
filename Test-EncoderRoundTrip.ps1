param([string[]]$Captures = @('air-dumpcap-ref','air-cycle1','air-cycle3'))
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
. .\Decode-ReferenceBlocks.ps1 -DefinitionsOnly
Add-Type -TypeDefinition @'
using System;
public static class DmEnc {
 static int ZZ(int d){return (d<<1)^(d>>31);}
 public static byte[] Chan(int[] v,int width){
  int n=v.Length; int size=7+((n-1)*width+7)/8; var o=new byte[size];
  o[0]=(byte)(v[0]>>16);o[1]=(byte)(v[0]>>8);o[2]=(byte)v[0];o[5]=(byte)width;o[6]=(byte)width;
  int bit=7*8; for(int i=1;i<n;i++){int c=ZZ(v[i]-v[i-1]); for(int k=width-1;k>=0;k--,bit++) if(((c>>k)&1)!=0) o[bit/8]|=(byte)(0x80>>(bit%8));}
  return o;}
 public static int MinWidth(int[] v){int m=0;for(int i=1;i<v.Length;i++){int z=ZZ(v[i]-v[i-1]); if(z>m)m=z;} int w=0;while(m>0){w++;m>>=1;} return w;}
 public static ushort Crc(byte[] d,int n){int c=0xFFFF;for(int i=0;i<n;i++){c^=d[i]<<8;for(int b=0;b<8;b++)c=((c&0x8000)!=0)?((c<<1)^0x1021)&0xFFFF:(c<<1)&0xFFFF;}return (ushort)c;}
 public static byte[] Packet(byte[] hdr22,int[] l,int[] r,int wl,int wr){
  var a=Chan(l,wl);var b=Chan(r,wr); var p=new byte[22+a.Length+b.Length+2+128];
  Array.Copy(hdr22,p,22);Array.Copy(a,0,p,22,a.Length);Array.Copy(b,0,p,22+a.Length,b.Length);
  int e=22+a.Length+b.Length; ushort c=Crc(p,e); p[e]=(byte)(c>>8);p[e+1]=(byte)c; return p;}
 public static bool Same(byte[] a,byte[] b){if(a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
}
'@
$t = 'C:\Program Files\Wireshark\tshark.exe'
$st = @{}
foreach ($n in $Captures) {
 foreach ($h in (& $t -r "$n.pcapng" -Y 'udp.dstport==45455' -T fields -e udp.payload 2>$null)) {
  if (-not ($h -and $h.StartsWith('446d'))) { continue }
  $p = [ReferenceBlockDecoder]::Decode($h)
  $raw = New-Object byte[] ($h.Length/2); for ($i=0; $i -lt $raw.Length; $i++) { $raw[$i] = [Convert]::ToByte($h.Substring($i*2,2),16) }
  $hdr = [byte[]]$raw[0..21]
  $mw = [DmEnc]::MinWidth($p.Left); $mwr = [DmEnc]::MinWidth($p.Right)
  $k = if ($raw.Length -gt 1000) { 'pre' } else { 'play' }
  $e1 = [DmEnc]::Packet($hdr, $p.Left, $p.Right, $p.Width, $p.RightWidth)
  $st["$k total"]++
  $st["$k layout-exact (orig widths)"] += [int][DmEnc]::Same($e1, $raw)
  $st["$k minwidth==orig L"] += [int]($mw -eq $p.Width)
  $st["$k minwidth==orig R"] += [int]($mwr -eq $p.RightWidth)
  if ($mw -ne $p.Width) { $st["$k widthdiff orig=$($p.Width) min=$mw"]++ }
 }
}
$st.GetEnumerator() | sort Name | % { "$($_.Name): $($_.Value)" }
