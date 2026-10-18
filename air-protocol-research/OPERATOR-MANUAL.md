# Operator manual

## Scope and safety

This manual covers the current `Send-Mp3.ps1` and `Send-Playlist.ps1`
Windows research tools. They send decoded local music directly to an Expert,
without official AIR. They are not a system-wide Windows audio endpoint.
Only stereo 44100/48000 Hz PCM16 input paths are in the tested contract.
The source MP3 is decoded, and resampled when necessary; compressed MP3 bytes
are not sent to the Expert.

Use only audio you are entitled to play. Live operation is audible: arrange
explicit approval and a safe manually selected hardware volume first.
Gain is a sender multiplier, not a calibrated device-volume control.
Default gain is 0.25; gain 1.4 was authorized for specific lab trials and is
not a universal recommendation. Do not infer safety from a packet ACK.

## Requirements and dependency setup

- Windows PowerShell 5.1 / .NET Framework and Windows Media Foundation.
- Wireshark with Npcap; scripts expect `dumpcap.exe` and `tshark.exe` under
  `C:\Program Files\Wireshark`. Configure capture permissions according to
  the Npcap installation. Do not disable protections to make capture work.
- NAudio **2.2.1** NuGet packages, not included in this repository.
- IPv4 reachability and broadcast status visibility to the Expert; correct
  route and capture interface. Ethernet on the sender was used for later
  tests, but this alone does not guarantee reliability.
- A writable working copy: captures are generated beside the scripts.

For NAudio, retrieve version 2.2.1 packages from
`https://www.nuget.org/api/v2/package/<package-id>/2.2.1`.
Extract each package under `tools\naudio\<lowercase-package-id>`.
Packages are ZIP containers; if using Expand-Archive, download/copy them
with a `.zip` suffix first. Required assembly paths:

```text
tools\naudio\naudio\lib\net472\NAudio.dll
tools\naudio\naudio.core\lib\netstandard2.0\NAudio.Core.dll
tools\naudio\naudio.winmm\lib\netstandard2.0\NAudio.WinMM.dll
tools\naudio\naudio.asio\lib\netstandard2.0\NAudio.Asio.dll
tools\naudio\naudio.midi\lib\netstandard2.0\NAudio.Midi.dll
tools\naudio\naudio.wasapi\lib\netstandard2.0\NAudio.Wasapi.dll
```

Corresponding package IDs are NAudio, NAudio.Core, NAudio.WinMM, NAudio.Asio,
NAudio.Midi and NAudio.Wasapi. Review their licenses and keep packages local.
Do not commit DLLs or package archives. Source/codec/mock tests do not require
these assemblies; local MP3 decode and playback do.

Commands below use process-scoped execution-policy bypass; they do not change
machine policy. They assume `air-protocol-research` is the current directory.
Replace all example paths/addresses/interface numbers with your own values.
Documentation addresses `192.0.2.x` cannot route to a real Expert.

## 1. Identify interface and inspect status

After approval for passive capture:

```powershell
& 'C:\Program Files\Wireshark\dumpcap.exe' -D
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Find-Experts.ps1 `
  -CaptureInterface 1 -ExpertAddress 192.0.2.20 -NetworkInputIndex 9
```

`CaptureInterface` is the dumpcap index, not the Windows adapter index. Input
index 9 is an example, not universal. See [DISCOVERY.md](./DISCOVERY.md).
Manually ensure the Expert is on, unmuted, with its enabled network input
selected and hardware volume at an appropriate level. The sender refuses
stale status, wrong/disabled input, ambiguous devices, observed competing Dm
or an occupied local UDP 45456 port. It changes none of those conditions.

Keep official AIR streaming and other senders off. A quiet passive capture
cannot prove global exclusivity on a switched/Wi-Fi network.

## 2. Start a bounded excerpt

After explicit playback approval, use a unique capture stem:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Send-Mp3.ps1 `
  -Mp3 'C:\Audio\test-track.mp3' -SampleRate 48000 -Gain 0.25 `
  -MaxSeconds 12 -CaptureInterface 1 -ExpertAddress 192.0.2.20 `
  -NetworkInputIndex 9 -Stem 'air-local-check' `
  -StopFile 'C:\Audio\air-stop.signal'
```

To test 44100 Hz, replace `-SampleRate 48000` with
`-SampleRate 44100 -ExperimentalRate`. The flag remains required even though
44.1 kHz has live evidence. Omitting MaxSeconds or setting it to zero plays
through natural EOF. Do not start a long run before a bounded check.

Leave Gen, SessionId and Startup unspecified for normal operation:
generation 30/32, random nonzero session, generated 38-block silence startup.
Generated startup does not require a pcap. `-Startup Captured` is a legacy
diagnostic requiring private evidence, not a fallback or normal setup.
Generation zero failed in one tested lifecycle state; do not use it.

## 3. Stop and playlists

In another PowerShell window, create the exact stop file passed at startup:

```powershell
New-Item -ItemType File -Path 'C:\Audio\air-stop.signal'
```

Stop produces a nonzero cancellation exit, closes the sending socket and
prevents later playlist tracks. The Expert may finish queued audio: this is
not immediate mute or remote flush. A synchronous native decode call delays
stop handling until it returns. Do not use forced parent termination as the
normal stop mechanism.

Before a new playback, explicitly remove the known stop file:

```powershell
Remove-Item -LiteralPath 'C:\Audio\air-stop.signal'
```

For sequential separate-session playback, open a fresh PowerShell process
with `powershell.exe -NoProfile -ExecutionPolicy Bypass`, then:

```powershell
& .\Send-Playlist.ps1 -Mp3 @('C:\Audio\first.mp3','C:\Audio\second.mp3') `
  -SampleRate 48000 -Gain 0.25 -CaptureInterface 1 `
  -ExpertAddress 192.0.2.20 -NetworkInputIndex 9 `
  -StopFile 'C:\Audio\air-stop.signal'
```

Each track gets new discovery/startup and a fresh session. Any track failure
stops the playlist; transitions are not gapless. MaxSeconds, if supplied,
applies per track.

## 4. Interpret results

- `STARTUP READY`: matching startup feedback acknowledged the last silence
  block. This alone does not mean music played successfully.
- `elapsed`, `sent`, `B`, `F`: source progress and receiver feedback.
- `RECOVERY`: validated interval requests entered bounded paced repair.
- `maxReadMs` / `maxLateMs`: synchronous decoder stall / send lateness.
- `ACKNOWLEDGED`: all sent blocks acknowledged and F reached padded track
  end. It explicitly does **not** certify acoustic playout.
- Exception/nonzero exit: failed or cancelled playback, not a completed track.

For source completeness, compare decoded frame counts/hashes and validate the
capture separately; an internally consistent short stream can still omit
source frames. See the [developer manual](./DEVELOPER-MANUAL.md).

## Troubleshooting

| Symptom | Action |
|---|---|
| Assembly missing | Check the exact six NAudio paths above; do not install a different version blindly |
| dumpcap fails | Verify installation, selected dumpcap index and approved capture permissions |
| No/stale Expert | Check broadcast-domain visibility, selected interface, VLAN/client isolation and actual device state |
| Port busy/competing traffic | Identify the owner; stop only your own approved sender normally; never steal/share the socket |
| Startup not acknowledged | Keep the refusal; check input/status/network and retry only after inspecting the failure with a fresh session |
| Feedback absent or B stalled | Retain log/capture locally. Playback failed; there is no automatic recovery. Do not remove the watchdog |
| Recovery outside cache/bounds | Fail closed. Do not guess missing packets or enlarge limits without testing |
| Stop file already exists | Confirm the previous run ended, then remove only that named signal file |
| Playback sounds wrong | Stop; independently check levels, pitch/timing and audio output. ACKs do not establish fidelity |

Unresolved B stalls occurred in current-code live runs even with continuing
feedback. See [LONG-RUN.md](./LONG-RUN.md); no single network or clock cause is
proven. Native pause, seek, flush, high rates, native PCM24, cold-boot and
cross-device/firmware behavior remain unsupported or insufficiently tested.

After testing, check UDP 45456 is released and the capture process created
by your run has exited. Do not terminate processes by name. Captures contain
network/device information and potentially audio; keep them and logs local.
