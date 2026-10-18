# AIR start-up sequence (from `air-dumpcap-ref.pcapng`, one capture, one session pair)

## Current sender: generated startup and automatic sessions (2026-10-18)

The historical capture observations below remain useful, but Send-Mp3.ps1
no longer requires the captured preamble by default. It constructs 38 valid
200-frame stereo-silence Dm packets from scratch, with its own header,
session, generation, counters and CRC. At 44100 Hz it uses mode 00; at
48000 Hz mode 02. This is an empirically working startup sequence, not proof
that 38 packets or a preamble are required.

SessionId=0 now selects a random nonzero 16-bit session for each invocation;
an explicit nonzero SessionId still permits reproducible experiments.
Generation defaults to 30/32 within each fresh session. Successful repeated
starts with that same generation but different sessions show that manual
monotonically increasing generations are not needed in this tested workflow.
Random selection does not guarantee collision freedom or define device
session-expiry semantics.

Before sending music, the sender requires a valid startup Df from the selected
Expert address/port, matching session and generation, acknowledging the final
startup counter with no intervals. It fails within two seconds if not ready.
Audio feedback now also checks session, not just generation and CRC.
Startup=Captured remains an explicit legacy diagnostic option; it is not an
automatic fallback. Generated startup does not read a reference pcap.
Discovery and diagnostic recording still depend on Wireshark tools.

Live wired-laptop/Expert-Wi-Fi validation:

- Initial generated-startup 44100 Hz excerpt: 1764 blocks acknowledged.
- Two sequential six-second tracks at 44100 Hz: each 1323 blocks, final
  B=264400; automatic sessions 0x2721 and 0x47c8, no resends.
- Stop-file cancellation after five seconds prevented the playlist's second
  track, exited visibly nonzero and released UDP 45456.
- A fresh automatic session (0xd88a) then reconnected and acknowledged
  another six-second excerpt.
- A 48000 Hz six-second excerpt acknowledged 1440 blocks through B=287800.

Normal completion waits for final B and then for F to pass the padded track
end before closing; F is a transport/reference counter, not acoustic proof.
Stop means cease sending and close the socket, not a demonstrated remote
flush command: already queued audio may finish. Separate playlist sessions
have discovery/decode/startup gaps; gapless transitions, pause/resume,
automatic outage recovery and cold-device startup remain future work.
Offline tests verify generated packets with the independent decoder, timeout
before any music is sent, foreign-session rejection and cancellation cleanup.

Incremental decoding follow-up: Send-Mp3.ps1 now pre-reads bounded PCM before
startup instead of decoding the whole track. The final implementation uses
a fixed 65536-byte decoder staging buffer and an 800-byte packet buffer
(66336 application PCM bytes total); it consumes the first 200-frame block
before startup. Further native reads occur as staging is consumed during
pacing. Startup/readiness/session handling remains unchanged.
Generated startup plus the earlier direct-800-byte delivery path completed a 185.5-second
Track1 at 44100 Hz through natural EOF, including final partial-block padding
and B/F drain. Short live 44100/48000 checks and stop/reconnect passed again.
See [SENDER-TEST.md](./SENDER-TEST.md) for the bounded-buffer model, synchronous
read limits and full-track decoded-PCM equivalence tests.

The final staged implementation also completed Track1 at 48000 Hz with
8903209 decoded frames and 44517 audio blocks, restoring nine tail frames
lost by the earlier direct-small-read resampler pattern. The complete
capture independently validates startup, packet CRC/decoding, 12 identical
retransmissions, 191 zero-padding frames and final B/F drain.
Stop/suppress-next-track/socket-release and fresh-session reconnect passed
again with the final implementation at 44100 Hz.

Generation-boundary experiment: startup 253 / audio 255 completed a full
48000 Hz track using the earlier decoder (which omitted nine tail frames).
A subsequent fresh-session startup at generation zero failed readiness:
matching Df acknowledged only the first startup block (A=199, B=0, F=0).
The cause is not established. This does not validate wraparound, nor prove
that zero fails in every lifecycle state. Keep 30/32 as the tested default;
fresh sessions do not by themselves establish every generation is valid.

Observed, sender-side (PC 192.0.2.10 -> Expert 192.0.2.20).

## Phases
| t (s) | What | Evidence |
|---|---|---|
| 0 - 1.8 | Expert only broadcasts `Da` status (353 B, port 45454, ~every 0.31 s, in pairs). | frames 1-8 |
| 1.834 | Streaming enabled in AIR: first `Dm` at counter 0, header byte 10 = `06`, byte 11 = `02`. 38 blocks (counters 0-7400) are sent in ~150 ms (1112-byte payloads for 0-5800, 166-byte payloads for 6000-7400). | frames 9-52 |
| 1.84 - 8.2 | Idle: no `Dm` at all. Expert keeps sending `Df` every ~50 ms with A=7599, B=7400, n=0, so `Df` is a heartbeat/ack that is independent of audio. | 120+ `Df` |
| 8.214 | Playback starts: counter restarts at 0, header byte 10 = `08`. First 251 blocks have byte 11 = `02`, then `03` for the rest of the stream. | 2,400 blocks |

## Findings
* **Counter restarts at 0 for each playback start** (new stream), and the header byte 10 changed `06` -> `08` between the two. Treat it as a stream/generation id (+2 per start). Hypothesis only, one pair of observations.
* **Byte 11 (`02` then `03`):** `02` for the first ~1 s of real playback (251 blocks) then `03`. Likely a start-up vs steady-state flag. Unproven.
* **No deep prefill.** Pacing is real time from the first block: the sender leads wall time by only 6-16 ms (media time minus wall time) for the first 500 blocks. It is not a burst-then-pace design.
* **Sender clock:** over 8.3 s of media the wall time was 8380 ms (sender ~0.56% slow versus 48 kHz). The wall time is set by the playback source (winmm), not by AIR resampling. The Expert tolerated it with no `Df` intervals.
* **Start-up preamble in the first stream (counters 0-5800):** 1112-byte high-entropy payloads, which are far larger than the 174-byte blocks that encode silence. This looks like a one-off training/priming or a non-silence block type used right after stream open. It never appears in the second stream, so it is **not** required at every start. Content is not decoded.
* `Df` in start-up shows A=399, 1799, 5399 etc. with B=A-199: the Expert acknowledges blocks as they arrive, then A stays at 7599 when the stream stops.
* Offset-26 field of `Df` is 0 at start-up and begins to count only once real audio flows (about 2.4k per 50 ms, i.e. ~48000/s: a **sample/frame counter at the Expert**, which fits the 2400-frames-per-50 ms rate seen in all captures).

## Repeat cycles (air-cycle1..4, each: enable streaming, 3 s, play ~10 s clip, stop)
Header bytes 6-11 per stream segment (a segment = counter restarts at 0):

| Capture | Preamble segment (hdr 6-11, blocks, big blocks) | Playback segment (hdr, blocks `02`/`03`) |
|---|---|---|
| ref | 7700 0000 06 02, 38, 30 | 8: 251 / 2149 |
| cycle1 | 6100 0000 23 02, 40, 30 | 25: 247 / 2150 |
| cycle2 | 6100 0000 26 02, 36, 27 (plus 4 stray `25/03` blocks) | 27: 247 / 2152 |
| cycle3 | 6100 0000 28 02, 40, 32 | 2a: 247 / 2152 |
| cycle4 | 6100 0000 2c 02, 38, 30 | 2f: 266 / 2134 |

Confirmed by repeats:
* **The 1112-byte preamble burst appears at every streaming start** (27-32 large blocks, ~150 ms, 36-40 blocks total), then ~6 s idle. Correction of the earlier note that it only appears in the first stream: it is the stream-open phase, not a once-only event. Its content is still undecoded.
* **Playback is a new segment**: counter restarts at 0, byte 10 changes, first blocks are 174-byte (silence-sized).
* **Byte 10 is a stream generation counter** that increases at each new segment, usually by 1-3 (06->08, 23->25, 26->27, 28->2a, 2c->2f), so not a strict +1. Bytes 6-7 (`7700` vs `6100`) are constant within an AIR run and changed once between runs: likely a session/connection id.
* **Byte 11 is `02` for the first 247-266 blocks (~1.03-1.1 s) of a playback segment and `03` afterwards.** The switch point varies by up to 19 blocks, so it is probably time- or Expert-state-driven, not a fixed block count. The preamble segment is always `02`.
* Stray `Dm` blocks from the previous generation (4 blocks, `25/03`, 1368 B) can arrive just after the next stream-open (cycle2): the sender flushes late, the Expert should key on byte 10.

## Preamble content comparison (ref, cycle1-4)
**Checksum identified and verified:** bytes 982-983 of the 1112-byte blocks (and, in every `Dm`, the 2 bytes before the final 128 zero bytes) are **CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, big-endian) over all preceding payload bytes**, i.e. bytes 0 to len-131. Verified on **22,042 of 22,042 `Dm` payloads** across 9 captures (all cycles, drop tests, resends), including all 277 preamble blocks; the 128 trailing bytes are always zero. This is the same CRC as `Df`/`Da`. A sender must therefore recompute it for every block, with the generation byte and counter included in the covered range, and append 128 zero bytes. (The layout was already in BLOCK-DECODER.md; the earlier "unknown checksum" in this section was wrong, it simply varies because header/body vary.)

Compared the stream-open blocks (counters 0-7400, header byte 11 = `02`) byte by byte across five starts:

* **Three of five starts (ref, cycle1, cycle4) are the same sequence.** Block for block (same counter) they differ only at payload bytes 5-6 (session id, ref vs cycle1 only), byte 10 (generation) and **bytes 982-983 (the CRC, which changes because the generation byte changes)**. Real encoded data ends at byte 981; the rest to 1112 is the CRC plus 128 bytes of zero padding.
* **Two of five starts (cycle2, cycle3) carry different content**: 950+ of 1112 bytes differ against the others and against each other, yet the same size pattern (27-32 blocks of 1112 B, then 166 B) and the same header layout. So the preamble is **not one fixed constant sequence**: it is either (a) a deterministic function of some state (e.g. previous stream / encoder state) or (b) something with a per-start random element such as a nonce or scrambling seed. Seeing the same bytes three times out of five argues against pure randomness; (a) is more likely, but unproven.
* Within one preamble, successive blocks differ from each other (no repetition), and the bodies are not random-looking in byte statistics (about 224 distinct values and ~12% zero bytes per body), consistent with compressed audio of constant magnitude (the earlier decode saw ~1.26M constant magnitude), i.e. a priming/test signal rather than the user's audio.
* Conclusion for a sender: a replay of the "common" preamble with a recomputed checksum and updated header bytes would reproduce 3 of 5 observed starts. Whether the Expert accepts any particular preamble, or needs one at all, is **untested** (needs a live send test with your approval).

## Sender prototype implication
1. Send `Da`-independent `Dm` blocks of 200 frames every 4.1667 ms from your own clock, counter starting at 0 on each new stream.
2. Listen on port 45456 for `Df`; resend blocks in reported intervals; the Expert repeats requests every ~50 ms until satisfied.
3. Do not assume a big prefill is needed; keep lead at about 10 ms.

## Not yet verified
* What the first stream's 1112-byte preamble blocks contain, and whether the Expert needs them.
* The exact meaning of byte 10/11 (needs captures from several start/stop cycles).
* Whether a stream can be started with a pure-silence first block (i.e. no preamble).
* Whether the preamble is a fixed sequence (compare payload bytes across cycles) and whether byte 11 `03` is triggered by Expert state.
