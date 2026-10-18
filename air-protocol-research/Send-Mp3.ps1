param(
    [string]$Mp3 = 'C:\dev\Track1-converted.mp3',
    [int]$Gen = 30,
    [double]$Gain = 0.25,
    [int]$MaxSeconds = 0,
    [string]$Stem = 'air-mp3',
    [int]$CaptureInterface = 5,
    [string]$ExpertAddress,
    [string]$ExpertName,
    [ValidateRange(-1,14)][int]$NetworkInputIndex = -1,
    [ValidateSet(44100,48000)][int]$SampleRate = 48000,
    [ValidateRange(0,65535)][int]$SessionId = 0,
    [ValidateSet('Generated','Captured')][string]$Startup = 'Generated',
    [string]$StopFile,
    [switch]$ExperimentalRate
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$dumpcap = 'C:\Program Files\Wireshark\dumpcap.exe'
. (Join-Path $PSScriptRoot 'Discovery.ps1')
if($SampleRate -ne 48000 -and -not $ExperimentalRate) { throw '44.1k mode requires -ExperimentalRate.' }
if($Gen -lt 0 -or $Gen -gt 253 -or $MaxSeconds -lt 0 -or [double]::IsNaN($Gain) -or [double]::IsInfinity($Gain) -or $Gain -le 0 -or $Gain -gt 3) {
    throw 'Require generation 0..253, nonnegative duration, and finite gain in (0,3].'
}
if($StopFile) {
    $StopFile=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StopFile)
    if(Test-Path -LiteralPath $StopFile) { throw 'Stop file already exists; remove it explicitly before starting.' }
}

# Decode to the selected PCM rate; AIR mode selection remains experimental at 44.1k.
$nd = Join-Path $PSScriptRoot 'tools\naudio'
foreach ($d in 'naudio.core\lib\netstandard2.0\NAudio.Core.dll','naudio.winmm\lib\netstandard2.0\NAudio.WinMM.dll','naudio.asio\lib\netstandard2.0\NAudio.Asio.dll','naudio.midi\lib\netstandard2.0\NAudio.Midi.dll','naudio.wasapi\lib\netstandard2.0\NAudio.Wasapi.dll','naudio\lib\net472\NAudio.dll') {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $nd $d))
}
if($SessionId -eq 0) {
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $identity=New-Object byte[] 2
        do { $rng.GetBytes($identity); $SessionId=[int]$identity[0]*256+$identity[1] } while($SessionId -eq 0)
    } finally { $rng.Dispose() }
}
"Session: 0x$($SessionId.ToString('x4')); startup=$Startup"
$preHex=[string[]]@();$preT=[double[]]@()
if($Startup -eq 'Captured') {
    $rows = & 'C:\Program Files\Wireshark\tshark.exe' -r air-dumpcap-ref.pcapng -Y 'udp.dstport==45455 && udp.payload[0:2]==44:6d' -T fields -e frame.time_relative -e udp.payload
    $pre = New-Object System.Collections.ArrayList
    foreach ($r in $rows) { $f = $r -split "`t"; $h = $f[1]; if ($h.Substring(20, 2) -ne '06') { break }; [void]$pre.Add(@{ T = [double]$f[0]; H = $h }) }
    $preHex = [string[]]($pre | % { $_.H }); $preT = [double[]]($pre | % { $_.T - $pre[0].T })
    if($LASTEXITCODE -ne 0 -or $preHex.Length -ne 38) { throw 'Could not load the expected reference preamble.' }
    $sessionHex=$SessionId.ToString('x4')
    $preHex=[string[]]@($preHex | ForEach-Object { $_.Substring(0,10)+$sessionHex+$_.Substring(14) })
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.IO;
public static class Snd2 {
 public const int ResendCacheBlocks=400;
 public delegate int ReadPcm(byte[] buffer,int offset,int count);
 public sealed class PcmBlockReader {
  readonly ReadPcm read;
  readonly long maxFrames;
  bool ended;
  readonly byte[] decoded=new byte[65536];
  int decodedOffset,decodedCount;
  public readonly byte[] Buffer=new byte[800];
  public int StagingBytes { get { return Buffer.Length+decoded.Length; } }
  public long FramesRead { get; private set; }
  public double MaxReadMs { get; private set; }
  public PcmBlockReader(ReadPcm read,long maxFrames) {
   if(read==null)throw new ArgumentNullException("read");
   if(maxFrames<0||maxFrames>long.MaxValue/4)throw new ArgumentOutOfRangeException("maxFrames");
   this.read=read;this.maxFrames=maxFrames;
  }
  public int ReadNext(Action poll) {
   if(poll==null)throw new ArgumentNullException("poll");
   poll();Array.Clear(Buffer,0,Buffer.Length);
   if(ended)return 0;
   int wanted=maxFrames==0?800:(int)Math.Min(200,maxFrames-FramesRead)*4;
   if(wanted==0){ended=true;return 0;}
   int filled=0;
   while(filled<wanted){
    poll();
    if(decodedOffset==decodedCount){
     // Media Foundation resampler EOF output can depend on native Read size.
     int request=maxFrames==0?decoded.Length:(int)Math.Min(decoded.Length,(maxFrames-FramesRead)*4-filled);
     var timer=Stopwatch.StartNew();
     int n=read(decoded,0,request);
     MaxReadMs=Math.Max(MaxReadMs,timer.Elapsed.TotalMilliseconds);
     poll();
     if(n<0||n>request)throw new InvalidDataException("Decoder returned invalid PCM byte count");
     if(n==0){ended=true;break;}
     decodedOffset=0;decodedCount=n;
    }
    int copy=Math.Min(wanted-filled,decodedCount-decodedOffset);
    Array.Copy(decoded,decodedOffset,Buffer,filled,copy);
    decodedOffset+=copy;filled+=copy;
   }
   if(filled%4!=0)throw new InvalidDataException("PCM ended with an incomplete stereo frame");
   FramesRead+=filled/4;
   return filled/4;
  }
 }
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
 public static string[] GenerateStartup(int session,int gen,int rate) {
  if(session<1||session>65535||gen<0||gen>253||(rate!=44100&&rate!=48000))
   throw new ArgumentOutOfRangeException("startup");
  var packets=new string[38];var silence=new int[200];
  for(int k=0;k<packets.Length;k++){
   var h=new byte[22];h[0]=0x44;h[1]=0x6d;h[2]=2;
   h[5]=(byte)(session>>8);h[6]=(byte)session;h[10]=(byte)gen;
   h[11]=(byte)(rate==44100?0:2);h[21]=200;
   long counter=200L*k;for(int i=0;i<8;i++)h[12+i]=(byte)(counter>>(56-8*i));
   packets[k]=BitConverter.ToString(Packet(h,silence,silence)).Replace("-","");
  }
  return packets;
 }

 public static void CheckHealth(double now,double lastFeedback,double lastProgress,long sent,long acknowledged) {
  if(now-lastFeedback>=2000)throw new InvalidOperationException("Feedback absent for 2 seconds");
  if(sent>acknowledged && now-lastProgress>=2000)throw new InvalidOperationException("Acknowledgement progress stalled for 2 seconds");
 }
 public static bool ValidFeedback(byte[] d,byte generation) {
  if(d.Length<41 || (d.Length-41)%4!=0 || d[0]!=0x44 || d[1]!=0x66 || d[9]!=generation)return false;
  if(((d[37]<<8)|d[38])!=(d.Length-41)/4)return false;
  return Crc(d,d.Length-2)==((d[d.Length-2]<<8)|d[d.Length-1]);
 }
 public static bool ValidSessionFeedback(byte[] d,byte generation,int session) {
  return ValidFeedback(d,generation)&&((d[4]<<8)|d[5])==session;
 }
 public static long[] RepairCounters(long b,long a,long f,long sent,int[] intervals) {
  if(b<0||b%200!=0||a<=b||a%200!=199||a>sent+199||f<0||f>a)
   throw new InvalidOperationException("Invalid feedback recovery bounds");
  if(intervals==null||intervals.Length==0||intervals.Length%2!=0)
   throw new InvalidOperationException("Invalid feedback intervals");
  var counters=new List<long>();int previous=-1;
  for(int i=0;i<intervals.Length;i+=2){
   int start=intervals[i],end=intervals[i+1];
   if(start<0||end>65535||start>end||start<=previous)
    throw new InvalidOperationException("Invalid feedback intervals");
   previous=end;
   if(end-start+1>ResendCacheBlocks-counters.Count)
    throw new InvalidOperationException("Recovery request exceeds resend-cache safety limit");
   for(int index=start;index<=end;index++){
    long counter=f-f%200+200L*index;
    if(counter<=b||counter>sent||counter>a-199)
     throw new InvalidOperationException("Requested counter outside feedback bounds");
    counters.Add(counter);
   }
  }
  return counters.ToArray();
 }
 public static string Run(string[] preHex,double[] preT,ReadPcm read,double gain,int maxSeconds,string localIp,string expert,int gen,int sampleRate,string stopFile){
  using(var sock=new UdpClient(AddressFamily.InterNetwork)) {
   sock.ExclusiveAddressUse=true;
   sock.Client.Bind(new IPEndPoint(IPAddress.Parse(localIp),45456));
   sock.Client.ReceiveTimeout=200;
   var dest=new IPEndPoint(IPAddress.Parse(expert),45455);
   var sw=Stopwatch.StartNew();
   byte[] initial=FromHex(preHex[0]);int session=(initial[5]<<8)|initial[6];
   int dfCount=0,invalid=0,resends=0;
   long lastB=-1,lastF=0,sent=-1;
   double lastFeedback=0,lastProgress=0,maxLate=0;
   var cache=new Dictionary<long,byte[]>();
   var pending=new SortedSet<long>();
   double nextRepair=0,repairPeriod=200000.0/sampleRate;
   Action poll=()=>{
    if(!String.IsNullOrEmpty(stopFile)&&File.Exists(stopFile))throw new OperationCanceledException("Playback stopped by stop file; queued receiver audio may finish");
    for(int drained=0;drained<64 && sock.Available>0;drained++) {
     var ep=new IPEndPoint(IPAddress.Any,0);
     byte[] d=sock.Receive(ref ep);
     if(!ep.Address.Equals(dest.Address)||ep.Port!=45456||!ValidSessionFeedback(d,(byte)(gen+2),session)){invalid++;continue;}
     long b=BE64(d,18);
     if(b<0||b>sent||b%200!=0||b<lastB){invalid++;continue;}
     dfCount++;lastFeedback=sw.Elapsed.TotalMilliseconds;lastF=BE64(d,26);
     if(b>lastB){lastB=b;lastProgress=lastFeedback;}
     int n=(d[37]<<8)|d[38];
     if(n>0) {
      int[] intervals=new int[n*2];
      for(int i=0;i<n;i++){
       intervals[2*i]=(d[39+4*i]<<8)|d[40+4*i];
       intervals[2*i+1]=(d[41+4*i]<<8)|d[42+4*i];
      }
      // Captures map interval indexes relative to F's current 200-frame block.
      long[] repair=RepairCounters(b,BE64(d,10),lastF,sent,intervals);
      foreach(long counter in repair)if(!cache.ContainsKey(counter))
       throw new InvalidOperationException("Recovery window is outside resend cache");
      foreach(long counter in repair)pending.Add(counter);
      Console.WriteLine("RECOVERY B="+b+" A="+BE64(d,10)+" intervals="+n+" requestedBlocks="+repair.Length+" pending="+pending.Count);
     }
    }
    while(pending.Count>0&&pending.Min<=lastB)pending.Remove(pending.Min);
    if(pending.Count>0&&sw.Elapsed.TotalMilliseconds>=nextRepair){
     long counter=pending.Min;byte[] resend;
     if(!cache.TryGetValue(counter,out resend))throw new InvalidOperationException("Queued recovery counter expired from cache");
     sock.Send(resend,resend.Length,dest);pending.Remove(counter);resends++;
     nextRepair=sw.Elapsed.TotalMilliseconds+repairPeriod;
    }
   };
   var pcm=new PcmBlockReader(read,maxSeconds==0?0:(long)maxSeconds*sampleRate);
   int frames=pcm.ReadNext(poll);
   if(frames==0)throw new InvalidOperationException("Decoded audio is empty; audio was not started");
   double t0=sw.Elapsed.TotalMilliseconds;
   for(int i=0;i<preHex.Length;i++){
    poll();
    byte[] p=FromHex(preHex[i]);p[10]=(byte)gen;
    int ce=p.Length-130;ushort crc=Crc(p,ce);p[ce]=(byte)(crc>>8);p[ce+1]=(byte)crc;
    while(sw.Elapsed.TotalMilliseconds-t0<preT[i]*1000)Thread.SpinWait(50);
    sock.Send(p,p.Length,dest);
   }
   double startupWait=sw.Elapsed.TotalMilliseconds;
   bool ready=false;
   long startupEnd=BE64(FromHex(preHex[preHex.Length-1]),12);
   while(!ready){
    if(!String.IsNullOrEmpty(stopFile)&&File.Exists(stopFile))throw new OperationCanceledException("Playback stopped during startup");
    for(int drained=0;drained<64&&sock.Available>0;drained++){
     var ep=new IPEndPoint(IPAddress.Any,0);byte[] d=sock.Receive(ref ep);
     if(ep.Address.Equals(dest.Address)&&ep.Port==45456&&ValidSessionFeedback(d,(byte)gen,session)&&
        BE64(d,18)==startupEnd&&d.Length==41)ready=true;
    }
    if(!ready&&sw.Elapsed.TotalMilliseconds-startupWait>=2000)
     throw new InvalidOperationException("Startup not acknowledged within 2 seconds; audio was not started");
    if(!ready)Thread.Sleep(1);
   }
   Console.WriteLine("STARTUP READY: session="+session+" B="+startupEnd);
   Thread.Sleep(1000);
   var h=new byte[22];Array.Copy(FromHex(preHex[0]),h,22);h[10]=(byte)(gen+2);
   long blocks=0;
   double period=200000.0/sampleRate,ta=sw.Elapsed.TotalMilliseconds,nextLog=ta;
   lastFeedback=ta;lastProgress=ta;
   Console.WriteLine("Audio start: rate="+sampleRate+" streamingPCMBufferBytes="+pcm.Buffer.Length+" pcmStagingBytes="+pcm.StagingBytes+" gain="+gain);
   for(long k=0;frames>0;k++){
    double due=ta+k*period;
    while(sw.Elapsed.TotalMilliseconds<due){poll();Thread.SpinWait(50);}
    poll();CheckHealth(sw.Elapsed.TotalMilliseconds,lastFeedback,lastProgress,sent,lastB);
    maxLate=Math.Max(maxLate,sw.Elapsed.TotalMilliseconds-due);
    var l=new int[200];var r=new int[200];
    for(int i=0;i<frames;i++){
     int o=i*4;
     l[i]=(int)Math.Round((short)(pcm.Buffer[o]|pcm.Buffer[o+1]<<8)*gain*77.276);
     r[i]=(int)Math.Round((short)(pcm.Buffer[o+2]|pcm.Buffer[o+3]<<8)*gain*77.276);
     if(l[i]<-8388608||l[i]>8388607||r[i]<-8388608||r[i]>8388607)throw new InvalidOperationException("24-bit sample overflow");
    }
    long cnt=(long)k*200;var hh=(byte[])h.Clone();
    hh[11]=(byte)((sampleRate==44100?0:2)+(k>=(sampleRate==44100?227:250)?1:0));
    for(int i=0;i<8;i++)hh[12+i]=(byte)(cnt>>(56-8*i));
    byte[] packet=Packet(hh,l,r);cache[cnt]=packet;cache.Remove(cnt-200L*ResendCacheBlocks);
    sock.Send(packet,packet.Length,dest);sent=cnt;blocks++;
    if(sw.Elapsed.TotalMilliseconds>=nextLog){
     Console.WriteLine("elapsed="+((sw.Elapsed.TotalMilliseconds-ta)/1000).ToString("F1")+
      " sent="+sent+" B="+lastB+" F="+lastF+" feedbackAgeMs="+
      (sw.Elapsed.TotalMilliseconds-lastFeedback).ToString("F0")+" Df="+dfCount+" resends="+resends+" decodedFrames="+pcm.FramesRead+
      " maxReadMs="+pcm.MaxReadMs.ToString("F1")+" maxLateMs="+maxLate.ToString("F1"));
     nextLog=sw.Elapsed.TotalMilliseconds+5000;
    }
    frames=pcm.ReadNext(poll);
   }
   double drain=sw.Elapsed.TotalMilliseconds;
   while(lastB<sent){
    poll();CheckHealth(sw.Elapsed.TotalMilliseconds,lastFeedback,lastProgress,sent,lastB);
    if(sw.Elapsed.TotalMilliseconds-drain>=3000)throw new InvalidOperationException("Final block not acknowledged within drain timeout");
    Thread.Sleep(1);
   }
   double playoutWait=sw.Elapsed.TotalMilliseconds;
   while(lastF<sent+200){
    poll();
    if(sw.Elapsed.TotalMilliseconds-playoutWait>=3000)throw new InvalidOperationException("Receiver F did not reach track end within drain timeout");
    if(sw.Elapsed.TotalMilliseconds-lastFeedback>=2000)throw new InvalidOperationException("Feedback absent during track-end drain");
    Thread.Sleep(1);
   }
   return "ACKNOWLEDGED: blocks="+blocks+" decodedFrames="+pcm.FramesRead+" pcmBufferBytes="+pcm.Buffer.Length+" pcmStagingBytes="+pcm.StagingBytes+
    " maxReadMs="+pcm.MaxReadMs.ToString("F1")+" Df="+dfCount+" invalidOrOther="+invalid+
    " resends="+resends+" finalB="+lastB+" lastSent="+sent+" finalF="+lastF+" paddedEnd="+(sent+200)+" maxLateMs="+maxLate.ToString("F1")+
    "; acoustic playout not verified";
  }
 }
}
'@
if($Startup -eq 'Generated') {
    $preHex=[Snd2]::GenerateStartup($SessionId,$Gen,$SampleRate)
    $preT=[double[]]@(0..37 | ForEach-Object { $_*200.0/$SampleRate })
}

$cap = Join-Path $PSScriptRoot "$Stem.pcapng"
$rd=$null;$rs=$null;$dc=$null
try {
    $rd = New-Object NAudio.Wave.MediaFoundationReader($Mp3)
    "source: $($rd.WaveFormat)  length $([int]$rd.TotalTime.TotalSeconds)s"
    $fmt = New-Object NAudio.Wave.WaveFormat($SampleRate, 16, 2)
    $rs = New-Object NAudio.Wave.MediaFoundationResampler($rd, $fmt)
    $read=[Delegate]::CreateDelegate([Snd2+ReadPcm],$rs,'Read')
    $dc = Start-Process -FilePath $dumpcap -ArgumentList @('-i',"$CaptureInterface",'-s','0','-B','32','-f','"udp port 45454 or udp port 45455 or udp port 45456"','-w',('"' + $cap + '"')) -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    if ($dc.HasExited) { throw 'dumpcap failed to start.' }
    $target=Get-AirSenderTarget -CaptureInterface $CaptureInterface -ExpertAddress $ExpertAddress -ExpertName $ExpertName -NetworkInputIndex $NetworkInputIndex
    "Selected Expert: $($target.Device.Name) at $($target.ExpertAddress)"
    [Snd2]::Run($preHex, $preT, $read, $Gain, $MaxSeconds, $target.LocalAddress, $target.ExpertAddress, $Gen, $SampleRate, $StopFile)
}
finally {
    try {
        if($null -ne $dc) {
            Start-Sleep -Seconds 1
            $dc.Refresh()
            if(-not $dc.HasExited) { Stop-Process -Id $dc.Id }
        }
    } finally {
        if($null -ne $rs) { $rs.Dispose() }
        if($null -ne $rd) { $rd.Dispose() }
    }
}
