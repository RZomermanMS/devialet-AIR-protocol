# Qmusic long-run follow-up

## Latest readiness assessment (2026-10-18)

This section supersedes the older outstanding-work lists below. The user
subsequently authorized continued live testing. All recordings/audio remain
local; no automatic volume, power, mute or input changes were made.

### Full Qmusic transport and bounded recovery

`air-readiness-cache400-full` completed the approximately 19-minute mix at
44100 Hz, gain 1.4, generated startup and session 0xb68f. The laptop was on
Ethernet; the Expert remained on its Wi-Fi input. The sender decoded
50989296 frames and sent 254947 unique audio blocks with 8064 retransmissions.
Final B=50989200 and sender final F=50990729 exceeded padded end 50989400.

Independent complete-capture validation checked every matching Dm:
254947 decoded/CRC-valid unique audio blocks, 8064 byte-identical resends,
38 startup blocks, 22832 matching captured audio Df, 995 interval reports,
104 final zero-padding frames and captured final F=51017189.
The capture validator streams tshark output rather than loading the entire
capture into memory.

The preceding run failed on an arbitrary 32-block recovery limit even though
the requested blocks were valid and still cached. The limit now shares the
actual 400-packet resend-cache constant; bounds, ordering, cache presence,
already-sent checks, deduplication and paced retransmission remain.
Tests accept 400 requested blocks and reject 401. A 40-block burst-loss
integration case exercises the previously rejected recovery path.

Concurrent 1200 ping probes recorded 1165 successes and 35 timeouts.
Successful RTT averaged 99.14 ms, maximum 886 ms; 169 successes exceeded
200 ms. Sender maximum native read was 442.1 ms and maximum lateness 437.7 ms.
This is successful acknowledged transport despite impairment, NOT a claim of
uninterrupted sound or an established diagnosis of every resend.

### Decoder EOF defect found and corrected

The first full 48000 Hz Track1 test (startup/audio generation 253/255,
session 0xb33d) acknowledged 44516 blocks with 3209 resends, but decoded only
8903200 frames instead of the baseline 8903209. Capture validation correctly
validated the transmitted stream; it did not establish source completeness.
Direct native resampler reads of 800 bytes reproduced the nine missing frames.

PcmBlockReader now stages native reads in 65536 bytes, then slices into
800-byte/200-frame packet blocks. Application PCM staging is fixed at 66336
bytes, not whole-track buffering; decoder internals and encoded resend cache
are additional. Short reads, exact duration budgets, EOF padding, explicit
decoder errors and cancellation polling remain covered.

All 48 synthetic reader cases pass. Complete PCM SHA256 and frame counts
match the 65536-byte native-read baseline for both sources at both rates:

| Source | Rate | Frames | SHA256 |
|---|---:|---:|---|
| Track1 | 44100 | 8179824 | 56332EB5DF8D4329713FCE8F1674E01C7EAC5052CE0C647C9A9C2F3E69508BC3 |
| Track1 | 48000 | 8903209 | 28A02296F20EC42D2BE0B41C851326C83E3A88B6F82D31BAC637090017D9C605 |
| Qmusic | 44100 | 50989296 | 86AB7F806DB2D5C0482B284A9AD57BAAEC39ECD97C01CFBB59F609EDB784A535 |
| Qmusic | 48000 | 55498553 | D9AB2DD4BA13E258C6CBD7A893D395ABA4C01250FB713B4C44B0FC7C4523590F |

Final-code live result `air-readiness-final48000-retry`, session 0x9f5d,
default generation 30/32: 8903209 decoded frames, 44517 unique audio blocks,
12 resends, final B=8903200, sender F=8904823, padded end 8903400,
maximum native read 21.4 ms, maximum lateness 20.4 ms.
Independent full-capture validation passed: 38 startup blocks, all 44517
audio blocks decoded/CRC-checked, 12 byte-identical resends, 3710 captured
audio Df, 17 interval reports, 191 zero-padding frames and final F=8936023.
This confirms transmission of the restored partial tail and end drain.

### Failures retained, not counted as successful runs

After the staging change, `air-readiness-final44100` failed the two-second
B-progress watchdog after about 64 seconds of source transmission.
Captured last audio counter was 2826400; final feedback froze at
A=2693799/B=2693200 while F advanced to 2813351 with no missing intervals.
The Expert continued feedback; this was not a successful full Qmusic rerun.
Ten subsequent pings succeeded at 2-30 ms; those probes do not establish
conditions during the stall or its cause.

The first final-code 48000 Hz attempt, `air-readiness-final48000`, also
failed the progress watchdog after about 85 seconds. The bounded fresh-session
retry above completed. These failures remain unresolved reliability evidence:
do not attribute them solely to Wi-Fi, decoder staging, generation or a
particular clock without additional evidence. Do not disable the watchdog,
invent missing intervals or report acoustic completion.
The successful 19-minute Qmusic run preceded the decoder staging fix;
the complete final-code Qmusic PCM hash passes offline, but a final-code
19-minute physical run has NOT passed.

Generation-zero startup also failed after the 253/255 test, even with a fresh
session: only A=199/B=0/F=0 was acknowledged. Normal fresh-session 30/32 works
in tested starts; general generation-wrap/session-expiry behavior is unknown.

### Final regressions and implementation decision

On the final staged decoder:

- 18 actual-sender loopback integration cases pass across 44100/48000:
  clean, adjacent/separated loss, lost resend, 40-block burst, absent feedback,
  stalled B, foreign session and corrupt feedback.
- Watchdog, generated startup, session/CRC/bounds, 400/401 recovery boundary,
  cancellation cleanup and missing-readiness tests pass.
- Feedback parser 30/30, discovery 22/22, and ten exact codec fixtures
  preserving 4000 channel samples pass. Width-25 remains unvalidated.
- Live stop prevented the next playlist track and released the socket;
  a fresh 44100 Hz six-second session acknowledged all 1323 blocks and drain.

Decision: enough wire-protocol evidence to START a constrained Music Assistant
provider/shared user-mode transport implementation, not enough to call the
sender production-reliable or fully reverse-engineered. Known outage/restart
and pacing/buffer behavior need an explicit integration recovery policy and
further instrumented tests. Acoustic fidelity has not been measured.
Do not spend more blind full-track repetitions instead of implementing those
observable lifecycle/recovery surfaces.

Windows ARM64 transport is a separate portable implementation/build test;
a system-wide virtual audio endpoint additionally requires WDK driver work,
signing and physical ARM64 validation. No ARM64 driver is built or verified.
See [SENDER-TEST.md](./SENDER-TEST.md) for the supported contract, integration
architecture, exclusions and official platform references.

## Historical investigation

Offline inspection of `air-qmusic-gen100.pcapng` after generation-100 playback
completed. No playback, volume change or network experiment was started.

## Verified observations

- The sender exited with code 0 after 277,493 blocks, approximately 1,156.2
  seconds of source audio. Its final log reports 5,608 Df messages, zero reported
  gaps/resends and maximum send lateness 65 ms.
- The capture contains exactly 5,608 Df packets, matching the receiver log.
- First Df was captured at 1.8453517 seconds.
- Last change in contiguous position B was at 298.5024001 seconds,
  ending at B=13,894,600 (about 289.47 seconds of source frames).
- Last Df was at 301.2995646 seconds. Its B remained 13,894,600.
- Outbound Dm remained visible through 1,159.1665418 seconds, ending at
  counter 55,498,400, matching the sender's final counter.
- After 302 seconds, the capture still contains 4,165 Expert status broadcasts
  from UDP 45454, but no more Df packets.
- Music-sized variable Dm packets are present after the feedback failure,
  including around 600 and 1,100 seconds. The final constant/zero block alone
  does not establish a premature end of decoded audio.

## Interpretation and limits

This is not a successful acknowledged full-track validation. The sender kept
transmitting for approximately fourteen minutes after captured feedback ended.
Its receiver log and capture agree, making a receive-thread-only problem
insufficient to explain the missing feedback. Continued status broadcasts show
the Expert remained visible on the network; they do not prove the streaming
session remained healthy.

Zero reported missing intervals does not establish zero packet loss or zero
underruns, especially after feedback ceases. Packet capture itself can miss
traffic; the evidence does not prove a particular receiver failure or timeout.
Clock drift, insufficient buffering, stream lifecycle, network disruption and
receiver rejection remain possible explanations, not established causes.

## Required follow-up

1. Add explicit feedback/progress timestamps and detect both absent feedback
   and a stalled B while audio counters advance.
2. Fail visibly and clean up rather than reporting success after an unacknowledged
   stream. Account for startup, counter/generation resets and playout drain.
3. Inspect timing/buffer evolution around 285-302 seconds before attributing a
   cause; compare status changes and capture-drop evidence where available.
4. Validate corrected behavior offline, then request approval for another
   instrumented live run. Do not replay automatically.

The research repository's earlier handoff was uploaded before this completion
result became available. This follow-up is currently retained locally.

## Instrumented 44.1 kHz follow-up (2026-10-18)

The user approved a short Qmusic check followed by the full mix. The sender
now validates feedback endpoints, generation, length/count and CRC; checks for
two seconds without feedback or B progress; and requires acknowledgement
through the final sent block before reporting transport completion.

The first short check (generation 140/142) aborted on an unsupported
multi-block gap after about 13 seconds of audio. Sender-side counters around
the gap were contiguous and regularly spaced. A bounded cached-window resend
path was added and tested offline; it does not claim an exact interpretation
of interval indexes. See FORMATS.md for its limits.

The second short check (144/146) acknowledged all 6,615 blocks through
B=1,322,800 with no resends. Consequently the live recovery path remains
unverified by that successful short run.

The full 1,156.2-second mix was started as generation 150/152 at 44100 Hz,
sender gain 1.4. Initial feedback and acknowledgement progress were verified.
Capture and progress log: `air-qmusic44100-long150.pcapng` and
`air-qmusic44100-long150.log`. No device-volume change was made.
It aborted after approximately 70 seconds: B=3,063,600 remained pinned
through two broad-window repairs, then the recovery window exceeded its
32-block safety limit. Local UDP port 45456 was verified free afterwards.

Cross-checking six official controlled-loss captures identified an exact
relative-F interval mapping, documented in FORMATS.md. The broad-window
path was replaced with exact counters and offline fixture/guard tests passed.
A new full run, generation 160/162, has started with the same rate/gain.
Capture/log stem: `air-qmusic44100-exact160`. Initial B progress is verified.
That run recovered several loss episodes but stopped on the progress watchdog
after approximately 110 seconds. Final captured B=4,695,000 and A=4,695,199
were pinned while F kept advancing and later exceeded A; final feedback had
no missing intervals. Last transmitted counter was 4,839,600.

The repair path was then changed to an ordered, deduplicated queue with at
most one resend per 200-frame period, rather than burst-sending all requested
blocks in a feedback callback. Already acknowledged queued blocks are removed.
Compilation and mapping/guard tests passed again.

Generation 170/172 ran with paced repairs at the same rate/gain.
Capture/log stem: `air-qmusic44100-paced170`. It aborted on the progress
watchdog after approximately 49.2 seconds of audio, last sent=2,171,200.
Final captured A=2,035,999, B=2,034,600, F=2,142,655, no intervals.
UDP 45456 was verified free; no playback remains active.

Offline capture checks found 10 distinct first-requested counters in the exact
run and 6 in the paced run subsequently covered by B while F was still below
the requested counter. This distinguishes some timely acknowledgement
recovery from advances occurring only after F passed missing data. It does
not establish acoustic fidelity.

Result: the 30-second transport check passed, but sustained full-mix playback
remains unvalidated. Exact recovery, pacing and watchdogs are implemented;
the final receiver acceptance/progress failure remains unresolved. Local
adapter error/discard counters were zero, not proof of wireless delivery.
No further automatic replay is scheduled.

## Idle versus concurrent streaming latency

A subsequent bounded diagnostic compared round-trip latency to 192.0.2.20
without playback and during another approved-source playback attempt.
It did not change Windows networking, device configuration or volume.

- Idle: 40/40 successful ICMP probes, 3..35 ms, mean 11.2 ms.
- Concurrent with generation 180/182 playback: 376/380 successful probes,
  successful RTT 2..473 ms, mean 19.08 ms; six successful probes exceeded
  200 ms and four consecutive probes timed out (1500 ms timeout each).
- Concurrent probe results are persisted in
  `air-qmusic44100-probe180-latency.csv`, with times relative to the probe
  loop start. That origin differs from capture time and audio elapsed time;
  do not directly compare their numeric timestamps.
- The requested 180-second excerpt aborted on the two-second progress
  watchdog after approximately 14 seconds of audio. Last Dm counter=620200;
  final captured A=491599, B=484000, F=600983.
- Capture/log stem: `air-qmusic44100-probe180`.
- Sender compilation, mapping and watchdog tests passed afterwards.
  No UDP 45456 sender socket or dumpcap process remained.

This establishes intermittent round-trip delay/loss during the diagnostic,
independent of interpreting AIR feedback. It does not isolate the PC Wi-Fi,
access point, Expert Wi-Fi/firmware or ICMP handling, nor prove all earlier
stalls share one cause. The stable idle measurement does not establish stable
connectivity under audio load. The roughly one-second F-to-send margin is
insufficient against sustained multi-second outages; increasing a watchdog
would not recover audio whose receiver deadline has passed.

The requested long-run experiment has therefore produced a failed sustained-
playback result, not a full-track success. Further reliable-playback work
requires isolating the loaded network/receiver path (for example a controlled
closer-AP or wired comparison), rather than repeated unchanged replay or
loosening success criteria. No additional replay is scheduled.

## Ethernet comparison after user connected laptop

Ethernet 2 is up at 1 Gbps, Wi-Fi disconnected; the route to the Expert uses
192.0.2.11 on Ethernet, capture interface 10. The Expert remains on Wi-Fi.
The initial wired run (190/192) reused template session 0x4977 and received
no Df, even in the Ethernet capture, aborting at two seconds. Status broadcasts
and outgoing Dm were captured. Concurrent probes succeeded 120/120, mean
7.85 ms, maximum 325 ms; only part of that minute overlapped audio.

Send-Mp3.ps1 now accepts optional SessionId (1..65535 overrides bytes 5..6;
0 preserves the template), applied to every preamble and subsequent audio
header with CRC recomputation by the existing sender. A short wired retry
(194/196, session 0x660e) acknowledged all 6615 blocks through B=1322800,
592 valid Df, two resends, maximum send lateness 19.4 ms. This supports but
does not prove session/source-address association as the initial wired issue.

The full mix is running as generation 200/202, session 0x660f, same 44100 Hz
and gain 1.4, capture/log stem `air-qmusic44100-wired200`. Initial feedback
and B progression were verified. Device volume/power/mute/input unchanged.
Full completion remains pending.

### Full wired result: acknowledged through end of track

Generation 200/202, session 0x660f completed with exit code 0:

- Source: 50,989,296 PCM frames at 44100 Hz (about 19m16s), gain 1.4.
- Sent 254,947 blocks, final partial source block padded to 200 frames.
- Final B=50,989,200 equals last sent block counter=50,989,200.
- Sender validated 23,082 Df; maximum measured send lateness 31.9 ms.
- One requested block was resent; subsequent progress continued to the end.
- Independent capture check: 23,095 audio-generation Df including packets
  outside the sender listening lifetime, one interval report, final
  B=50,989,200. Final captured F=51,002,274.
- Sender compilation and offline watchdog/mapping tests passed afterwards.
- UDP 45456 and dumpcap cleanup verified; no playback remains running.
- No Expert volume, power, mute or input changes were made.

This is a successful full-track transport acknowledgement test on laptop
Ethernet with the Expert on Wi-Fi. It does not establish bit-perfect audio,
pitch, output depth, or absence of audible glitches. Compared with the earlier
laptop-Wi-Fi failures it supports the wired route as a practical improvement,
but the changed session identifier and sequential trials prevent attribution
solely to the physical link. Historical failure results above remain valid.

## Incremental decoding validation

Historical first implementation: the 800-byte-only application staging below
was later superseded by the 66336-byte model in the latest assessment above.
Qmusic matched at both rates, but the later Track1 48000 Hz test exposed
source-dependent tail truncation and required the decoder staging fix.

The subsequent sender update removes whole-track MemoryStream/byte-array
decoding. Its PCM staging buffer is fixed at 800 bytes (200 stereo PCM16
frames); the 400-encoded-packet resend cache remains separately bounded.
Native decoder reads are synchronous; this does not bound internal Media
Foundation buffers or provide HTTP/live-radio input. See SENDER-TEST.md.

Complete offline Qmusic PCM comparison against the previous 65536-byte
decoder read pattern:

| Rate | Frames | Matching SHA-256 |
| --- | ---: | --- |
| 44100 | 50,989,296 | 86AB7F806DB2D5C0482B284A9AD57BAAEC39ECD97C01CFBB59F609EDB784A535 |
| 48000 | 55,498,553 | D9AB2DD4BA13E258C6CBD7A893D395ABA4C01250FB713B4C44B0FC7C4523590F |

Live Qmusic twelve-second caps at both rates were acknowledged with exactly
the requested frames (529200 and 576000), no resends. Stop-file cancellation,
suppression of the next playlist track and fresh-session reconnect passed.

Live natural-EOF test: `air-incremental-full-track1`, session 0xf98b,
generated startup, generation 30/32, 44100 Hz, gain 1.4:

- 8,179,824 source frames; 40,900 blocks over approximately 185.5 seconds.
- Final B=8,179,800 equals last sent; sender final F=8,182,014 exceeds
  padded track end=8,180,000.
- 3,728 validated Df, zero resends, maxReadMs=27.9 and maxLateMs=30.4.
- Independent capture: exactly 40,900 audio-generation Dm; final captured
  B=8,179,800 and F=8,208,474. Final packet passes independent CRC/decoder
  validation and its last 176 frames are zero-padding.
- No active sender socket or dumpcap remained. Volume/power/mute/input
  unchanged. This is not an acoustic fidelity claim.

The 19-minute Qmusic mix has been decoded completely for equivalence, but
not replayed completely with the incremental delivery implementation.
The earlier full 19-minute transport pass above remains a result for its
prior whole-track decode/captured-startup configuration.

A final consecutive-track test initially stopped before track two because no
Expert was discovered. Follow-up probes also timed out, then connectivity
and fresh Wi-Fi-input status recovered without network/device changes.
The repeated test (`air-incremental-playlist-recheck.log`) acknowledged both
three-second excerpts: each 132300 decoded frames, 662 padded blocks,
B=132200, F past 132400, no resends. Cleanup verified no sender/capture
remained. This preserves fail-closed readiness behavior; it does not resolve
the intermittent Expert/network unreachability.
