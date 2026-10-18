param(
    [Parameter(Mandatory=$true)][string]$CapturePath,
    [Parameter(Mandatory=$true)][long]$ExpectedFrames,
    [Parameter(Mandatory=$true)][ValidateRange(1,65535)][int]$SessionId,
    [ValidateRange(0,253)][int]$Gen=30,
    [ValidateSet(44100,48000)][int]$SampleRate=44100,
    [Parameter(Mandatory=$true)][string]$SourceAddress,
    [Parameter(Mandatory=$true)][string]$ExpertAddress
)
$ErrorActionPreference='Stop'
$CapturePath=(Get-Item -LiteralPath $CapturePath).FullName
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw 'Decoder syntax invalid' }
$decoder=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
    $node.Value.Contains('public static class ReferenceBlockDecoder')
},$true))
if($decoder.Count -ne 1) { throw 'Expected exactly one independent decoder' }
$verify=@'
public static class SenderCaptureVerification {
 static long BE(byte[] d,int offset,int size){
  long value=0;for(int i=0;i<size;i++)value=(value<<8)|d[offset+i];return value;
 }
 static byte[] Bytes(string hex){
  if(hex.Length%2!=0)throw new Exception("Odd payload length");
  var bytes=new byte[hex.Length/2];
  for(int i=0;i<bytes.Length;i++)bytes[i]=Convert.ToByte(hex.Substring(2*i,2),16);
  return bytes;
 }
 static void Assert(bool value,string message){if(!value)throw new Exception(message);}
 public static string Run(string tshark,string path,long frames,int session,int gen,int rate,string source,string expert){
  if(frames<=0)throw new ArgumentOutOfRangeException("frames");
  var start=new ProcessStartInfo(tshark,"-r \""+path+"\" -Y \"udp.payload[0:2]==44:6d || udp.payload[0:2]==44:66\" -T fields -e ip.src -e ip.dst -e udp.srcport -e udp.dstport -e udp.payload");
  start.UseShellExecute=false;start.CreateNoWindow=true;
  start.RedirectStandardOutput=true;start.RedirectStandardError=true;
  var errors=new System.Text.StringBuilder();
  using(var process=new Process()){
   process.StartInfo=start;
   process.ErrorDataReceived+=(sender,e)=>{if(e.Data!=null)lock(errors){errors.AppendLine(e.Data);}};
   Assert(process.Start(),"tshark failed to start");process.BeginErrorReadLine();
   long last=-200,unique=0,repeated=0,feedback=0,reports=0,maxB=-1,lastF=0,startup=0;
   long expectedBlocks=(frames+199)/200;int padding=0;
   var recent=new Dictionary<long,string>();
   try {
    string line;
    while((line=process.StandardOutput.ReadLine())!=null){
     string[] fields=line.Split('\t');
     Assert(fields.Length==5,"Unexpected tshark field count");
     string hex=fields[4];byte[] data=Bytes(hex);
     if(data.Length>=22&&data[0]==0x44&&data[1]==0x6d){
      if(fields[0]!=source||fields[1]!=expert||fields[2]!="45456"||fields[3]!="45455")continue;
      if(BE(data,5,2)!=session)continue;
      if(data[10]!=gen&&data[10]!=gen+2)continue;
      var packet=ReferenceBlockDecoder.Decode(hex);
      if(data[10]==gen){
       Assert(packet.Counter==startup*200,"Startup counter gap or duplicate");
       Assert(data[11]==(rate==44100?0:2),"Wrong startup rate mode");
       startup++;continue;
      }
      long counter=packet.Counter;
      Assert(data[11]==(rate==44100?0:2)+(counter/200>=(rate==44100?227:250)?1:0),"Wrong audio mode");
      if(counter<=last){
       string original;
       Assert(recent.TryGetValue(counter,out original)&&original==hex,"Retransmission differs or is outside cache");
       repeated++;continue;
      }
      Assert(counter==last+200,"Sender-side capture has a missing audio counter");
      unique++;last=counter;recent[counter]=hex;recent.Remove(counter-80000);
      Assert(unique<=expectedBlocks,"Extra audio after expected EOF");
      if(unique==expectedBlocks){
       for(int i=(int)(frames-counter);i<200;i++){
        Assert(packet.Left[i]==0&&packet.Right[i]==0,"Nonzero final partial-block padding");
        padding++;
       }
      }
     }else if(data.Length>=41&&data[0]==0x44&&data[1]==0x66){
      if(fields[0]!=expert||fields[1]!=source||fields[2]!="45456"||fields[3]!="45456"||
         BE(data,4,2)!=session||data[9]!=gen+2)continue;
      Assert((data.Length-41)%4==0&&BE(data,37,2)==(data.Length-41)/4,"Malformed captured feedback");
      int crc=65535;
      for(int i=0;i<data.Length-2;i++){crc^=data[i]<<8;for(int bit=0;bit<8;bit++)crc=((crc&32768)!=0?(crc<<1)^0x1021:crc<<1)&65535;}
      Assert(crc==BE(data,data.Length-2,2),"Captured feedback CRC invalid");
      long b=BE(data,18,8);
      Assert(b>=0&&b%200==0&&b<=last,"Captured acknowledgement outside sent bounds");
      maxB=Math.Max(maxB,b);lastF=BE(data,26,8);feedback++;
      if(BE(data,37,2)>0)reports++;
     }
    }
    process.WaitForExit();
    Assert(process.ExitCode==0,"tshark failed: "+errors.ToString());
    Assert(startup==38,"Startup packet count mismatch");
    Assert(unique==expectedBlocks,"Track capture incomplete");
    Assert(maxB==last,"Final sent block not acknowledged in capture");
    Assert(lastF>=last+200,"Captured F did not reach padded track end");
    return "PASS: "+unique+" unique audio blocks independently decoded/CRC-checked; "+repeated+
     " byte-identical retransmissions; startup="+startup+"; Df="+feedback+"; intervalReports="+reports+
     "; finalB="+maxB+"; finalF="+lastF+"; zeroPaddingFrames="+padding+".";
   }finally{
    if(!process.HasExited){process.Kill();process.WaitForExit();}
   }
  }
 }
}
'@
$source=[regex]::Replace($decoder[0].Value,'(?m)^using [^\r\n]+;\r?\n','')
Add-Type -TypeDefinition ("using System; using System.IO; using System.Collections.Generic; using System.Diagnostics;`n"+$source+"`n"+$verify)
[SenderCaptureVerification]::Run('C:\Program Files\Wireshark\tshark.exe',$CapturePath,$ExpectedFrames,
    $SessionId,$Gen,$SampleRate,$SourceAddress,$ExpertAddress)
