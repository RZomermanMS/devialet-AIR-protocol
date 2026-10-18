param([switch]$DefinitionsOnly)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
public static class ReferenceBlockDecoder {
 public sealed class Packet {
  public long Counter; public int Width,RightWidth; public int[] Left,Right;
 }
 private static byte[] Bytes(string h) {
  var b=new byte[h.Length/2];for(int i=0;i<b.Length;i++)b[i]=Convert.ToByte(h.Substring(2*i,2),16);return b;
 }
 private static int[] Channel(byte[] b,int start,int size,int count) {
  int width=b[start+6];
  if(width>24 || b[start+3]!=0 || b[start+4]!=0 || b[start+5]!=width)
   throw new InvalidDataException("Unsupported channel configuration.");
  if(size!=7+((count-1)*width+7)/8)throw new InvalidDataException("Channel length mismatch.");
  int first=(b[start]<<16)|(b[start+1]<<8)|b[start+2];
  if((first&0x800000)!=0)first-=0x1000000;
  int[] values=new int[count];values[0]=first;int bit=(start+7)*8;
  for(int i=1;i<count;i++){
   int code=0;
   for(int k=0;k<width;k++,bit++)code=(code<<1)|((b[bit/8]>>(7-bit%8))&1);
   int delta=(code>>1)^-(code&1);
   values[i]=checked(values[i-1]+delta);
   if(values[i]<-8388608 || values[i]>8388607)throw new InvalidDataException("Sample outside signed 24-bit range.");
  }
  while(bit<(start+size)*8){if(((b[bit/8]>>(7-bit%8))&1)!=0)throw new InvalidDataException("Nonzero bit padding.");bit++;}
  return values;
 }
 public static Packet Decode(string hex) {
  byte[] b=Bytes(hex);
  if(b.Length<166 || b[0]!=0x44 || b[1]!=0x6d)throw new InvalidDataException("Invalid Dm packet.");
  int end=b.Length-128;
  for(int i=end;i<b.Length;i++)if(b[i]!=0)throw new InvalidDataException("Nonzero trailing padding.");
  int crc=65535;
  for(int i=0;i<end-2;i++){crc^=b[i]<<8;for(int k=0;k<8;k++)crc=((crc&32768)!=0?(crc<<1)^0x1021:crc<<1)&65535;}
  if(crc!=((b[end-2]<<8)|b[end-1]))throw new InvalidDataException("CRC mismatch.");
  int count=(b[20]<<8)|b[21];
  if(count!=200)throw new InvalidDataException("Unsupported frame count.");
  int total=end-24;
  int width=b[28];
  if(width>24)throw new InvalidDataException("Unsupported first channel width.");
  int size=7+((count-1)*width+7)/8;
  int remaining=total-size;
  if(remaining<7)throw new InvalidDataException("Missing second channel block.");
  long counter=0;for(int i=12;i<20;i++)counter=checked(counter*256+b[i]);
  return new Packet{Counter=counter,Width=width,RightWidth=b[22+size+6],
   Left=Channel(b,22,size,count),Right=Channel(b,22+size,remaining,count)};
 }
 public static object Analyze(Packet[] packets,string wavePath,string csvPath) {
  byte[] wav=File.ReadAllBytes(wavePath);
  var observed=new Dictionary<long,int>();int stereoMismatch=0,conflicts=0;
  using(var writer=new StreamWriter(csvPath)){
   writer.WriteLine("Frame,Left24Candidate,Right24Candidate,Reference16");
   foreach(var p in packets)for(int i=0;i<p.Left.Length;i++){
    long frame=p.Counter+i;if(frame<0 || frame>=480000)throw new InvalidDataException("Reference frame out of bounds.");
    if(p.Left[i]!=p.Right[i])stereoMismatch++;
    if(observed.ContainsKey(frame)){if(observed[frame]!=p.Left[i])conflicts++;continue;}
    observed.Add(frame,p.Left[i]);
    writer.WriteLine(frame+","+p.Left[i]+","+p.Right[i]+","+BitConverter.ToInt16(wav,44+(int)frame*4));
   }
  }
  var positions=new List<long>();var decoded=new List<double>();
  int sourceSilent=0,decodedNonzeroWhenSourceSilent=0;
  foreach(var pair in observed){
   int reference=BitConverter.ToInt16(wav,44+(int)pair.Key*4);
   if(reference==0){sourceSilent++;if(pair.Value!=0)decodedNonzeroWhenSourceSilent++;}
   if(pair.Key>=168000 && pair.Key<312000){positions.Add(pair.Key);decoded.Add(pair.Value);}
  }
  if(positions.Count<1000)throw new InvalidDataException("Insufficient steady-tone samples.");
  double best=-1,bestHz=0,bestAmplitude=0;
  for(int step=0;step<=140;step++){
   double hz=990+step*.1,n=positions.Count,sum=0,energy=0,ys=0,yc=0,s=0,c=0,ss=0,cc=0,sc=0;
   for(int i=0;i<positions.Count;i++){
    double angle=2*Math.PI*hz*positions[i]/48000,sine=Math.Sin(angle),cosine=Math.Cos(angle),v=decoded[i];
    sum+=v;energy+=v*v;ys+=v*sine;yc+=v*cosine;s+=sine;c+=cosine;ss+=sine*sine;cc+=cosine*cosine;sc+=sine*cosine;
   }
   ys-=sum*s/n;yc-=sum*c/n;ss-=s*s/n;cc-=c*c/n;sc-=s*c/n;
   double det=ss*cc-sc*sc,a=(cc*ys-sc*yc)/det,b=(ss*yc-sc*ys)/det;
   double score=(a*ys+b*yc)/(energy-sum*sum/n);
   if(score>best){best=score;bestHz=hz;bestAmplitude=Math.Sqrt(a*a+b*b);}
  }
  double bestCorrelation=-1,bestGain=0,bestError=0;int bestLag=0;
  for(int lag=-512;lag<=512;lag++){
   double xy=0,xx=0,yy=0;
   for(int i=0;i<positions.Count;i++){
    int reference=BitConverter.ToInt16(wav,44+((int)positions[i]+lag)*4);
    xy+=reference*decoded[i];xx+=(double)reference*reference;yy+=decoded[i]*decoded[i];
   }
   if(xx==0)continue;double correlation=xy/Math.Sqrt(xx*yy);
   if(correlation>bestCorrelation){bestCorrelation=correlation;bestLag=lag;bestGain=xy/xx;bestError=Math.Sqrt(Math.Max(0,yy-xy*xy/xx)/positions.Count);}
  }
  return new {Packets=packets.Length,UniqueDecodedFrames=observed.Count,StereoMismatches=stereoMismatch,
   ConflictingSamples=conflicts,SourceZeroSamples=sourceSilent,NonzeroDecodedAtSourceZero=decodedNonzeroWhenSourceSilent,
   SteadyToneSamples=positions.Count,BestFrequencyHz=bestHz,FrequencySearchStepHz=.1,ToneFitRSquared=best,
   Candidate24BitTonePeak=bestAmplitude,BestSourceLagFrames=bestLag,BestSourceCorrelation=bestCorrelation,
   GainCandidate24PerSource16=bestGain,GainAdjustedRMSE=bestError};
 }
}
'@
if ($DefinitionsOnly) { return }
$root = $PSScriptRoot
$rows = Import-Csv -LiteralPath 'C:\Evidence\air-reference-wifi-packets.csv'
$audio = @($rows | Where-Object { $_.PayloadHex.StartsWith('446D') })
$decoded = @($audio | ForEach-Object { [ReferenceBlockDecoder]::Decode($_.PayloadHex) })
$result = [ReferenceBlockDecoder]::Analyze($decoded,
    (Join-Path $root 'air-test-48k16-stereo-997hz.wav'),
    (Join-Path $root 'reference-decoded-samples.csv'))
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'reference-decoded-results.json')
$result | Format-List
