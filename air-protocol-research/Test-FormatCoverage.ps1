$ErrorActionPreference='Stop'
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Test-EncoderRoundTrip.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw 'Encoder script has syntax errors' }
$definitions=@($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
    $node.StringConstantType -eq 'SingleQuotedHereString' -and
    $node.Value.Contains('public static class DmEnc')
},$true))
if($definitions.Count -ne 1) { throw 'Expected exactly one existing encoder definition' }
$decoderAst=[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw 'Decoder script has syntax errors' }
$decoderDefinitions=@($decoderAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
    $node.StringConstantType -eq 'SingleQuotedHereString' -and
    $node.Value.Contains('public static class ReferenceBlockDecoder')
},$true))
if($decoderDefinitions.Count -ne 1) { throw 'Expected exactly one existing decoder definition' }

$coverage=@'
using System;
using System.IO;
public static class FormatCoverage {
 public static string Run() {
  int packets=0,samples=0;
  var random=new Random(20261018);
  var header=new byte[22];header[0]=0x44;header[1]=0x6d;header[20]=0;header[21]=200;
  // No sample-rate field is asserted here: these are offline codec fixtures.
  foreach(int bits in new int[]{16,24}) {
   for(int scenario=0;scenario<5;scenario++) {
    int[] left=new int[200],right=new int[200];
    for(int i=0;i<200;i++) {
     int a,b;
     if(scenario==0) { a=0;b=0; }
     else if(scenario==1) { a=bits==24?-8388608:-32768;b=bits==24?8388607:32767; }
     else if(scenario==2) { a=1000+i;b=-1000-i; }
     else if(scenario==3) {
      int peak=bits==24?6000000:30000;
      a=(int)Math.Round(peak*Math.Sin(2*Math.PI*i/43));
      b=(int)Math.Round(peak*Math.Sin(2*Math.PI*i/31));
     } else {
      // Restrict deltas to the currently supported <=24-bit code width.
      a=random.Next(-2000000,2000001);b=random.Next(-2000000,2000001);
      if(bits==16) { a/=200;b/=200; }
     }
     left[i]=bits==16?a*256:a;right[i]=bits==16?b*256:b;
    }
    int wl=DmEnc.MinWidth(left),wr=DmEnc.MinWidth(right);
    byte[] raw=DmEnc.Packet(header,left,right,wl,wr);
    var decoded=ReferenceBlockDecoder.Decode(BitConverter.ToString(raw).Replace("-",""));
    for(int i=0;i<200;i++) {
     if(decoded.Left[i]!=left[i]||decoded.Right[i]!=right[i])
      throw new Exception("Precision lost for "+bits+"-bit fixture "+scenario);
    }
    byte[] reencoded=DmEnc.Packet(header,decoded.Left,decoded.Right,decoded.Width,decoded.RightWidth);
    if(!DmEnc.Same(raw,reencoded))throw new Exception("Packet round-trip mismatch");
    packets++;samples+=400;
   }
  }
  int[] extreme=new int[200];
  for(int i=0;i<200;i++)extreme[i]=(i%2==0)?-8388608:8388607;
  int width=DmEnc.MinWidth(extreme);
  if(width!=25)throw new Exception("Full-range transition must require 25 bits");
  byte[] edge=DmEnc.Packet(header,extreme,extreme,width,width);
  bool rejected=false;
  try { ReferenceBlockDecoder.Decode(BitConverter.ToString(edge).Replace("-","")); }
  catch(InvalidDataException) { rejected=true; }
  if(!rejected)throw new Exception("Unexpected decoder acceptance of unverified width 25");
  return packets+" exact codec fixture round-trips; "+samples+
   " channel samples preserved; 24-bit low bits preserved; width-25 limitation confirmed.";
 }
}
'@
$source=$coverage+"`n"+$definitions[0].Value+"`n"+$decoderDefinitions[0].Value
$source=[regex]::Replace($source,'(?m)^using [^\r\n]+;\r?\n','')
Add-Type -TypeDefinition ("using System; using System.IO; using System.Collections.Generic;`n"+$source)
[FormatCoverage]::Run()
