$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Decode-ReferenceBlocks.ps1') -DefinitionsOnly
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public static class StereoRampComparison {
 public sealed class Match {
  public int Block,SourceChannel,Lag,Frames;
  public double Correlation,Gain,Offset,RMSE;
 }
 public static Match Fit(List<long> frames,List<int> values,short[] source,int block,int sourceChannel,int lag,int stride){
  double x=0,y=0,xx=0,yy=0,xy=0;int n=0;
  for(int i=0;i<frames.Count;i+=stride){
   long f=frames[i]+lag;if(f<100800 || f>=379200)continue;
   double a=source[(int)f],b=values[i];x+=a;y+=b;xx+=a*a;yy+=b*b;xy+=a*b;n++;
  }
  if(n<100)throw new InvalidDataException("Insufficient matching samples.");
  double vx=xx-x*x/n,vy=yy-y*y/n,cov=xy-x*y/n;
  if(vx<=0 || vy<=0)throw new InvalidDataException("Zero-variance comparison.");
  double gain=cov/vx;
  return new Match{Block=block,SourceChannel=sourceChannel,Lag=lag,Frames=n,
   Correlation=cov/Math.Sqrt(vx*vy),Gain=gain,Offset=(y-gain*x)/n,
   RMSE=Math.Sqrt(Math.Max(0,vy-cov*cov/vx)/n)};
 }
 public static Match[] Compare(long[] counters,int[][] left,int[][] right,string path,string csv){
  byte[] wav=File.ReadAllBytes(path);short[][] source={new short[480000],new short[480000]};
  for(int f=0;f<480000;f++)for(int c=0;c<2;c++)source[c][f]=BitConverter.ToInt16(wav,44+4*f+2*c);
  var frames=new List<long>();var values=new[]{new List<int>(),new List<int>()};
  var seen=new HashSet<long>();
  using(var writer=new StreamWriter(csv)){
   writer.WriteLine("Frame,Block0,Block1,SourceLeftAtUnshiftedFrame,SourceRightAtUnshiftedFrame");
   for(int p=0;p<counters.Length;p++)for(int i=0;i<200;i++){
    long frame=counters[p]+i;if(frame<0 || frame>=480000)throw new InvalidDataException("Counter outside source.");
    if(!seen.Add(frame))continue;
    writer.WriteLine(frame+","+left[p][i]+","+right[p][i]+","+source[0][frame]+","+source[1][frame]);
    if(frame>=105000 && frame<375000){frames.Add(frame);values[0].Add(left[p][i]);values[1].Add(right[p][i]);}
   }
  }
  var results=new List<Match>();
  for(int block=0;block<2;block++)for(int c=0;c<2;c++){
   Match best=null;
   for(int lag=-4096;lag<=4096;lag++){
    var fit=Fit(frames,values[block],source[c],block,c,lag,23);
    if(best==null || fit.Correlation>best.Correlation)best=fit;
   }
   results.Add(Fit(frames,values[block],source[c],block,c,best.Lag,1));
  }
  return results.ToArray();
 }
 public static object[] Validate(long[] counters,int[][] left,int[][] right,string path,int lag){
  byte[] wav=File.ReadAllBytes(path);var results=new List<object>();
  for(int block=0;block<2;block++){
   short[] source=new short[480000];for(int f=0;f<480000;f++)source[f]=BitConverter.ToInt16(wav,44+4*f+2*block);
   var frames=new List<long>();var values=new List<int>();var seen=new HashSet<long>();
   for(int p=0;p<counters.Length;p++)for(int i=0;i<200;i++){
    long frame=counters[p]+i;
    if(frame>=105000 && frame<375000 && seen.Add(frame)){frames.Add(frame);values.Add(block==0?left[p][i]:right[p][i]);}
   }
   // Exclude the every-23rd observations used to select the offset.
   var heldFrames=new List<long>();var heldValues=new List<int>();
   for(int i=0;i<frames.Count;i++)if(i%23!=0){heldFrames.Add(frames[i]);heldValues.Add(values[i]);}
   var neighbors=new List<Match>();
   for(int offset=lag-3;offset<=lag+3;offset++)neighbors.Add(Fit(heldFrames,heldValues,source,block,block,offset,1));
   var best=neighbors[0];foreach(var n in neighbors)if(n.Correlation>best.Correlation)best=n;
   var windows=new List<Match>();
   for(int half=0;half<2;half++){
    var ff=new List<long>();var vv=new List<int>();
    for(int i=0;i<heldFrames.Count;i++)if((heldFrames[i]<240000?0:1)==half){ff.Add(heldFrames[i]);vv.Add(heldValues[i]);}
    Match windowBest=null;
    for(int offset=lag-3;offset<=lag+3;offset++){
     var candidate=Fit(ff,vv,source,block,block,offset,1);
     if(windowBest==null || candidate.Correlation>windowBest.Correlation)windowBest=candidate;
    }
    windows.Add(windowBest);
   }
   int exact=0;double squared=0;int count=0;double max=0;
   for(int i=0;i<heldFrames.Count;i++){
    int actual=source[(int)heldFrames[i]+lag];
    double estimated=(heldValues[i]-best.Offset)/best.Gain,error=estimated-actual;
    if(Math.Round(estimated)==actual)exact++;
    squared+=error*error;max=Math.Max(max,Math.Abs(error));count++;
   }
   results.Add(new {Block=block,HeldOutFrames=count,Neighbors=neighbors.ToArray(),HalfWindowBest=windows.ToArray(),
    GainAdjustedSource16RMSE=Math.Sqrt(squared/count),GainAdjustedSource16MaxError=max,
    RoundedSource16Exact=exact,RoundedSource16ExactFraction=(double)exact/count});
  }
  return results.ToArray();
 }
}
'@
$rows = Import-Csv -LiteralPath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-stereo-ramp-packets.csv'
$audio = @($rows | Where-Object { $_.PayloadHex.StartsWith('446D') })
$decoded = @($audio | ForEach-Object { [ReferenceBlockDecoder]::Decode($_.PayloadHex) })
$left = [int[][]]@($decoded | ForEach-Object { ,$_.Left })
$right = [int[][]]@($decoded | ForEach-Object { ,$_.Right })
$matches = [StereoRampComparison]::Compare([long[]]$decoded.Counter,$left,$right,
    (Join-Path $PSScriptRoot 'air-stereo-nonperiodic-ramp.wav'),
    (Join-Path $PSScriptRoot 'stereo-ramp-decoded-samples.csv'))
$diagonal = @($matches | Where-Object { $_.Block -eq $_.SourceChannel })
if ($diagonal[0].Lag -ne $diagonal[1].Lag) { throw 'Channels do not share a fitted source offset.' }
$validation = [StereoRampComparison]::Validate([long[]]$decoded.Counter,$left,$right,
    (Join-Path $PSScriptRoot 'air-stereo-nonperiodic-ramp.wav'),$diagonal[0].Lag)
$result = [pscustomobject]@{
    CaptureAudioPackets = $audio.Count
    DecodedPackets = $decoded.Count
    WidthPairs = @($decoded | Group-Object Width,RightWidth | Select-Object Name,Count)
    Matches = @($matches)
    Validation = @($validation)
    LagConvention = 'decoded(frame) compared to source(frame + lag); source-relative integer offset, not acoustic latency.'
    SearchRange = '-4096..4096 frames, positive correlation, affine gain/offset; every 23rd sample for search, all active samples for final fit.'
    VolumeBytes = @($rows | Where-Object { $_.PayloadHex.StartsWith('4461') } |
        ForEach-Object { $_.PayloadHex.Substring(620,2) } | Sort-Object -Unique)
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'stereo-ramp-comparison.json')
$matches | Format-Table -AutoSize
$result.WidthPairs | Format-Table -AutoSize
$validation | ForEach-Object {
    $_ | Select-Object Block,HeldOutFrames,GainAdjustedSource16RMSE,GainAdjustedSource16MaxError,
        RoundedSource16ExactFraction | Format-List
    $_.Neighbors | Select-Object Block,Lag,Correlation | Format-Table -AutoSize
    $_.HalfWindowBest | Select-Object Block,Lag,Frames,Correlation | Format-Table -AutoSize
}
