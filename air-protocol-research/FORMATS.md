# Streaming format coverage

## Separate source format from AIR wire format

MP3, WAV and FLAC describe source containers/codecs, not the AIR sample-rate
configuration. The current MP3 sender uses Media Foundation to decode/resample
everything to **48 kHz, 16-bit stereo** before encoding AIR packets. A 44.1 kHz
MP3 playing successfully therefore does not establish native 44.1 kHz AIR.

## Current evidence

| Surface | Status |
| --- | --- |
| 48 kHz stereo AIR | Live tone and music playback established |
| 44.1 kHz MP3 source | Played after conversion to 48 kHz PCM16 |
| Native 44.1 kHz AIR | Not established; header/negotiation evidence missing |
| Native 88.2/96/176.4/192 kHz AIR | Not established |
| Signed 24-bit codec sample domain | Existing seed and reconstructed sample representation |
| 24-bit lower-bit preservation | Offline codec fixtures added; no native PCM24 source-to-device validation |
| Arbitrary full-range PCM24 jumps | Encoder computes width 25; current decoder rejects it; receiver support unknown |
| FLAC/WAV source playback | Not validated in the current MP3 entry point |

The empirically scaled PCM16 music path is not proof of 24-bit source fidelity
or a calibrated unity-gain mapping.

## Offline coverage

Run `Test-FormatCoverage.ps1` using Windows PowerShell with process-only execution
policy bypass. It loads the actual encoder definition from
Test-EncoderRoundTrip.ps1 without running capture-dependent tests or playback,
and uses the existing ReferenceBlockDecoder.

Ten stereo blocks cover PCM16 shifted into a 24-bit domain and unquantized PCM24:
silence, constant signed limits, unit-step ramps (including 24-bit low bits),
different left/right sine signals, and deterministic random samples. Every
sample and re-encoded byte must agree exactly.

An additional boundary fixture alternates -8388608 and +8388607. Both values
are valid signed 24-bit samples, but zigzag deltas require 25 bits. This test
records the current explicit decoder rejection; it does NOT declare width 25
to be a valid AIR receiver configuration. Production playback needs a verified
encoding strategy for this case before arbitrary PCM24 can be advertised.

These are synthetic offline tests, not sample-rate negotiation tests or
independent evidence of receiver format support.

## Next native-rate experiment

Obtain an independently known 44.1 kHz AIR stream/header or reliable protocol
evidence identifying the format fields. Compare it to the 48 kHz baseline,
including startup, per-channel configuration, counters and feedback clock.
Devimote's status/control backend does not supply an AIR audio format selector.

Do not merely change pacing to 200/44100 seconds while replaying the 48 kHz
header: a receiver still running at 48 kHz could play at the wrong pitch and/or
underrun. Once the format is established, request approval for a short quiet
captured test and verify tone pitch, timing, progress and error feedback.

No native-rate live test, driver reconfiguration or volume change was performed
for this format-coverage work. This follow-up remains local until uploaded.

## Approved live pacing experiment, 18 October 2026

Subsequently, the user approved a live test. Send-Minimal.ps1 now accepts
SampleRate=44100/48000 for tone generation and pacing; non-48k use requires
the explicit ExperimentalRate switch. This parameter does NOT configure a
verified AIR sample-rate header.

Generation 120 preamble / 122 audio, six seconds, amplitude 10 source-style
units multiplied by 77 (very quiet), existing 48 kHz header/preamble unchanged:

- Sent 1,323 audio blocks, counters 0 through 264,400.
- Capture `air-rate44100-gen120.pcapng`: first/last audio packets at
  8.1046732 / 14.0959740 seconds; spacing agrees with 44.1 kHz pacing.
- Received 154 Df messages, zero reported missing intervals, no resends.
- Final feedback B=264,400 acknowledged the final sent block.
- During the interior audio window, Expert frame-counter slope was
  approximately 48,003.6 frames/second, while B advanced approximately
  44,094.0 frames/second (first/last feedback-point estimates).
- Port 45456 was free after completion. No volume, power, mute or input
  commands were issued by this test.

The unchanged header did NOT yield evidence of a 44.1 kHz receiver clock.
The receiver continued reporting an approximately 48 kHz clock while we fed
44.1 kHz samples. This cannot be advertised as native 44.1 kHz playback.
If played continuously at 48 kHz, a tone generated as 997 Hz at 44.1 kHz would
be about 1,085.2 Hz; actual acoustic pitch, buffering and underruns were not
measured. Acknowledgement of every block does not settle those questions.

Next: establish the actual rate-selector/negotiation fields from independent
evidence. Do not use the experimental pacing option for ordinary music.

## Official AIR reference captured during user playback

On 18 October 2026 the user started official AIR playback and approved observation.
Twenty seconds were captured in `air-official-rate-reference.pcapng`: 1,988 packets,
zero reported capture drops. Dm streaming began 12.1230822 seconds into capture;
the preceding period therefore also records the start of this observed stream.

- 1,731 Dm packets; all decode with the existing decoder and pass its CRC,
  configuration, sample-range and padding checks.
- First-to-last frame-position slope: approximately 44,102.85 frames/second.
  This supports native 44.1 kHz transmission by the official sender, unlike
  merely observing a 44.1 kHz source file.
- First 22-byte Dm header:
  `446d020000660d0000000300000000000000000000c8`.
- Generation byte 10 was 03; byte 11 was 00 for 227 observed packets, then 01
  for 1,504 packets. Our earlier 48 kHz reference used byte 11 values 02/03.
  Bit 1 of byte 11 is consequently a candidate rate-family indicator, but one
  comparison does not establish its complete meaning or other supported rates.
- Candidate session bytes also changed (660d), so not every header difference
  can be attributed to sample rate.
- A Dr input-selection command appeared at 12.0995497 seconds, with command
  bytes 6..9 `00054110`, consistent with selecting Wi-Fi input 9. Its presence
  is not evidence of a sample-rate configuration command.
- Df feedback was present from 12.1952053 through 19.9454060 seconds.

No settings or volume were changed by the capture, and official playback was
not stopped. Next step is a separately approved own-sender comparison using
the observed 00/01 header modes at 44.1 kHz, with measured feedback timing and
listening verification. Do not claim native own-sender support until tested.

## Own sender with observed 00/01 modes

The user then stopped official AIR and approved our own test. Eight seconds
of a quiet synthetic 997 Hz tone were sent at 44.1 kHz pacing, amplitude 10
times 77, generation 130 preamble / 132 audio. Only audio byte 11 was changed
to 00 for the first 227 blocks then 01. The replayed preamble still used the
old 48 kHz template; this was not a complete independent native-rate startup.

Capture: `air-own44100-modes-gen130.pcapng`. All 1,764 transmitted audio blocks
were acknowledged through final B=352,600. The sender reported 189 Df messages
and no gaps/resends; the full capture contains 204 Df packets including those
outside the socket's listening lifetime.

An offline regression of feedback frame counter F against capture time,
excluding the first 1.5 and last 0.5 seconds of audio transmission, gives:

| Capture | Interior F slope, frames/second |
| --- | ---: |
| Official 44.1 kHz reference | 44,016.1 |
| Own 44.1 kHz pacing, old 02/03 modes | 47,969.8 |
| Own 44.1 kHz pacing, observed 00/01 modes | 44,488.7 |

The mode change moved the observed F rate toward the 44.1 kHz family, supporting
a rate-related interpretation of byte 11 bit 1. The deviation from 44,100 and
short duration prevent a precision clock or native-format fidelity claim.
Acoustic pitch, actual output bit depth, buffer stability and 24-bit source
preservation remain unmeasured. Port 45456 was free after the experiment.

## Instrumented Qmusic check before long run

After user approval, Send-Mp3.ps1 was updated for selectable 44100/48000 PCM
decode and pacing, with 00/01 modes at 44100 (ExperimentalRate required).
The old 48 kHz preamble remains. The receiver thread was replaced by bounded
socket polling, source/port/generation/length/CRC checks, two-second missing-
feedback and stalled-progress guards, live progress logs and final-ack gating.
Socket disposal occurs on errors. Multi-block loss is explicitly unsupported
and aborts instead of silently pretending that B+200 alone is sufficient.
Test-SenderWatchdog.ps1 verifies timeout boundaries and feedback validation.

Generation 140/142, gain 1.4, 30-second requested Qmusic excerpt at 44100:

- PCM decode reported 50,989,296 frames at 44100 Hz (about 1156.2 seconds);
  the sender was limited to the first 30 seconds.
- At 10 seconds audio time: sent=441400, B=440400, F=395284,
  latest-feedback age about 11 ms; maximum send lateness 22.8 ms.
- The check aborted at approximately 13 seconds of audio on unsupported
  multi-block loss. No full-length run was started.
- Capture `air-qmusic44100-check140.pcapng`: first gap at 21.0416381 seconds
  capture time, B=563000, one interval [200,203] (raw 00c8..00cb).
  Following reports pinned B and decreased both interval endpoints.
- Last outgoing Dm counter was 569200 at 21.0388016 seconds.
- Socket was closed and local UDP 45456 was free after the abort.

The long-run test is blocked on recovery/timing investigation, not classified
as a pass. The interval endpoints are not assumed to be absolute frame/block
indexes. No device volume, power, mute or input changes were made.

### Bounded recovery and short retry

Outgoing counters surrounding the first gap are contiguous in the sender-side
capture, with approximately 4.5 ms spacing; no obvious pacing stall appears
there. This does not establish delivery at the Expert or explain the loss.

The sender now repairs a nonempty interval report by resending the cached
outstanding window from B+200 through the block ending at A. This deliberately
includes possible duplicates and is not an exact interval-index mapping.
The window must be aligned, already sent, fully cached and at most 32 blocks;
malformed intervals or unsupported bounds abort explicitly. Two-second
feedback/progress watchdogs still bound failed repair attempts.

Offline tests cover the observed eight-block window (563200..564600), a
single-block window, invalid alignment, unsent bounds and the 32-block limit.

The generation-144/146 retry acknowledged all 6,615 blocks of the 30-second
excerpt: final B and last sent counter both 1,322,800; 599 validated Df,
zero resends, maximum send lateness 27.6 ms. Capture/log stem:
`air-qmusic44100-repair144`. This run did not exercise live recovery and does
not establish acoustic quality.

The user-approved full mix was then started with generation 150/152,
44100 Hz, gain 1.4, capture/log stem `air-qmusic44100-long150`. Initial
feedback and B progress were verified. It aborted after approximately
70 seconds: B stayed at 3,063,600 despite two repair attempts (6 and 19
cached blocks), then the broad repair window exceeded 32 blocks.
Device volume, power, mute and input were not changed.

### Exact relative-F recovery

Follow-up comparison with controlled-drop captures supports:

`requestedCounter = F - (F % 200) + 200 * intervalIndex`

For example, F=230841 and interval [246,247] map to counters 280000 and
280200, the two known deliberately dropped blocks. F=3024078 and interval
[199,200] in the new full-run failure map to 3063800 and 3064000, rather
than the six-block broad window.

Across `air-dumpcap-drop`, `air-drop-120000`, `air-drop-pair`,
`air-drop-sep`, `air-drop-resend` and `air-drop-df`, all 22 interval reports'
first predicted counter equal B+200; 21 have a corresponding outbound packet
within 250 ms after the report. One report lacks that timed match; this is
not proof of universal behavior or acoustic recovery.

Send-Mp3.ps1 now expands exact intervals using this formula. It rejects
backward B, unordered/overlapping intervals, counters outside (B,A], unsent
or uncached counters, and requests exceeding 32 blocks. The A bound includes
the complete requested 200-frame block. Seven captured mapping fixtures,
separated intervals, malformed bounds/order and safety limits pass offline.
The broad-window implementation above is superseded.

A full retry began with generation 160/162, same rate and gain, capture/log
stem `air-qmusic44100-exact160`. Initial feedback and B progress were verified.
Exact recovery allowed progress past several loss episodes (190 resends by
75 seconds), but the run ultimately aborted on two seconds without B progress
after approximately 110 seconds of audio. Final captured B=4,695,000,
A=4,695,199; F continued advancing beyond A with zero missing intervals.
The sender continued through counter 4,839,600 before the guard fired.
Thus some loss episodes recovered, but this is not a long-run pass.

The sender subsequently added a deduplicated, ordered pending-repair queue,
discarding already acknowledged entries. Repairs are limited to one per
200-frame period rather than bursting a complete interval list in one poll.
The mapping/guard tests and C# compilation still pass. Generation 170/172
ran with that change, same rate/gain, capture/log stem
`air-qmusic44100-paced170`. It aborted on two seconds without B progress
after approximately 49.2 seconds of audio; last Dm counter=2,171,200.
Final captured A=2,035,999, B=2,034,600, F=2,142,655, no intervals.
UDP 45456 was verified free afterwards. No playback remains active.

Across the exact and paced captures, respectively 10 and 6 distinct first-
requested counters were subsequently covered by B while F was still below
that requested counter. This supports transport recovery before that F-based
deadline in those episodes; later B advances after F had passed a request
are not counted as timely recovery. It does not establish acoustic output.

The long-run task has produced failure evidence, not a successful full-mix
validation. Neither exact mapping nor resend pacing solved the final loss of
acceptance. Receiver buffering/lifecycle and wireless delivery/timing remain
unresolved; local adapter counters reported no errors/discards, which does
not prove end-to-end delivery. WLAN signal diagnostics required unavailable
Windows location/elevation permission; no settings were changed to bypass it.

A bounded follow-up with simultaneous ICMP probes (generation 180/182)
also aborted, at approximately 14 seconds of audio. Idle probes were
40/40 successful, maximum 35 ms; the concurrent diagnostic had four
consecutive 1500 ms timeouts and six successful RTTs above 200 ms
(maximum 473 ms). This demonstrates intermittent round-trip impairment,
not its location or a universal explanation for AIR failures.
See LONG-RUN.md for results and timestamp-origin limits. Cleanup and offline
sender tests were verified again. The full native-44.1k mix is not validated.

## Full wired Qmusic transport validation

After the user connected laptop Ethernet (Expert still on Wi-Fi), the
full 1156.2-second mix completed at 44100 Hz, gain 1.4, generation 200/202,
session 0x660f. All 254,947 blocks were acknowledged through final
B=50,989,200, equal to the last sent block start. One block was resent;
maximum measured send lateness was 31.9 ms. Capture independently confirms
the final B and one interval report. Offline tests and socket/capture cleanup
passed afterwards. See LONG-RUN.md for session/source-address startup findings.

This supersedes the earlier pending/failed full-track status for this wired
configuration only. It establishes transport acknowledgement through the
whole track, not acoustic fidelity, native PCM24 preservation or bit-perfect
playout. Device volume was unchanged.
