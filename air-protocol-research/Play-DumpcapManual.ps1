param(
    [string]$WaveName = 'air-test-48k16-stereo-997hz.wav',
    [string]$ExpectedSHA256 = 'EFCED6291888A928155BD2F5C6DBE7114C45B0D7861CC3D452CA769E9E727B05',
    [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$CaptureStem = 'air-reference'
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
Start-Transcript -LiteralPath (Join-Path $PSScriptRoot ($CaptureStem + '-playback.log'))
$capturing = $false
$filterAdded = $false
try {
    $wav = Join-Path $PSScriptRoot $WaveName
    if ((Get-FileHash -LiteralPath $wav -Algorithm SHA256).Hash -ne $ExpectedSHA256) {
        throw 'Reference WAV checksum mismatch.'
    }
    $dumpcap = 'C:\Program Files\Wireshark\dumpcap.exe'
    $capProc = $null
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
public static class ReferenceWavePlayer {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 private struct Caps {
  public ushort Manufacturer, Product; public uint Version;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Name;
  public uint Formats; public ushort Channels, Reserved; public uint Support;
 }
 [StructLayout(LayoutKind.Sequential, Pack=2)]
 private struct Format { public ushort Tag, Channels; public uint Rate, BytesPerSecond; public ushort Alignment, Bits, Extra; }
 [StructLayout(LayoutKind.Sequential)]
 private struct Header { public IntPtr Data; public uint Length, Recorded; public UIntPtr User; public uint Flags, Loops; public IntPtr Next; public UIntPtr Reserved; }
 [DllImport("winmm.dll")] private static extern uint waveOutGetNumDevs();
 [DllImport("winmm.dll",CharSet=CharSet.Unicode)] private static extern uint waveOutGetDevCapsW(UIntPtr id,out Caps caps,uint size);
 [DllImport("winmm.dll")] private static extern uint waveOutOpen(out IntPtr h,uint id,ref Format f,IntPtr cb,IntPtr instance,uint flags);
 [DllImport("winmm.dll")] private static extern uint waveOutPrepareHeader(IntPtr h,IntPtr p,uint size);
 [DllImport("winmm.dll")] private static extern uint waveOutWrite(IntPtr h,IntPtr p,uint size);
 [DllImport("winmm.dll")] private static extern uint waveOutReset(IntPtr h);
 [DllImport("winmm.dll")] private static extern uint waveOutUnprepareHeader(IntPtr h,IntPtr p,uint size);
 [DllImport("winmm.dll")] private static extern uint waveOutClose(IntPtr h);
 private static void Check(uint result,string op) { if(result!=0) throw new InvalidOperationException(op+": MMRESULT "+result); }
 public static string Play(string path) {
  byte[] wav=File.ReadAllBytes(path);
  uint device=uint.MaxValue; string name=null;
  for(uint i=0;i<waveOutGetNumDevs();i++) {
   Caps caps; Check(waveOutGetDevCapsW(new UIntPtr(i),out caps,(uint)Marshal.SizeOf(typeof(Caps))),"Enumerate");
   if(caps.Name.IndexOf("Devialet AIR",StringComparison.OrdinalIgnoreCase)>=0) {
    if(device!=uint.MaxValue) throw new InvalidOperationException("Multiple AIR outputs.");
    device=i;name=caps.Name;
   }
  }
  if(device==uint.MaxValue) throw new InvalidOperationException("AIR output missing.");
  var f=new Format {Tag=1,Channels=2,Rate=48000,BytesPerSecond=192000,Alignment=4,Bits=16};
  IntPtr h; Check(waveOutOpen(out h,device,ref f,IntPtr.Zero,IntPtr.Zero,0),"Open");
  IntPtr data=IntPtr.Zero,header=IntPtr.Zero; bool prepared=false;
  uint size=(uint)Marshal.SizeOf(typeof(Header));
  try {
   data=Marshal.AllocHGlobal(wav.Length-44); Marshal.Copy(wav,44,data,wav.Length-44);
   header=Marshal.AllocHGlobal((int)size);
   Marshal.StructureToPtr(new Header {Data=data,Length=(uint)(wav.Length-44)},header,false);
   Check(waveOutPrepareHeader(h,header,size),"Prepare");prepared=true;
   Check(waveOutWrite(h,header,size),"Write");
   var deadline=DateTime.UtcNow.AddSeconds(20);
   while((((Header)Marshal.PtrToStructure(header,typeof(Header))).Flags&1)==0) {
    if(DateTime.UtcNow>deadline) throw new TimeoutException("Playback timeout.");
    Thread.Sleep(20);
   }
  } finally {
   try { Check(waveOutReset(h),"Reset"); if(prepared) Check(waveOutUnprepareHeader(h,header,size),"Unprepare"); }
   finally { uint result=waveOutClose(h); if(header!=IntPtr.Zero)Marshal.FreeHGlobal(header);if(data!=IntPtr.Zero)Marshal.FreeHGlobal(data);Check(result,"Close"); }
  }
  return name;
 }
}
'@
    function Get-AirTrayName {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $class = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'SystemTray.NormalButton')
        $icon = $root.FindAll('Descendants', $class) | Where-Object { $_.Current.Name -like 'Devialet AIR - *' } | Select-Object -First 1
        if ($icon) { $icon.Current.Name } else { 'unknown' }
    }
    $pcap = Join-Path $PSScriptRoot ($CaptureStem + '.pcapng')
    $capProc = Start-Process -FilePath $dumpcap -ArgumentList @('-i','5','-s','0','-B','32','-f','"host 192.0.2.20"','-w',('"' + $pcap + '"')) -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    if ($capProc.HasExited) { throw 'dumpcap failed to start.' }
    $capturing = $true
    Write-Host ((Get-Date).ToString('o') + ' GO: capture running; waiting up to 120s for you to enable the Expert in the AIR tray menu.')
    [Console]::Beep(880,300)
    $deadline = (Get-Date).AddSeconds(120)
    $tshark = 'C:\Program Files\Wireshark\tshark.exe'
    $name = 'streaming assumed on'
    Start-Sleep -Seconds 3
    Write-Host ('AIR tray now: ' + $name)
    Write-Host ((Get-Date).ToString('o') + ' Streaming enabled.')
    Start-Sleep -Seconds 3
    Write-Host ((Get-Date).ToString('o') + ' Reference file playback starting; no volume APIs are used.')
    $output = [ReferenceWavePlayer]::Play($wav)
    Write-Host ((Get-Date).ToString('o') + ' Playback completed on ' + $output)
    Start-Sleep -Seconds 3
    Stop-Process -Id $capProc.Id
    $capProc.WaitForExit(5000) | Out-Null
    $capturing = $false
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $PSScriptRoot ($CaptureStem + '-error.txt'))
    throw
} finally {
    if ($capturing -and $capProc -and !$capProc.HasExited) { Stop-Process -Id $capProc.Id }
    Stop-Transcript
}

