# AIR `Dm` audio analysis

**Later reference-capture update:** a constrained channel-block decoder now
recovers actual sample values with a measured 997 Hz tone. See
[block decoder findings](./BLOCK-DECODER.md). The opaque-body and codec-blocked
conclusions below are retained as the earlier batch's historical findings.

`Audio.ps1` is dot-sourceable and exports:

* `ConvertFrom-AirDm([byte[]])` — validates `44 6D`, requires the 22-byte header, reads mode byte 11, BE64 sample counter at bytes 12–19, BE16 sample count at bytes 20–21, and preserves the bytes from 22 onward as an opaque body.
* `Get-AirAudioAnalysis([object[]])` — accepts packet objects with `PayloadHex` (and optional `TimestampRaw`), measures counter/body evidence without decoding audio.

## Controlled capture result

`Test-Audio.ps1` reads the immutable full-payload `air-session-packets.csv` and writes `audio-results.json`. The controlled input contains 951 `Dm` packets, 746 unique BE64 counters, and 205 duplicate counter occurrences whose full payloads are identical; no payload conflicts were found. Coordinator integration strengthened the fingerprint from body-only to full payload and tested differing headers with identical bodies. This is evidence of duplicate observations, **not** a retransmission claim.

All observed counters are on a 200-sample grid. Across the observed 4,600–478,600 range, 746 of 2,371 grid positions are present (1,625 missing). There are 336 adjacent capture-order counter decreases; this measured ordering condition is not attributed to sender or network reordering.

Modes are measured from the input (`02` controlled); the baseline CSV exposes only prefixes. Coordinator integration additionally parsed the retained full baseline corrected pcapng: 1,833 Dm packets, 1,833 unique positions, mode `03`; full-payload analysis is saved in `baseline-inspection.json`.

Observed payload-length transitions, ordered by counter, are `166→614` across 141,600→142,800, `614→664` across 143,000→143,400, `664→714` across 143,600→143,800, then `714→614` across 332,200→334,400 and `614→166` across 334,400→334,600. These bracket the expected 144,000–336,000 tone interval (including its fades) but missing grid positions and mixing prohibit a sample-level timing claim.

## Codec boundary

The candidate header field is consistently 200, while full payload sizes are 166, 614, 664, and 714 bytes (opaque remainders after byte 21: 144, 592, 642, and 692 bytes). Their variable 0.720–3.460 remainder bytes/candidate frame are incompatible with an entire fixed PCM16LE stereo block (800 bytes), PCM16LE mono (400), or PCM24BE stereo (1,200) beginning exactly at byte 22. This does not establish the true codec/body boundary or exclude PCM inside another compressed/framed representation. The capture has gaps; actual network loss is unproven. No PCM, sample values, channel interpretation, or 997 Hz measurement is produced.

The narrow blocker is a contiguous full-payload controlled recording (or offline sender codec specification) spanning a stable portion of the known 48 kHz test signal. That would permit a bounded codec/framing test without inventing PCM.
