$ErrorActionPreference='Stop'
$sources=@()
foreach($definition in @(
    @{File='Send-Mp3.ps1';Class='public static class Snd2'},
    @{File='Decode-ReferenceBlocks.ps1';Class='public static class ReferenceBlockDecoder'}
)) {
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot $definition.File),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count) { throw "Syntax error in $($definition.File)" }
    $class=$definition.Class
    $found=@($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Value.Contains($class)
    },$true))
    if($found.Count -ne 1) { throw "Expected exactly one $class definition" }
    $sources+=[regex]::Replace($found[0].Value,'(?m)^using [^\r\n]+;\r?\n','')
}
$tests=@'
public static class SenderIntegrationTests {
 enum Scenario { Clean, AdjacentLoss, SeparatedLoss, LostResend, BurstLoss, FeedbackAbsent, ProgressStall, ForeignSession, CorruptFeedback }
 sealed class Expert : IDisposable {
  readonly UdpClient socket;
  readonly UdpClient input;
  readonly Thread worker;
  readonly Scenario scenario;
  readonly HashSet<long> received=new HashSet<long>();
  readonly Dictionary<long,int> attempts=new Dictionary<long,int>();
  volatile bool stop;
  Exception failure;
  long newest=-1,contiguous=-1;
  bool audio;
  public int DecodedPackets,InvalidInjected,PaddingSamples;
  public Expert(Scenario scenario) {
   this.scenario=scenario;
   socket=new UdpClient(AddressFamily.InterNetwork);
   socket.ExclusiveAddressUse=true;
   socket.Client.Bind(new IPEndPoint(IPAddress.Parse("127.0.0.2"),45456));
   socket.Client.ReceiveTimeout=20;
   try {
    input=new UdpClient(AddressFamily.InterNetwork);
    input.ExclusiveAddressUse=true;
    input.Client.Bind(new IPEndPoint(IPAddress.Parse("127.0.0.2"),45455));
    input.Client.ReceiveTimeout=10;
   }catch{
    if(input!=null)input.Close();
    socket.Close();throw;
   }
   worker=new Thread(Loop);worker.IsBackground=true;worker.Start();
  }
  static ushort Crc(byte[] data,int count) {
   int crc=65535;
   for(int i=0;i<count;i++){crc^=data[i]<<8;for(int k=0;k<8;k++)crc=((crc&32768)!=0?(crc<<1)^0x1021:crc<<1)&65535;}
   return (ushort)crc;
  }
  static void Put(byte[] data,int offset,long value,int bytes) {
   for(int i=0;i<bytes;i++)data[offset+i]=(byte)(value>>(8*(bytes-i-1)));
  }
  void Feedback(long b,long a,long f,int generation,int session,List<int> missing) {
   var intervals=new List<int>();
   foreach(int index in missing){
    if(intervals.Count>0&&intervals[intervals.Count-1]+1==index)intervals[intervals.Count-1]=index;
    else{intervals.Add(index);intervals.Add(index);}
   }
   byte[] packet=new byte[41+2*intervals.Count];
   packet[0]=0x44;packet[1]=0x66;packet[9]=(byte)generation;
   Put(packet,4,session,2);Put(packet,10,a,8);Put(packet,18,b,8);Put(packet,26,f,8);
   Put(packet,37,intervals.Count/2,2);
   for(int i=0;i<intervals.Count;i++)Put(packet,39+2*i,intervals[i],2);
   ushort crc=Crc(packet,packet.Length-2);Put(packet,packet.Length-2,crc,2);
   socket.Send(packet,packet.Length,new IPEndPoint(IPAddress.Loopback,45456));
  }
  void Loop() {
   using(input){
    try {
     while(!stop){
      while(input.Available>0){
       var ep=new IPEndPoint(IPAddress.Any,0);byte[] data=input.Receive(ref ep);
       var decoded=ReferenceBlockDecoder.Decode(BitConverter.ToString(data).Replace("-",""));
       if(data[10]==30){
        if(decoded.Counter==7400)Feedback(7400,7599,0,30,0x1234,new List<int>());
        continue;
       }
       if(data[10]!=32)throw new Exception("Unexpected generation in integration test");
       audio=true;DecodedPackets++;
       long counter=decoded.Counter;
       for(int i=0;i<200;i++){
        long frame=counter+i;
        int total=scenario==Scenario.FeedbackAbsent||scenario==Scenario.ProgressStall||
         scenario==Scenario.ForeignSession||scenario==Scenario.CorruptFeedback?132300:
         scenario==Scenario.BurstLoss?10024:1824;
        int expected=frame<total?(int)Math.Round(((frame%101)-50)*77.276):0;
        if(decoded.Left[i]!=expected||decoded.Right[i]!=-expected)
         throw new Exception("Wire PCM differs from incremental source at frame "+frame);
        if(frame>=total)PaddingSamples++;
       }
       int attempt;attempts.TryGetValue(counter,out attempt);attempts[counter]=++attempt;
       bool drop=(scenario==Scenario.AdjacentLoss&&(counter==200||counter==400)&&attempt==1)||
        (scenario==Scenario.SeparatedLoss&&(counter==200||counter==800)&&attempt==1)||
        (scenario==Scenario.LostResend&&counter==200&&attempt<=2)||
        (scenario==Scenario.BurstLoss&&counter>=200&&counter<=8000&&attempt==1);
       newest=Math.Max(newest,counter);
       if(!drop)received.Add(counter);
       while(received.Contains(contiguous+200))contiguous+=200;
       if(contiguous==-1&&received.Contains(0)){contiguous=0;while(received.Contains(contiguous+200))contiguous+=200;}
      }
      if(audio&&newest>=0){
       if(scenario==Scenario.BurstLoss&&newest<8200){Thread.Sleep(1);continue;}
       if(scenario==Scenario.FeedbackAbsent){Thread.Sleep(2);continue;}
       if(scenario==Scenario.ForeignSession){
        Feedback(newest,newest+199,newest+200,32,0x1235,new List<int>());
        InvalidInjected++;Thread.Sleep(5);continue;
       }
       if(scenario==Scenario.CorruptFeedback){
        byte[] bad=new byte[41];bad[0]=0x44;bad[1]=0x66;bad[9]=32;Put(bad,4,0x1234,2);
        socket.Send(bad,bad.Length,new IPEndPoint(IPAddress.Loopback,45456));
        InvalidInjected++;Thread.Sleep(5);continue;
       }
       if(scenario==Scenario.ProgressStall){
        Feedback(0,newest+199,0,32,0x1234,new List<int>());Thread.Sleep(5);continue;
       }
       var missing=new List<int>();
       for(long counter=contiguous+200;counter<=newest;counter+=200)
        if(!received.Contains(counter))missing.Add((int)(counter/200));
       Feedback(contiguous,newest+199,missing.Count==0?newest+200:0,32,0x1234,missing);
       Thread.Sleep(10);
      } else Thread.Sleep(1);
     }
    }catch(Exception ex){failure=ex;}
   }
  }
  public void Dispose() {
   stop=true;
   if(!worker.Join(2000))throw new Exception("Mock Expert thread did not exit");
   socket.Close();
   if(failure!=null)throw new Exception("Mock Expert failed",failure);
  }
 }
 static void Assert(bool value,string message) { if(!value)throw new Exception(message); }
 public static string Run() {
  int cases=0;
  foreach(int rate in new int[]{44100,48000})
  foreach(Scenario scenario in Enum.GetValues(typeof(Scenario))){
   bool fault=scenario==Scenario.FeedbackAbsent||scenario==Scenario.ProgressStall||
    scenario==Scenario.ForeignSession||scenario==Scenario.CorruptFeedback;
   int frames=fault?132300:scenario==Scenario.BurstLoss?10024:1824;
   byte[] pcm=new byte[frames*4];
   for(int i=0;i<frames;i++){
    short left=(short)((i%101)-50),right=(short)-left;
    pcm[4*i]=(byte)left;pcm[4*i+1]=(byte)(left>>8);
    pcm[4*i+2]=(byte)right;pcm[4*i+3]=(byte)(right>>8);
   }
   var clock=Stopwatch.StartNew();
   using(var expert=new Expert(scenario))
   using(var source=new MemoryStream(pcm)){
    string result=null;Exception error=null;
    double[] times=new double[38];for(int i=0;i<38;i++)times[i]=i*200.0/rate;
    try {
     result=Snd2.Run(Snd2.GenerateStartup(0x1234,30,rate),times,source.Read,1,0,
      "127.0.0.1","127.0.0.2",30,rate,null);
    }catch(InvalidOperationException ex){error=ex;}
    if(fault){
     string expected=scenario==Scenario.ProgressStall?"progress stalled":"Feedback absent";
     Assert(error!=null&&error.Message.Contains(expected),"Expected explicit "+expected+" for "+scenario);
     Assert(result==null,"Fault reported success");
     Assert(clock.Elapsed.TotalSeconds<6,"Fault handling exceeded bound");
    }else{
     Assert(error==null,"Unexpected transport failure: "+error);
     long last=(frames-1)/200*200;
     Assert(result.Contains("decodedFrames="+frames+" ")&&result.Contains("finalB="+last+" ")&&result.Contains("paddedEnd="+(last+200)+" "),"Wrong final transport result");
     Assert(expert.PaddingSamples>=176,"Final partial packet not checked");
     if(scenario!=Scenario.Clean)Assert(!result.Contains("resends=0 "),"Loss case did not retransmit");
    }
    Console.WriteLine("PASS: loopback "+rate+" "+scenario+"; decodedPackets="+expert.DecodedPackets);
   }
   using(var rebound=new UdpClient(AddressFamily.InterNetwork)){
    rebound.ExclusiveAddressUse=true;rebound.Client.Bind(new IPEndPoint(IPAddress.Loopback,45456));
   }
   cases++;
  }
  return "PASS: "+cases+" end-to-end loopback transport cases; independent CRC/PCM decode, loss recovery, deadline guards, identity filtering and socket cleanup.";
 }
}
'@
Add-Type -TypeDefinition ("using System; using System.IO; using System.Collections.Generic; using System.Diagnostics; using System.Net; using System.Net.Sockets; using System.Threading;`n"+
    ($sources -join "`n")+"`n"+$tests)
[SenderIntegrationTests]::Run()
