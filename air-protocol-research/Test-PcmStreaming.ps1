param([string]$Mp3)
$ErrorActionPreference='Stop'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Send-Mp3.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw 'Sender syntax invalid' }
$source=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
    $node.Value.Contains('public static class Snd2')
},$true))
$tests=@'
public static class PcmStreamingTests {
 sealed class Source {
  public long Length,Position;
  public int Chunk=800,Calls,LargestRequest;
  public int Read(byte[] buffer,int offset,int count) {
   Calls++;LargestRequest=Math.Max(LargestRequest,count);
   int size=(int)Math.Min(Math.Min(count,Chunk),Length-Position);
   for(int i=0;i<size;i++)buffer[offset+i]=(byte)((Position+i)%251);
   Position+=size;return size;
  }
 }
 static void Assert(bool value,string message) { if(!value)throw new Exception(message); }
 static void Fails(Action action,string message) {
  try{action();}catch(Exception ex){if(ex.Message.Contains(message))return;throw;}
  throw new Exception("Expected failure: "+message);
 }
 public static string CompareDecoder(Snd2.ReadPcm incremental,Snd2.ReadPcm baseline) {
  using(var actual=System.Security.Cryptography.SHA256.Create())
  using(var expected=System.Security.Cryptography.SHA256.Create()){
   var reader=new Snd2.PcmBlockReader(incremental,0);
   int frames;
   while((frames=reader.ReadNext(()=>{}))>0)
    actual.TransformBlock(reader.Buffer,0,frames*4,reader.Buffer,0);
   actual.TransformFinalBlock(new byte[0],0,0);
   var buffer=new byte[65536];long baselineBytes=0;int n;
   while((n=baseline(buffer,0,buffer.Length))>0){
    expected.TransformBlock(buffer,0,n,buffer,0);baselineBytes+=n;
   }
   expected.TransformFinalBlock(new byte[0],0,0);
   Assert(reader.FramesRead*4==baselineBytes,"Incremental decoder length differs from baseline");
   string hash=BitConverter.ToString(actual.Hash).Replace("-","");
   Assert(hash==BitConverter.ToString(expected.Hash).Replace("-",""),"Incremental PCM differs from baseline");
   return "PASS: "+reader.FramesRead+" decoded frames match 65536-byte-read baseline; SHA256="+hash+
    "; sender PCM staging="+reader.StagingBytes+" bytes.";
  }
 }
 public static string Run() {
  int fixtures=0;
  foreach(int length in new int[]{0,4,796,800,804,1600,1604,123456})
   foreach(int chunk in new int[]{1,3,7,799,800,65536}){
    var source=new Source{Length=length,Chunk=chunk};
    var reader=new Snd2.PcmBlockReader(source.Read,0);
    long bytes=0;int polls=0,frames;
    while((frames=reader.ReadNext(()=>{polls++;}))>0){
     for(int i=0;i<frames*4;i++)
      Assert(reader.Buffer[i]==(byte)((bytes+i)%251),"PCM content mismatch");
     for(int i=frames*4;i<800;i++)Assert(reader.Buffer[i]==0,"Stale final-block padding");
     bytes+=frames*4;
    }
    int calls=source.Calls;
    Assert(reader.ReadNext(()=>{})==0&&source.Calls==calls,"EOF must stay terminal");
    Assert(bytes==length&&reader.FramesRead==length/4,"Frame count mismatch");
    Assert(reader.Buffer.Length==800&&reader.StagingBytes==66336&&source.LargestRequest<=65536,"PCM buffer not bounded");
    Assert(polls>=source.Calls*2,"Missing decoder-side feedback/cancellation polls");
    fixtures++;
   }
  var unlimited=new Source{Length=long.MaxValue,Chunk=7};
  var capped=new Snd2.PcmBlockReader(unlimited.Read,201);
  Assert(capped.ReadNext(()=>{})==200&&capped.ReadNext(()=>{})==1&&capped.ReadNext(()=>{})==0,"Duration cap shape");
  Assert(unlimited.Position==804&&capped.FramesRead==201,"Decoder read beyond duration cap");
  var large=new Source{Length=long.MaxValue};
  var bounded=new Snd2.PcmBlockReader(large.Read,0);
  for(int i=0;i<10000;i++)Assert(bounded.ReadNext(()=>{})==200,"Long source read failed");
  Assert(bounded.FramesRead==2000000&&large.Position>=8000000&&large.Position<=8000000+65536&&bounded.StagingBytes==66336,"Long source buffer size changed");
  foreach(int length in new int[]{1,2,3,799,801}){
   var bad=new Source{Length=length,Chunk=3};
   var reader=new Snd2.PcmBlockReader(bad.Read,0);
   Fails(()=>{while(reader.ReadNext(()=>{})>0){}},"incomplete stereo frame");
  }
  var broken=new Snd2.PcmBlockReader((b,o,n)=>{throw new IOException("decoder failure");},0);
  Fails(()=>broken.ReadNext(()=>{}),"decoder failure");
  var invalid=new Snd2.PcmBlockReader((b,o,n)=>n+1,0);
  Fails(()=>invalid.ReadNext(()=>{}),"invalid PCM byte count");
  var negative=new Snd2.PcmBlockReader((b,o,n)=>-1,0);
  Fails(()=>negative.ReadNext(()=>{}),"invalid PCM byte count");
  var stoppedSource=new Source{Length=800,Chunk=1};
  var stopped=new Snd2.PcmBlockReader(stoppedSource.Read,0);int checks=0;
  Fails(()=>stopped.ReadNext(()=>{
   if(++checks==5)throw new OperationCanceledException("cancelled");
  }),"cancelled");
  Assert(stoppedSource.Position<=2,"Cancellation consumed extra source data");
  Fails(()=>new Snd2.PcmBlockReader(null,0),"read");
  Fails(()=>new Snd2.PcmBlockReader(large.Read,-1),"maxFrames");
  return "PASS: "+fixtures+" short-read/EOF/padding fixtures; bounded long/unknown-length input, exact cap, decoder errors and cancellation.";
 }
}
'@
Add-Type -TypeDefinition ($source[0].Value+"`n"+$tests)
[PcmStreamingTests]::Run()
if($Mp3) {
    $nd=Join-Path $PSScriptRoot 'tools\naudio'
    foreach($dll in @('naudio.core\lib\netstandard2.0\NAudio.Core.dll','naudio.winmm\lib\netstandard2.0\NAudio.WinMM.dll',
        'naudio.asio\lib\netstandard2.0\NAudio.Asio.dll','naudio.midi\lib\netstandard2.0\NAudio.Midi.dll',
        'naudio.wasapi\lib\netstandard2.0\NAudio.Wasapi.dll','naudio\lib\net472\NAudio.dll')) {
        [void][Reflection.Assembly]::LoadFrom((Join-Path $nd $dll))
    }
    foreach($rate in @(44100,48000)) {
        $a=$null;$b=$null;$ra=$null;$rb=$null
        try {
            $a=New-Object NAudio.Wave.MediaFoundationReader($Mp3)
            $b=New-Object NAudio.Wave.MediaFoundationReader($Mp3)
            $format=New-Object NAudio.Wave.WaveFormat($rate,16,2)
            $ra=New-Object NAudio.Wave.MediaFoundationResampler($a,$format)
            $rb=New-Object NAudio.Wave.MediaFoundationResampler($b,$format)
            $small=[Delegate]::CreateDelegate([Snd2+ReadPcm],$ra,'Read')
            $large=[Delegate]::CreateDelegate([Snd2+ReadPcm],$rb,'Read')
            "Rate: $rate"
            [PcmStreamingTests]::CompareDecoder($small,$large)
        } finally {
            if($null -ne $ra) { $ra.Dispose() }
            if($null -ne $rb) { $rb.Dispose() }
            if($null -ne $a) { $a.Dispose() }
            if($null -ne $b) { $b.Dispose() }
        }
    }
}
