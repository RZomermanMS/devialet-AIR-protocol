# Devialet AIR protocol research and agent handoff

Research date: 17 October 2026. Target: eventual Music Assistant integration.
This folder contains experimental Windows PowerShell/C# implementations and
research notes, not a production provider or a complete protocol specification.

## Read first

1. This README is the current handoff and qualifies older conclusions.
2. [SENDER-TEST.md](./SENDER-TEST.md): synthetic tone and MP3 sender experiments.
3. [BLOCK-DECODER.md](./BLOCK-DECODER.md): channel format and encoder round-trip.
4. [STARTUP.md](./STARTUP.md): stream startup, headers, generations and preamble.
5. [DROP-TEST.md](./DROP-TEST.md): controlled packet-loss and recovery experiments.
6. [PRE-ENCODING.md](./PRE-ENCODING.md): source-to-wire processing observations.

Other documents preserve the earlier investigation. In particular REPORT.md,
PLAN.md and the initial sections of BLOCK-DECODER.md contain historical limitations
that later experiments superseded. Read dated follow-ups before treating an
earlier "unknown" as current. Conversely, successful experiments do not establish
all AIR formats or all device behavior.

## Current outcome

- The tested stereo format decodes and re-encodes byte-exactly: 7,314/7,314
  packets across the reference and selected cycle captures.
- A synthetic sender using a replayed startup preamble was accepted by the Expert.
- The MP3 sender decoded a local 44.1 kHz track to 48 kHz PCM16 stereo and
  transmitted 44,517 blocks over about 185.5 seconds.
- The generation-40 run reported 3,493 Df responses, no reported gaps, and final
  contiguous position B=8,903,200, matching its last block.
- A later generation-60 run at gain 0.6 reported 3,700 Df responses, no reported
  gaps, final B=8,903,200 and maximum send lateness 33 ms.
- The user reported that playback sounded good but quiet. The source track
  measured peak -9.0 dBFS and RMS -26.8 dBFS before sender attenuation.
- These are observed acknowledgements and subjective listening, not proof of
  bit-perfect DAC output, zero underruns, or indefinite clock stability.

No live playback was performed while preparing this handoff.

### Later Qmusic listening tests

A second local MP3 (44.1 kHz stereo, approximately 1,156.2 seconds) was decoded
and played through the standalone sender. The Expert returned progress feedback.
The user requested successive level increases from Gain=0.6 to 1.0 and then
1.4; each change restarted playback with a fresh generation (80, 90 and 100).
The relative increases are about 4.4 dB and 2.9 dB respectively. Windows and
Expert volume were not changed. These runs are not yet documented as completed
full-duration validations; do not claim final loss, playout or drift statistics.
Gain=1.4 is an experiment, not a recommended universal default.

## Tested transport and block format

Offsets are zero-based within the UDP payload; multibyte fields are big-endian.
The original test host was 172.16.5.252; the Expert was 172.16.5.90.
These are local experiment addresses, not portable configuration defaults.

| Message | Direction / purpose |
| --- | --- |
| Dm | Sender UDP 45456 to Expert UDP 45455; audio blocks |
| Df | Expert to sender UDP 45456; progress and missing-block feedback |
| Da | Expert broadcast from UDP 45454; status/discovery observations |

Dm has a 22-byte header. Byte 10 is a candidate stream generation; byte 11 is
observed as 02 then 03. The frame-position counter is BE64 at offset 12 and
frame count is BE16 at offset 20 (200 in these experiments).
Other header bytes, including candidate session fields, remain incompletely
understood; the prototype copies them from a captured packet.

Each channel:

1. Signed 24-bit starting sample, 3 bytes.
2. Configuration bytes `00 00 W W`.
3. 199 zigzag-coded deltas, W bits each, MSB-first and byte-padded with zeros.

Decode a zigzag code u using `(u >> 1) XOR -(u & 1)`.
W is the minimal bit length of the maximum zigzag delta in that channel in the
tested captures. W=0 represents a constant channel. Channels can have different
widths. The packet contains left then right channel blocks, a big-endian
CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection, xorout 0) over
everything before the CRC, then 128 zero bytes.
CRC verification was reported for 22,042/22,042 Dm payloads across nine captures.

Pacing is 200 frames every 4.1667 ms at 48 kHz. The prototype uses a Stopwatch
and busy-wait, not a production scheduler or feedback-controlled clock.
Df is observed approximately every 50 ms. Its BE64 fields are A at 10,
B at 18 and an Expert frame counter at 26. Consult Feedback.ps1 for full
validation and interval parsing; do not infer a complete resend algorithm from
the simplified sender.

## Findings that must remain qualified

- Repeated generation 6 produced no responses in one repeat; generation 16
  worked. Fresh generations 30/40/50/60 were subsequently used. This suggests
  stream-generation filtering; it does NOT establish required ordering,
  persistence, wraparound, or a universal "must increase" rule.
- The prototypes replay 38 captured preamble blocks, wait one second, then
  restart counters at zero with generation+2. They switch byte 11 to 03 at
  block 250. These are working choices, not demonstrated minimum requirements.
- Preambles are not all one fixed sequence. Three of five compared starts had
  common content after masking mutable fields; two differed substantially.
- Controlled single/separated drops and dropped resend/feedback experiments
  support receiver-driven recovery, including a repeat request about 50 ms later.
  Multi-gap interval semantics remain incomplete.
- The MP3 sender only resends B+200 on a nonzero gap count. It does not implement
  all reported intervals; no live resend happened in its clean MP3 runs.
- Gain 77.276 and per-block ramp near -0.48 describe measured driver output in
  some tone captures, not a required receiver transform or a universal amplitude
  calibration. Multitone fitting gave g=77.136 and ramp=-0.497 with lattice RMS
  0.034/0.026. Changed content and session are confounded; do not ascribe the
  difference solely to session drift.
- Synthetic playback worked without reproducing the ramp. The sender still
  applies the empirical multiplier 77.276 to PCM16 samples.
- Sender Gain=1.0 is NOT established as equivalent to the vendor driver's
  100% Windows-volume output. Nor is 1.0 a proven clipping boundary: numerical
  limits depend on PCM peak, multiplier and signed-24-bit range.
- The standalone UDP path does not use the vendor AIR audio endpoint. The
  Expert's own volume still matters. Do not generalize this into a claim about
  all Windows/network/device processing.

## Code map

| Files | Use |
| --- | --- |
| Send-Mp3.ps1 | Experimental MP3 decoder and sender |
| Send-Minimal.ps1 | Experimental quiet-tone sender |
| Decode-ReferenceBlocks.ps1 | Decoder; supports `-DefinitionsOnly` |
| Test-EncoderRoundTrip.ps1 | Byte-exact re-encoding verification |
| Common.ps1, Capture.ps1, Audio.ps1, Feedback.ps1 | Offline inspection helpers |
| Test-*.ps1 | Synthetic/capture-based checks with differing input requirements |
| Analyze-*.ps1, Compare-*.ps1, Fit-*.ps1 | Offline signal analyses |
| New-*.ps1 | Locally generated test-signal constructors |
| Play-*.ps1 | LIVE playback/capture helpers, not offline tests |
| Drop-*.ps1 | LIVE WinDivert interference experiments, not ordinary tests |

Preserve the flat layout: scripts commonly use PSScriptRoot and sibling files.

## Dependencies and reproduction limitations

Original environment: Windows PowerShell 5.1/.NET Framework, Wireshark
tshark/dumpcap in `C:\Program Files\Wireshark`, capture interface 5.
Most scripts contain original machine-specific paths and addresses.

The MP3 script loads NAudio 2.2.1 from NuGet packages extracted as:

```text
tools\naudio\naudio\lib\net472\NAudio.dll
tools\naudio\naudio.core\lib\netstandard2.0\NAudio.Core.dll
tools\naudio\naudio.winmm\lib\netstandard2.0\NAudio.WinMM.dll
tools\naudio\naudio.asio\lib\netstandard2.0\NAudio.Asio.dll
tools\naudio\naudio.midi\lib\netstandard2.0\NAudio.Midi.dll
tools\naudio\naudio.wasapi\lib\netstandard2.0\NAudio.Wasapi.dll
```

Use official NuGet packages and their license terms. The DLLs and archives are
not bundled. Media Foundation performs MP3 decode/resampling locally. No Python,
dotnet SDK, or ffmpeg was available in the original environment.

IMPORTANT: this source handoff is not independently runnable as-is.
The two sender scripts require the local `air-dumpcap-ref.pcapng` to extract
their preamble/header template. Capture-dependent tests similarly need retained
inputs that are deliberately excluded here. Do not silently fabricate missing
packets, source samples or evidence. Request controlled access to the local
evidence, or explicitly implement and test an independent startup sequence.

Original retained evidence location:

```text
C:\Users\rzome\.copilot\session-state\39c990a0-2ab4-4967-b74a-4a62955476fa\files\air-protocol-analysis
```

Example ORIGINAL-ENVIRONMENT command only, after dependencies, preamble capture,
device state and safe level have been verified and live playback approved:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Send-Mp3.ps1 `
  -Mp3 'C:\dev\Track1-converted.mp3' -Gen 70 -Gain 0.25 `
  -MaxSeconds 30 -Stem 'air-mp3-next'
```

Generation 70 is an example, not an allocated current generation. AIR streaming
must be off, and no other sender may own UDP 45456. Do not execute this command
automatically as a handoff validation step.

## Known prototype limitations to address before reuse

- Receiver thread catches all SocketExceptions as if they were timeouts.
- Receiver does not validate feedback sender, CRC or all length/count fields.
- Thread flags/counters are not consistently synchronized; cleanup on exceptions
  is incomplete.
- Resend cache is shared across startup/audio counter resets and only retains
  about 400 audio blocks. Full interval-to-frame mapping is missing.
- Arguments such as generation range, gain, duration and 24-bit sample range
  lack adequate validation.
- No feedback timeout, acceptance gate, robust end-of-stream protocol, or clock
  correction is implemented. Final sleeps do not prove complete playout.
- Audio is fully decoded to memory. Pacing busy-spins and may send catch-up
  bursts after scheduler delays (31-33 ms maximum observed in full-track runs).
- Header/session bytes, sample-rate selection and startup are capture-dependent.
- Capture shutdown forcibly stops its dumpcap PID and needs integrity checking.
- Successful transport does not establish bit-perfect amplitude or long-duration
  clock stability. Do not present these scripts as production-ready.

## Safety and evidence handling

- Never change Windows, AIR or Expert volume automatically.
- Obtain explicit permission before live sender, capture, driver-control or
  packet-drop experiments. Begin with conservatively attenuated test audio.
- WinDivert experiments require elevation/UAC and can wedge a stream. Do not
  start them simply to read or validate this folder.
- No packet captures, MP3/WAV audio, decoded-sample CSVs, local logs, ETL files,
  DLLs or downloaded third-party packages are included in this handoff.
- Raw captures include private network/device information and potentially audio.
  Keep them local unless separate permission and rights allow disclosure.
- Script/document contents preserve original experiment addresses and local
  paths for provenance; review them before publishing publicly.
- No new license is asserted for this collection; follow repository ownership
  and licensing decisions rather than inferring a license from this README.

## Recommended continuation

1. Parameterize endpoints/interface and validate arguments/sample bounds.
2. Extract the shared codec rather than maintaining three copied encoders.
3. Use the validated feedback parser; implement full interval recovery and test
   it offline before another approved live-loss test.
4. Make lifecycle/cleanup reliable and detect absent or stalled feedback.
5. Establish generation selection/wraparound and test preamble requirements.
6. Measure actual amplitude, playout latency and clock drift independently.
7. Build a streaming, platform-appropriate Music Assistant provider only after
   those transport/lifecycle requirements are established.

SHA256SUMS.csv records the packaged file hashes for transfer verification.
