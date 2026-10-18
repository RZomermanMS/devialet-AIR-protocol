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
    $status = & pktmon status
    if ($LASTEXITCODE -ne 0 -or ($status -join "`n") -notmatch 'Packet Monitor is not running') {
        throw 'Capture already active or status unknown.'
    }
    $filters = & pktmon filter list
    if ($LASTEXITCODE -ne 0 -or ($filters -join "`n") -notmatch 'None') {
        throw 'Existing packet filters found; refusing to modify them.'
    }
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
    function Open-AirMenu {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $class = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'SystemTray.NormalButton')
        $icon = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $class) |
            Where-Object { $_.Current.Name -like 'Devialet AIR - *' } | Select-Object -First 1
        if (!$icon) {
            $condition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, 'Show Hidden Icons')
            $button = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
            if (!$button) { throw 'Hidden icon control unavailable.' }
            $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Start-Sleep -Milliseconds 400
            $icon = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $class) |
                Where-Object { $_.Current.Name -like 'Devialet AIR - *' } | Select-Object -First 1
        }
        if (!$icon) { throw 'AIR icon unavailable.' }
        Write-Host ('AIR tray: ' + $icon.Current.Name)
        $icon.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 400
        $air = Get-Process -Name DevialetAIR -ErrorAction Stop
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $air.Id)
        return $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    }
    $items = Open-AirMenu
    $disable = $items | Where-Object { $_.Current.Name -eq 'Disable Devialet AIR' } | Select-Object -First 1
    if (!$disable) { throw 'AIR disable control unavailable.' }
    $disable.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 1
    & pktmon filter add AIRReferenceWave -i 192.0.2.20
    if ($LASTEXITCODE -ne 0) { throw 'Filter creation failed.' }
    $filterAdded = $true
    & pktmon start --capture --comp nics --pkt-size 0 --file-name ($CaptureStem + '.etl') --file-size 64
    if ($LASTEXITCODE -ne 0) { throw 'Capture start failed.' }
    $capturing = $true
    $items = Open-AirMenu
    $device = $items | Where-Object { $_.Current.Name -eq 'Devialet-WIFI (00:23:A7:28:27:C0)' } | Select-Object -First 1
    if (!$device -or !$device.Current.IsEnabled) { throw 'Expert connection unavailable.' }
    $device.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Host ((Get-Date).ToString('o') + ' Selected Expert connection.')
    Start-Sleep -Seconds 3
    Write-Host ((Get-Date).ToString('o') + ' Reference file playback starting; no volume APIs are used.')
    $output = [ReferenceWavePlayer]::Play($wav)
    Write-Host ((Get-Date).ToString('o') + ' Playback completed on ' + $output)
    Start-Sleep -Seconds 3
    & pktmon stop
    if ($LASTEXITCODE -ne 0) { throw 'Capture stop failed.' }
    $capturing = $false
    & pktmon etl2pcap ($CaptureStem + '.etl') --out ($CaptureStem + '.pcapng')
    if ($LASTEXITCODE -ne 0) { throw 'Capture conversion failed.' }
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $PSScriptRoot ($CaptureStem + '-error.txt'))
    throw
} finally {
    if ($capturing) {
        & pktmon stop
        if ($LASTEXITCODE -ne 0) { Write-Error 'Could not stop reference capture.' }
    }
    if ($filterAdded) {
        & pktmon filter remove AIRReferenceWave
        if ($LASTEXITCODE -ne 0) { Write-Error 'Could not remove reference filter.' }
    }
    Stop-Transcript
}
