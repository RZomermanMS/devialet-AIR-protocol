# Minimal sender test (Send-Minimal.ps1)

## Current MP3 lifecycle usage (2026-10-18)

The older tone/MP3 observations below predate the generated startup and
automatic sessions now used by Send-Mp3.ps1. See [STARTUP.md](./STARTUP.md)
for validation and limits, and [LONG-RUN.md](./LONG-RUN.md) for the earlier
full-track transport test using captured startup.

Send-Mp3.ps1 defaults to generated silence startup and an automatically
selected nonzero session ID; no manual Gen or SessionId is needed.
Startup=Captured explicitly retains the reference-pcap path for diagnostics.
All audio remains PCM16 decode with the previously empirical wire scaling.

Example, from a PowerShell process launched with execution-policy bypass:

```powershell
& .\Send-Playlist.ps1 -Mp3 @('C:\dev\Track1-converted.mp3',
  'C:\Dev\Qmusic Top40-Q3-2026 Mix by Eddeped (Wav_MP3)\Qmusic Top40-Q3-2026 Mix by Eddeped.mp3') `
  -CaptureInterface 10 -ExpertAddress 192.0.2.20 -NetworkInputIndex 9 `
  -SampleRate 44100 -ExperimentalRate -Gain 1.4 -StopFile 'C:\dev\air-stop.signal'
```

Interface 10 is this laptop's current Ethernet capture interface; enumerate
dumpcap interfaces on other machines. The input must already be selected;
these senders do not switch it or change device volume/power/mute.
Playlist paths are validated before playback. Each track uses a fresh process,
discovery/preflight and session; any failure prevents later tracks starting.
MaxSeconds limits each track for testing, not the whole playlist.

Creating the supplied stop file requests cancellation during decode/startup/
playback/drain. Cancellation is reported as a nonzero exit, not successful
completion. The caller must explicitly remove that file before restarting.
Pending receiver audio may finish; this is not an immediate mute or flush.
Do not forcibly kill the parent process as the normal stop mechanism.
Decoding is now incremental; transitions are still not gapless.

Test-SenderWatchdog.ps1 covers codec startup, feedback/session guards,
watchdogs, recovery mapping, cancellation cleanup and readiness timeout
without live audio. Test-Lifecycle.ps1 is an explicitly live test that
plays an excerpt, cancels a two-track playlist, checks track two never starts,
and reconnects for a second excerpt. It requires an already ready network input.
Generated startup plus incremental decoding completed the full 185.5-second
Track1 through natural EOF; see the results below. The earlier 19-minute
Qmusic transport run used captured startup and whole-track decoding.

### Incremental PCM delivery

The sender binds a native ReadPcm delegate to the existing NAudio resampler
and uses a fixed 65536-byte decoder staging buffer plus an 800-byte packet
buffer. Network packets contain at most 200 source stereo PCM16 frames,
padded to 200 on the wire. It sends the
first block after startup readiness instead of decoding the whole track first.
Subsequent blocks are decoded just ahead of their scheduled send time.
No source Length/Position, seeking or total-frame count is used by the PCM
consumer. Its counters are 64-bit. Resampling, wire scaling and packet
encoding are unchanged.

Short reads are accumulated, zero-byte Read means EOF, and the final partial
200-frame block is zero-padded. A partial stereo frame is an explicit error.
MaxSeconds is enforced at the decoder read boundary: bytes beyond the frame
budget are not requested. Feedback and stop polling run before/after each
native read. Decoder exceptions propagate and prevent later playlist tracks
starting; decoder/resampler/capture/socket resources are disposed on failure.

The application PCM staging buffers total 66336 bytes, independent of
source duration, rather than approximately 204 MB for Qmusic at 44100 Hz
(plus the previous MemoryStream/copy overhead). This is not a bound on total
process memory: NAudio/Media Foundation maintain their own decoder buffers,
and the sender retains up to 400 encoded packets for retransmissions.
No unbounded PCM queue or background decode thread is introduced. The fixed
decoder read size preserves the previous Media Foundation resampler EOF
behavior: direct 800-byte native reads omitted nine tail frames for Track1
at 48000 Hz. The staging fix restores all 8903209 frames and the baseline
PCM hash; both tracks match their baseline at both rates. The packet buffer
remains 800 bytes; log field pcmStagingBytes reports total application PCM
staging rather than just the packet buffer.

Native reads are synchronous. A blocked native decoder call can delay
feedback/stop handling until it returns; maxReadMs is logged for diagnosis.
This local-file implementation does not yet accept radio URLs, Music
Assistant HTTP streams, or guarantee cancellation of hung network reads.
An unknown-length callback is supported/tested by the PCM consumer, but
that alone does not establish an end-to-end live-radio source.

Test-PcmStreaming.ps1 runs 48 deterministic short-read/EOF/padding fixtures,
long/unknown-length input, exact frame-budget/no-overread, invalid byte
counts, decoder exceptions and cancellation. With -Mp3 it compares complete
incremental decoded PCM SHA-256 against the previous 65536-byte read pattern
at both rates, without buffering either whole decode in memory.

Validation on this laptop's Ethernet with Expert Wi-Fi, gain 1.4:

- Entire Qmusic decode is byte-exact against large-read baseline at both rates:
  50,989,296 frames at 44100 Hz and 55,498,553 at 48000 Hz.
- Twelve-second live checks: exactly 529200 frames/2646 blocks at 44100 Hz,
  and 576000 frames/2880 blocks at 48000 Hz; both final counters acknowledged,
  F reached padded end, no resends.
- Live playlist cancellation still suppressed track two and released the
  socket; fresh automatic session reconnected and played another excerpt.
- A consecutive-track recheck completed two three-second excerpts, each
  132300 frames/662 padded blocks, final B=132200 and F past padded end.
  An earlier attempt correctly stopped before track two when discovery
  observed no Expert; simultaneous ping probes confirmed temporary
  unreachability. The Expert became reachable again without configuration
  changes, and fresh passive status was verified before the successful retry.
- Full Track1 at 44100 Hz: 8,179,824 frames, 40,900 blocks, final B=8,179,800,
  zero resends, maxReadMs=27.9, maxLateMs=30.4. Normal EOF, not MaxSeconds.
  Capture independently confirms 40,900 audio packets, final B/F and all
  176 padded frames zero; the independent decoder validates final packet CRC.
  This was the earlier direct-800-byte decode implementation at 44100 Hz.
- No volume/power/mute/input changes were made. Playback and capture stopped.

These are transport and decoded-PCM equivalence checks, not acoustic or
bit-perfect output validation.

### Protocol fault-injection validation

Test-SenderIntegration.ps1 runs the actual embedded Snd2 sender against a
loopback-only mock Expert. It checks every received audio packet with the
independent ReferenceBlockDecoder, including CRC, expected stereo PCM
values, retransmitted contents and final zero-padding. It does not transmit
test faults to the physical Expert.

Nine scenarios at each of 44100/48000 Hz (18 cases) cover clean EOF,
adjacent losses, separated losses, a lost resend, a deliberate 40-block burst,
absent feedback, feedback with stalled B, a wrong session with correct CRC,
and corrupt feedback. Fault cases must fail visibly within a bounded time
and release their socket; successful loss cases must acknowledge the end.
This complements, not replaces, captured official-sender evidence and live
receiver tests: the mock implements our current protocol interpretation.

The live readiness run initially found a request above the old arbitrary
32-block repair cutoff. That limit is now tied to the actual 400-block
resend cache, using one shared constant. Bounds, order, already-sent and
cache-presence checks remain; retransmissions remain paced. Offline tests
cover an accepted 400-block request, rejected 401-block request, and
end-to-end 40-block burst recovery. This does not guarantee recovery from
every 400-block outage; receiver deadlines and cache age still apply.

Run Test-SenderIntegration.ps1 and Test-SenderWatchdog.ps1 sequentially:
they use the same fixed loopback sender port. They can run alongside
physical playback bound specifically to a different local interface address.

Test-SenderCapture.ps1 independently decodes/CRC-checks every matching Dm
from a completed generated-startup capture, verifies contiguous unique
counters and byte-identical resends within cache, checks mode transitions,
final padding and final B/F. It also validates matching Df CRC/length/count.
Pass CapturePath, ExpectedFrames, SessionId, SourceAddress, ExpertAddress
and the appropriate SampleRate/Gen. Captured-startup recordings are not its
target: it expects 38 generated startup packets in the selected rate mode.
It has verified all 40,900 packets of the Track1 recording, not only its tail.

### Integration readiness: supported contract and non-goals

The target is enough evidence to start a constrained integration, not a
complete specification of every AIR feature or production-driver approval.
The final-code 48000 Hz full Track1 capture passed with all 8903209 source
frames, 44517 unique blocks, 12 identical resends and 191 zero-padding frames.
Final-code stop/reconnect and all 18 loopback fault cases passed.
Two final-code live attempts also hit the progress watchdog, including the
44100 Hz Qmusic rerun. The successful 19-minute Qmusic run predates the
staging fix; no final-code whole-Qmusic live success is claimed.
See [LONG-RUN.md](./LONG-RUN.md) for exact successes, failures and hashes.

The implementation contract established so far:

- One selected Expert, IPv4 unicast Dm/Df and broadcast Da discovery.
- Exclusive local UDP source 45456, Dm destination 45455; matching Df source
  45456. Session/gen/source/CRC guards and fresh-status readiness.
- Generated 38-block silence startup; distinct automatic nonzero session,
  default generation 30/32, 200-frame packets and observed 44100/48000 modes.
- PCM16 stereo input scaled to signed-24-bit numerical wire values using
  the empirical factor; no claim of native PCM24 or calibrated full scale.
  Gain 1.4 is the live-test setting, not a general volume calibration.
- B/A/F and relative-F missing intervals, bounded 400-packet resend cache,
  paced retransmissions, explicit feedback/progress deadlines and end drain.
- Explicit stop ceases transmission, with possible remaining receiver audio;
  no remote flush, gapless/pause/seek or sample-synchronous grouping promised.
- Source errors, missed readiness and prolonged outages are visible failures,
  not success-shaped fallback. Reconnection uses fresh sessions.

Music Assistant: use this as the basis for a player provider and a portable
transport library, rather than porting the Windows MP3/PowerShell wrapper
unchanged. The initial integration should offer one player, 44100/48000
stereo PCM input, discovery/status, play/stop and explicit input selection.
Do not advertise native 24-bit/high-rate, immediate flush, sync groups,
gapless, native pause/seek or automatic volume/power control. Map user stop
to expected cancellation, not a false playback-completion event.

Remaining implementation work is an async cancellable PCM source feeding a
timed transport worker, direct socket discovery without Npcap/tshark,
structured lifecycle/error/status events, backpressure, source/network timeout
handling and Music Assistant API/configuration/packaging. Existing local-file
NAudio reads cannot guarantee cancellation while native Read is blocked.
A Linux/ARM port and actual Music Assistant runtime test have not been run.
Use a pinned Music Assistant target version; public main is a moving API.

Windows ARM64: the wire protocol can also underpin a user-mode native sender
or service. A system-wide AIR audio endpoint is additional driver work,
not another protocol inference: implement/cross-compile a virtual endpoint
and its PCM handoff, keep networking/codec/session management in a user-mode
service where possible, and test on physical Windows ARM64 hardware.
WDK/SDK builds, endpoint format negotiation, clock/latency/underruns,
install/uninstall, suspend/resume, device recovery, signing and the applicable
driver validation/submission requirements remain. No ARM64 binary, signed
driver or actual ARM deployment is claimed by these sender tests.

Public implementation references consulted (2026-10-18; no upstream
implementation copied):

- [Music Assistant PlayerProvider](https://github.com/music-assistant/server/blob/main/music_assistant/models/player_provider.py)
  and [Player](https://github.com/music-assistant/server/blob/main/music_assistant/models/player.py)
  define separate provider discovery/ownership and player behavior.
- [Building ARM64 drivers with the WDK](https://learn.microsoft.com/en-us/windows-hardware/drivers/develop/building-arm64-drivers)
- [Universal audio drivers / SysVAD starting point](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/audio-universal-drivers)
- [Driver code-signing requirements](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-reqs)

Outstanding protocol coverage, not first-provider blockers: cold power-cycle
startup, session collision/expiry and generation wrap rules, other Expert
models/firmware, 25-bit delta/full-range PCM24, higher rates, exact DAC timing,
calibrated gain, remote flush and multiroom synchronization.
Generation-zero startup failed readiness in a live test (only B=0 was
acknowledged); a 253/255 stream completed. Do not infer modulo-wrap behavior
or use zero generation as a normal integration default.

Sender binds UDP 192.0.2.10:45456 (AIR streaming off), replays the 38-block captured preamble (byte 10 = generation, CRCs recomputed), waits 1 s, then streams a quiet 997 Hz tone (amplitude 30 LSB x 77, both channels) from counter 0 with byte 10 = generation+2, byte 11 = 02 (03 from block 250), 200 frames every 4.1667 ms, resending B+200 when a Df reports a gap.

Results
- Run 1 (generation 6, identical to the reference capture): Df replies appeared only after audio began; A tracked our counter, no gaps.
- Run 2 (generation 6 again): zero Df replies. The Expert ignored the repeated generation.
- Run 3 (generation 16): Df heartbeat started at the first preamble block (A=199, B=0). Over 1920 audio blocks (8 s): A/B tracked our counters to 383999/383800, Df frame counter F advanced at ~48 kHz, 0 gaps, 0 resends.

Conclusions
- The Expert accepts a fully synthetic stream: our encoder, our CRC, a replayed preamble and our own pacing.
- Byte 10 (generation) must differ from the previous stream's, so it needs to increase per stream.
- No dependence on the lattice (g, ramp) was needed.
- Open: audibility/quality not verified from the PC side; other generations, shorter or no preamble, other levels and sample rates untested.

## MP3 sender (Send-Mp3.ps1)

Decodes C:\dev\Track1-converted.mp3 (44.1 kHz) to 48 kHz 16-bit stereo through Media Foundation (NAudio 2.2.1 in tools\naudio), scales by Gain (default 0.25, wire value = sample x gain x 77.276), then uses the same preamble/encoder/pacing/resend logic as Send-Minimal.ps1. Needs AIR streaming off and a generation id different from the last stream (-Gen).

- 30 s run (Gen 30): 7200 blocks, 0 gaps, 0 resends.
- Full track (Gen 40): 185.5 s, 44517 blocks, 3493 Df, 0 gaps, 0 resends, max send lateness 31 ms, final B = last block sent. Expert frame counter tracked ours over the full 3 minutes (no clock-drift problem seen).
- Captures: air-mp3.pcapng, air-mp3-full.pcapng.
