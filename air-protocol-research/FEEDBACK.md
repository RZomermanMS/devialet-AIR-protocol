# F1 Feedback (Df/Da) decoder

Files: `Feedback.ps1` (dot-source; needs Common.ps1), `Test-Feedback.ps1` (30 tests, exit 1 on failure, writes `feedback-results.json`).

## Subsequent sender findings (2026-10-18)

The historical correlations below predate the controlled-loss work. For the
tested 200-frame streams, B is the last contiguous block start, A is the
highest observed frame endpoint, and F at offset 26 is an advancing
receiver/reference frame counter. An interval index maps to:

`counter = F - (F % 200) + 200 * index`

See [DROP-TEST.md](./DROP-TEST.md) for official-sender capture evidence and
[SENDER-TEST.md](./SENDER-TEST.md) for sender/mock/live validation. The old
first-index=B/200+1 correlation applies when F is zero; it is not a general
absolute block-index formula. F is not acoustic confirmation or a calibrated
DAC clock. Session bytes are Dm[5..6] and Df[4..5], as noted below.
The sender now validates session as well as generation, source, length and CRC.

Da decoding also accepts the upstream 512-byte layout with trailing CRC, in
addition to the observed local 345-byte status; see DISCOVERY.md. No inference
of arbitrary format negotiation, other block sizes or generation-wrap rules
is made by these follow-up findings.

## Interface (no side effects)
- `ConvertFrom-AirDf([byte[]])` - throws on null, len<41, bad magic 4466, (len-41)%4!=0, BE16 count@37 != n, CRC mismatch. Returns Length, Session4_5, Session5_6, Field10_U64BE, Field18_U64BE, Count, Intervals(Start/End), IntervalsOrdered (flagged, not rejected), Crc, CrcValid.
- `ConvertFrom-AirDa([byte[]])` - throws unless len==345, magic 4461, CRC16 (over first 343) valid. Returns Name (19..50), Inputs[15] (52+17i: Flag + 16-char label), PowerOn (307&0x80), Muted (308&2), Channel ((308&0x3C)>>2), VolumeRaw (310), Volume ((raw-195)/2).
- `Get-AirFeedbackAnalysis(packet[])` - packets with PayloadHex; rejects are collected, never thrown. Returns counts, field stats, DaLast, Correlation, Dfs, DmSorted.
- Helpers: `Get-AirHexString`, `Get-AirDfDmCorrelation`.

## Results (1176 packets)
- Df 162/162 CRC+count+length valid, 0 rejected; Da 63/63 CRC valid (single state: "Devialet-WIFI", on, unmuted, channel 9, volume -28).
- Session: Df bytes 4..5 = 0x11BE; Dm bytes 5..6 = 0x11BE (Dm 4..5 = 0x0011) - verified, not assumed.
- Dm: counter BE64@12 multiples of 200 (4600..478600, 746 unique), block BE16@20 always 200.
- Df: 61 distinct lengths, up to 90 intervals; all ordered/disjoint. Field18 (BE64@18) constant 11800 (=59*200). Field10 (BE64@10) monotonic 11999..216799.

## Correlation (confidence: LOW overall)
- Exact (161/161 non-empty Df): first interval start == Field18/200+1; (Field10+1)/200 >= last interval End.
- Weak: P(block seen in Dm before Df | in interval)=0.461 vs gap 0.430. Intervals do NOT clearly track observed Dm blocks. Field10 lags max Dm block seen. Meaning of intervals/Field10 unproven (hypothesis: block-index ranges, possibly acknowledged/missing ranges; Field10 a playout/consumed position).

## Caveats
- Dm capture is sparse; correlation may be limited by capture, not protocol.
- Unordered intervals are flagged, not rejected.
- Scripts need ExecutionPolicy Bypass (`-ExecutionPolicy Bypass`).
- Feedback.ps1 was initially written via Set-Content (tooling lacked apply_patch/edit).
