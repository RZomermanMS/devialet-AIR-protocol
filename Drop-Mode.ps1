param(
    [uint64]$Target = 360000,[ValidateSet("resend","df")][string]$Mode = "resend",
    [int]$TimeoutSeconds = 90,
    [int]$PostDropSeconds = 25,
    [string]$LogPath = (Join-Path $PSScriptRoot 'drop-multi.log')
)
$ErrorActionPreference = 'Stop'
$tools = Join-Path $PSScriptRoot 'tools\windivert'
Set-Location -LiteralPath $tools
$env:PATH = $tools + ';' + $env:PATH
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
public static class ModeDropper {
 [DllImport("WinDivert.dll", CallingConvention=CallingConvention.Cdecl, SetLastError=true, CharSet=CharSet.Ansi)]
 static extern IntPtr WinDivertOpen(string filter, int layer, short priority, ulong flags);
 [DllImport("WinDivert.dll", CallingConvention=CallingConvention.Cdecl, SetLastError=true)]
 static extern bool WinDivertRecv(IntPtr h, byte[] pkt, uint len, out uint recvLen, byte[] addr);
 [DllImport("WinDivert.dll", CallingConvention=CallingConvention.Cdecl, SetLastError=true)]
 static extern bool WinDivertSend(IntPtr h, byte[] pkt, uint len, out uint sendLen, byte[] addr);
 [DllImport("WinDivert.dll", CallingConvention=CallingConvention.Cdecl)]
 static extern bool WinDivertClose(IntPtr h);
 public static string Run(string filter, ulong target, bool dfMode, int timeoutSec, int postDropSec, string log) {
  IntPtr h = WinDivertOpen(filter, 0, 0, 0);
  if (h == new IntPtr(-1)) throw new InvalidOperationException("WinDivertOpen failed: " + Marshal.GetLastWin32Error());
  var sw = Stopwatch.StartNew();
  var watchdog = new System.Threading.Thread(() => {
   System.Threading.Thread.Sleep(timeoutSec * 1000);
   WinDivertClose(h);
  });
  watchdog.IsBackground = true; watchdog.Start();
  byte[] pkt = new byte[65535]; byte[] addr = new byte[80];
  long seen = 0, forwarded = 0, dropped = 0; double dropAt = -1; ulong maxCounter = 0; int blockLeft = dfMode ? 1 : 2; int dfLeft = dfMode ? 1 : 0; int total = blockLeft + dfLeft;
  using (var w = new StreamWriter(log, true)) {
   w.WriteLine(DateTime.Now.ToString("o") + " armed: targets " + target + (dfMode ? "+first Df with intervals" : " x2 (original+resend)") + ", filter " + filter);
   w.Flush();
   try {
    while (sw.Elapsed.TotalSeconds < timeoutSec && !(blockLeft + dfLeft == 0 && dropAt >= 0 && sw.Elapsed.TotalSeconds - dropAt > postDropSec)) {
     uint n; if (!WinDivertRecv(h, pkt, (uint)pkt.Length, out n, addr)) continue;
     seen++;
     bool drop = false;
     int ihl = (pkt[0] & 0x0F) * 4;
     int p = ihl + 8;
     if (blockLeft > 0 && n >= p + 20 && pkt[p] == 0x44 && pkt[p+1] == 0x6D) {
      ulong c = 0; for (int i = 0; i < 8; i++) c = (c << 8) | pkt[p + 12 + i];
      if (c > maxCounter) maxCounter = c;
      if (c == target) {
       blockLeft--; drop = true; dropped++; if (blockLeft + dfLeft == 0) dropAt = sw.Elapsed.TotalSeconds;
       w.WriteLine(DateTime.Now.ToString("o") + " DROPPED Dm counter " + c + " length " + n + " (remaining block drops " + blockLeft + ")");
       w.Flush();
      }
     } else if (dfLeft > 0 && blockLeft == 0 && n >= p + 41 && pkt[p] == 0x44 && pkt[p+1] == 0x66 && ((pkt[p+37] << 8) | pkt[p+38]) > 0) {
      dfLeft--; drop = true; dropped++; dropAt = sw.Elapsed.TotalSeconds;
      w.WriteLine(DateTime.Now.ToString("o") + " DROPPED Df with " + ((pkt[p+37] << 8) | pkt[p+38]) + " interval(s), length " + n);
      w.Flush();
     }
     if (!drop) { uint s; WinDivertSend(h, pkt, n, out s, addr); forwarded++; }
    }
   } finally {
    WinDivertClose(h);
    w.WriteLine(DateTime.Now.ToString("o") + " closed: seen " + seen + ", forwarded " + forwarded + ", dropped " + dropped + ", maxCounter " + maxCounter);
   }
  }
  return dropped + " dropped";
 }
}
'@
$filter = '(outbound and ip and udp and ip.DstAddr == 172.16.5.90 and udp.DstPort == 45455) or (inbound and ip and udp and ip.SrcAddr == 172.16.5.90 and udp.DstPort == 45456)'
[ModeDropper]::Run($filter, $Target, ($Mode -eq "df"), $TimeoutSeconds, $PostDropSeconds, $LogPath)


