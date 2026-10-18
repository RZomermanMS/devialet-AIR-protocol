$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class AirBlockProbe {
 public static byte[] Bytes(string hex) {
  var b=new byte[hex.Length/2];for(int i=0;i<b.Length;i++)b[i]=Convert.ToByte(hex.Substring(i*2,2),16);return b;
 }
 public static bool Crc(byte[] b,int length) {
  int c=65535;for(int i=0;i<length-2;i++){c^=b[i]<<8;for(int k=0;k<8;k++)c=((c&32768)!=0?(c<<1)^0x1021:c<<1)&65535;}
  return c==((b[length-2]<<8)|b[length-1]);
 }
 public static object[] Probe(string hex) {
  byte[] b=Bytes(hex);var results=new List<object>();
  for(int offset=25;offset<=30;offset++)for(int shift=0;shift<8;shift++)
  for(int byteOrder=0;byteOrder<2;byteOrder++)for(int valueOrder=0;valueOrder<2;valueOrder++)
  for(int transform=0;transform<4;transform++){
   var samples=new double[180]; double curvature=0,energy=0;
   for(int i=0;i<samples.Length;i++){
    int v=0;
    for(int k=0;k<9;k++){
     int bit=offset*8+shift+i*9+k;
     int digit=(b[bit/8]>>(byteOrder==0?7-bit%8:bit%8))&1;
     if(valueOrder==0)v=(v<<1)|digit;else v|=digit<<k;
    }
    int decoded=transform==0?(v>=256?v-512:v):transform==1?((v>>1)^-(v&1)):transform==2?((v&256)!=0?-(v&255):v):v-256;
    samples[i]=decoded;
    energy+=decoded*decoded;
    if(i>=2){double d=samples[i]-2*samples[i-1]+samples[i-2];curvature+=d*d;}
   }
   results.Add(new {Offset=offset,Shift=shift,ByteOrder=byteOrder,ValueOrder=valueOrder,Transform=transform,
    Score=curvature/Math.Max(energy,1),First=string.Join(",",Array.ConvertAll(samples,x=>x.ToString()).GetRange(0,12))});
  }
  return results.ToArray();
 }
 private static T[] GetRange<T>(this T[] source,int start,int count){var a=new T[count];Array.Copy(source,start,a,0,count);return a;}
 public static object[] Fit(string hex) {
  byte[] b=Bytes(hex);var result=new List<object>();
  for(int width=1;width<=16;width++)for(int start=25*8;start<32*8;start++)
  for(int order=0;order<4;order++)for(int transform=0;transform<3;transform++)
  for(int predictor=0;predictor<3;predictor++){
   const int n=160;if(start+n*width>253*8)continue;
   double sum=0,energy=0,sin=0,cos=0,sumSin=0,sumCos=0,ss=0,cc=0,sc=0;
   double last=0,delta=0;
   for(int i=0;i<n;i++){
    int value=0;
    for(int k=0;k<width;k++){
     int pos=start+i*width+k;
     int bit=(b[pos/8]>>((order&1)==0?7-pos%8:pos%8))&1;
     if((order&2)==0)value=(value<<1)|bit;else value|=bit<<k;
    }
    int mask=1<<(width-1);
    double v=transform==0?(value>=mask?value-2*mask:value):
      transform==1?((value>>1)^-(value&1)):((value&mask)!=0?-(value&(mask-1)):value);
    if(predictor==1){last+=v;v=last;}else if(predictor==2){delta+=v;last+=delta;v=last;}
    double s=Math.Sin(2*Math.PI*997*i/48000),c=Math.Cos(2*Math.PI*997*i/48000);
    sum+=v;energy+=v*v;sin+=v*s;cos+=v*c;sumSin+=s;sumCos+=c;ss+=s*s;cc+=c*c;sc+=s*c;
   }
   double variance=energy-sum*sum/n;
   if(variance<1)continue;
   sin-=sum*sumSin/n;cos-=sum*sumCos/n;ss-=sumSin*sumSin/n;cc-=sumCos*sumCos/n;sc-=sumSin*sumCos/n;
   double det=ss*cc-sc*sc;
   double explained=(cc*sin*sin-2*sc*sin*cos+ss*cos*cos)/det;
   result.Add(new{Width=width,StartBit=start,Order=order,Transform=transform,Predictor=predictor,RSquared=explained/variance});
  }
  return result.ToArray();
 }
}
'@
$rows = Import-Csv -LiteralPath 'C:\Evidence\air-reference-wifi-packets.csv'
$tone = $rows | Where-Object { $_.PayloadHex.StartsWith('446D') -and $_.PayloadLength -eq '614' } | Select-Object -First 1
[AirBlockProbe]::Probe($tone.PayloadHex) | Sort-Object Score | Select-Object -First 12 | Format-Table -AutoSize
$steady = $rows | Where-Object { $_.PayloadHex.StartsWith('446D') -and $_.PayloadLength -eq '614' -and
    [Convert]::ToInt64($_.PayloadHex.Substring(24,16),16) -gt 160000 } | Select-Object -First 1
'=== FIXED-WIDTH / PREDICTOR HYPOTHESES AGAINST 997 HZ ==='
[AirBlockProbe]::Fit($steady.PayloadHex) | Sort-Object RSquared -Descending | Select-Object -First 12 | Format-Table -AutoSize
$summary = foreach ($group in ($rows | Where-Object { $_.PayloadHex.StartsWith('446D') } | Group-Object PayloadLength)) {
    $crcValid = 0
    $paddingValid = 0
    $halvesEqual = 0
    foreach ($row in $group.Group) {
        $b = [AirBlockProbe]::Bytes($row.PayloadHex)
        $end = $b.Length - 128
        if ([AirBlockProbe]::Crc($b, $end)) { $crcValid++ }
        if (@($b[$end..($b.Length - 1)] | Where-Object { $_ -ne 0 }).Count -eq 0) { $paddingValid++ }
        $channelLength = ($end - 2 - 22) / 2
        if ($channelLength -eq [Math]::Floor($channelLength) -and
            [BitConverter]::ToString($b,22,$channelLength) -eq
            [BitConverter]::ToString($b,22+$channelLength,$channelLength)) { $halvesEqual++ }
    }
    [pscustomobject]@{
        Length = [int]$group.Name
        Packets = $group.Count
        CRCBefore128BytePadding = $crcValid
        Zero128BytePadding = $paddingValid
        EqualChannelHalves = $halvesEqual
        CandidateChannelBytes = ([int]$group.Name - 128 - 2 - 22) / 2
    }
}
$summary | Format-Table -AutoSize
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'reference-block-structure.json')
