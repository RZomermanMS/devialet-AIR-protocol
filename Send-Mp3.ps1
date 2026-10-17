param(
    [string]$Mp3 = 'C:\dev\Track1-converted.mp3',
    [int]$Gen = 30,
    [double]$Gain = 0.25,
    [int]$MaxSeconds = 0,
    [string]$Stem = 'air-mp3'
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$tshark = 'C:\Program Files\Wireshark\tshark.exe'
$dumpcap = 'C:\Program Files\Wireshark\dumpcap.exe'

# decode MP3 -> 48 kHz 16-bit stereo PCM (in memory) via Media Foundation
$nd = Join-Path $PSScriptRoot 'tools\naudio'
foreach ($d in 'naudio.core\lib\netstandard2.0\NAudio.Core.dll','naudio.winmm\lib\netstandard2.0\NAudio.WinMM.dll','naudio.asio\lib\netstandard2.0\NAudio.Asio.dll','naudio.midi\lib\netstandard2.0\NAudio.Midi.dll','naudio.wasapi\lib\netstandard2.0\NAudio.Wasapi.dll','naudio\lib\net472\NAudio.dll') {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $nd $d))
}
$rd = New-Object NAudio.Wave.MediaFoundationReader($Mp3)
"source: $($rd.WaveFormat)  length $([int]$rd.TotalTime.TotalSeconds)s"
$fmt = New-Object NAudio.Wave.WaveFormat(48000, 16, 2)
$rs = New-Object NAudio.Wave.MediaFoundationResampler($rd, $fmt)
$ms = New-Object System.IO.MemoryStream
$buf = New-Object byte[] 65536
while (($n = $rs.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
$pcm = $ms.ToArray(); $rs.Dispose(); $rd.Dispose()
"decoded PCM: $($pcm.Length / 4) frames = $([Math]::Round($pcm.Length / 4 / 48000, 1)) s"

# preamble template
$rows = & $tshark -r air-dumpcap-ref.pcapng -Y 'udp.dstport==45455 && udp.payload[0:2]==44:6d' -T fields -e frame.time_relative -e udp.payload 2>$null
$pre = New-Object System.Collections.ArrayList
foreach ($r in $rows) { $f = $r -split "`t"; $h = $f[1]; if ($h.Substring(20, 2) -ne '06') { break }; [void]$pre.Add(@{ T = [double]$f[0]; H = $h }) }
$preHex = [string[]]($pre | % { $_.H }); $preT = [double[]]($pre | % { $_.T - $pre[0].T })

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public static class Snd2 {
 static int ZZ(int d){return (d<<1)^(d>>31);}
 static byte[] Chan(int[] v,int width){
  int n=v.Length; int size=7+((n-1)*width+7)/8; var o=new byte[size];
  o[0]=(byte)(v[0]>>16);o[1]=(byte)(v[0]>>8);o[2]=(byte)v[0];o[5]=(byte)width;o[6]=(byte)width;
  int bit=56; for(int i=1;i<n;i++){int c=ZZ(v[i]-v[i-1]); for(int k=width-1;k>=0;k--,bit++) if(((c>>k)&1)!=0) o[bit/8]|=(byte)(0x80>>(bit%8));}
  return o;}
 static int MinWidth(int[] v){int m=0;for(int i=1;i<v.Length;i++){int z=ZZ(v[i]-v[i-1]); if(z>m)m=z;} int w=0;while(m>0){w++;m>>=1;} return w;}
 static ushort Crc(byte[] d,int n){int c=0xFFFF;for(int i=0;i<n;i++){c^=d[i]<<8;for(int b=0;b<8;b++)c=((c&0x8000)!=0)?((c<<1)^0x1021)&0xFFFF:(c<<1)&0xFFFF;}return (ushort)c;}
 static byte[] Packet(byte[] hdr,int[] l,int[] r){
  var a=Chan(l,MinWidth(l));var b=Chan(r,MinWidth(r)); var p=new byte[22+a.Length+b.Length+2+128];
  Array.Copy(hdr,p,22);Array.Copy(a,0,p,22,a.Length);Array.Copy(b,0,p,22+a.Length,b.Length);
  int e=22+a.Length+b.Length; ushort c=Crc(p,e); p[e]=(byte)(c>>8);p[e+1]=(byte)c; return p;}
 static long BE64(byte[] d,int o){long v=0;for(int i=0;i<8;i++)v=(v<<8)|d[o+i];return v;}
 static byte[] FromHex(string h){var r=new byte[h.Length/2];for(int i=0;i<r.Length;i++)r[i]=Convert.ToByte(h.Substring(i*2,2),16);return r;}

 public static string Run(string[] preHex,double[] preT,byte[] pcm,double gain,int maxSeconds,string localIp,string expert,int gen){
  var log=new System.Text.StringBuilder();
  var sock=new UdpClient(new IPEndPoint(IPAddress.Parse(localIp),45456));
  var dest=new IPEndPoint(IPAddress.Parse(expert),45455);
  var cache=new Dictionary<long,byte[]>(); var lk=new object();
  var sw=Stopwatch.StartNew(); int dfCount=0,resends=0,dfGap=0,missed=0; bool stop=false; long lastB=0,lastF=0;
  var th=new Thread(()=>{ sock.Client.ReceiveTimeout=200; var ep=new IPEndPoint(IPAddress.Any,0);
   while(!stop){ byte[] d; try{d=sock.Receive(ref ep);}catch(SocketException){continue;}
    if(d.Length<40||d[0]!=0x44||d[1]!=0x66)continue; dfCount++;
    long B=BE64(d,18); int n=d[37]; lastB=B; lastF=BE64(d,26);
    if(n>0){dfGap++; byte[] p; lock(lk){cache.TryGetValue(B+200,out p);} if(p!=null){sock.Send(p,p.Length,dest);resends++;} else missed++;}
   }}); th.Start();
  double t0=sw.Elapsed.TotalMilliseconds;
  for(int i=0;i<preHex.Length;i++){ var p=FromHex(preHex[i]); p[10]=(byte)gen; int ce=(p.Length>1000)?982:p.Length-130; ushort pc=Crc(p,ce); p[ce]=(byte)(pc>>8); p[ce+1]=(byte)pc;
   while(sw.Elapsed.TotalMilliseconds-t0<preT[i]*1000.0)Thread.SpinWait(50); sock.Send(p,p.Length,dest); lock(lk){cache[BE64(p,12)]=p;} }
  Thread.Sleep(1000);
  var hdr=FromHex(preHex[0]); var h=new byte[22]; Array.Copy(hdr,h,22); h[10]=(byte)(gen+2); h[11]=0x02;
  long totalFrames=pcm.Length/4; if(maxSeconds>0) totalFrames=Math.Min(totalFrames,(long)maxSeconds*48000);
  int blocks=(int)((totalFrames+199)/200); double period=200.0/48.0;
  double ta=sw.Elapsed.TotalMilliseconds; long maxLate=0;
  for(int k=0;k<blocks;k++){
   double due=ta+k*period; while(sw.Elapsed.TotalMilliseconds<due)Thread.SpinWait(50);
   long late=(long)(sw.Elapsed.TotalMilliseconds-due); if(late>maxLate)maxLate=late;
   var l=new int[200];var r=new int[200];
   for(int i=0;i<200;i++){ long fr=(long)k*200+i; if(fr>=totalFrames)break; int o=(int)fr*4;
    double sl=(short)(pcm[o]|(pcm[o+1]<<8))*gain*77.276, sr=(short)(pcm[o+2]|(pcm[o+3]<<8))*gain*77.276;
    l[i]=(int)Math.Round(sl); r[i]=(int)Math.Round(sr); }
   long cnt=(long)k*200; var hh=(byte[])h.Clone(); if(k>=250)hh[11]=0x03;
   for(int i=0;i<8;i++)hh[12+i]=(byte)(cnt>>(56-8*i));
   var p=Packet(hh,l,r); lock(lk){cache[cnt]=p; cache.Remove(cnt-200L*400);} sock.Send(p,p.Length,dest);
   if(k%1200==0) log.AppendLine(((sw.ElapsedMilliseconds-(long)ta)/1000.0).ToString("F1")+"s block "+k+"/"+blocks+" Df B="+lastB+" F="+lastF+" gaps="+dfGap);
  }
  Thread.Sleep(1000); stop=true; th.Join(); sock.Close();
  log.AppendLine("blocks sent "+blocks+"; Df "+dfCount+"; Df with gap "+dfGap+"; resends "+resends+"; unresendable "+missed+"; max late ms "+maxLate+"; final B="+lastB+" (last sent "+((long)(blocks-1)*200)+")");
  return log.ToString();
 }
}
'@

$local = (Get-NetIPAddress -AddressFamily IPv4 | ? { $_.IPAddress -eq '172.16.5.252' }).IPAddress
if (-not $local) { throw 'local IP 172.16.5.252 not found' }
if (Get-NetUDPEndpoint -LocalPort 45456 -ErrorAction SilentlyContinue) { throw 'UDP 45456 is already in use (is AIR streaming on?)' }

$cap = Join-Path $PSScriptRoot "$Stem.pcapng"
$dc = Start-Process -FilePath $dumpcap -ArgumentList @('-i','5','-s','0','-B','32','-f','"host 172.16.5.90"','-w',('"' + $cap + '"')) -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
if ($dc.HasExited) { throw 'dumpcap failed to start.' }
try { [Snd2]::Run($preHex, $preT, $pcm, $Gain, $MaxSeconds, $local, '172.16.5.90', $Gen) }
finally { Start-Sleep -Seconds 1; Stop-Process -Id $dc.Id -ErrorAction SilentlyContinue }
