# AIR reference block decoder

**Asymmetric stereo follow-up:** [stereo ramp results](./STEREO-RAMP.md) establish
independent per-channel lengths and left/right correspondence in the tested
configuration. The decoder now supports unequal widths. Equal-size restrictions
below describe the initial tone-only implementation. The follow-up also establishes
a common best integer source offset on nonperiodic signals, not bit-exact fidelity.

Updated 17 October 2026 following the known WAV capture. This supersedes the
earlier codec-blocked conclusion **for the narrow packet configuration below**.
It does not establish the complete AIR codec family or a working sender.

## Observed packet envelope

All 561 reference-capture Dm packets validate this layout:

| UDP payload offset | Size | Meaning / evidence |
|---|---:|---|
| 0 | 22 | Previously identified Dm header; BE64 candidate frame position at 12 and BE16 frame count at 20 |
| 22 | variable | First candidate channel block |
| after first block | variable | Second candidate channel block |
| after second block | 2 | Big-endian CRC-16/CCITT, polynomial 0x1021, initial 0xFFFF, over preceding UDP payload bytes |
| after CRC | 128 | Zero bytes; their protocol purpose is unknown |

Both blocks are identical in all 561 packets, consistent with the identical-channel
source. Their channel order is not independently established. The current decoder
only supports equal-size blocks with the observed configuration; it must not be
advertised as a general stereo decoder.

## Narrow channel-block layout

Offsets here are relative to the start of each channel block:

| Offset | Size | Interpretation |
|---|---:|---|
| 0 | 3 | Signed 24-bit big-endian starting sample |
| 3 | 4 | Observed configuration `00 00 w w`; the full semantics of this field remain unknown |
| 7 | ceil(199 * w / 8) | 199 MSB-first, fixed-width delta codes |

For each code `u`, compute the signed delta as `(u >> 1) XOR -(u & 1)`.
Add that delta to the previous sample. The starting sample plus 199 deltas gives
200 reconstructed samples. Remaining bits in the final byte must be zero.
Width zero represents 200 copies of the starting sample and has no packed data.

| Width w | Channel bytes | Full UDP payload bytes |
|---:|---:|---:|
| 0 | 7 | 166 |
| 7 | 182 | 516 |
| 9 | 231 | 614 |
| 10 | 256 | 664 |
| 11 | 281 | 714 |

The reference WAV capture contains widths 0, 7 and 9. The earlier independent
controlled capture accepts widths 0, 9, 10 and 11 across all 951 packets, including
CRC, padding, configuration and sample-range checks. This is structural
cross-validation, not a measured-frequency claim about that earlier capture.

## Measured comparison, not just payload sizes

`Decode-ReferenceBlocks.ps1` reconstructs the samples and exports
`reference-decoded-samples.csv`, retaining frame positions. It does not generate
a misleading continuous WAV with fabricated samples in missing regions.

Results for the reference capture:

- 561 packets, 112,200 unique sample frames per channel.
- Zero channel disagreements and zero conflicting sample observations.
- 35,400 recovered samples in the source's steady-tone region were used for a
  sine/cosine least-squares frequency search from 990 to 1004 Hz, step 0.1 Hz.
- Best frequency: **997.0 Hz**.
- Sine-fit R-squared: **0.9985724573**.
- Fitted peak in candidate 24-bit units: approximately **1093.53**.
- Comparing to quantized source samples over trial offsets -512 to +512 frames,
  the best positive correlation is **0.9974483585**, with fitted gain approximately
  **33.340824 candidate units per source PCM16 unit** and gain-adjusted RMSE
  **55.33646 candidate units**.
- The best trial offset is +365 source frames, but a periodic signal has many
  phase-equivalent alignments. **This is not a measured latency.**
- 455 recovered samples are nonzero at positions where the corresponding
  unshifted reference sample is zero. Bit-exact preservation is not established.

The frequency and correlation strongly support this delta-unpacking interpretation.
They do not prove every field's semantics, exact sample alignment, or that the
only remaining differences come from Windows mixing. Other possibilities include
format scaling, timing alignment, audio processing and unmodeled codec behavior.

Capture visibility remains poor: 1,829 positions are absent from the observed
200-frame grid. The recovered sample CSV is sparse and must be analyzed as such.
No missing samples are silently replaced with zeros.

Byte 11 changes from mode 02 to 03 during source silence, around frame 52,800.
It is not a simple silence/tone flag. The same narrow block decoding works across
both values in this capture; broader mode behavior remains unknown.

## Reproduce

Run from this directory with Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Decode-ReferenceBlocks.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-ReferenceBlocks.ps1
```

Execution policy bypass applies to that process only. These commands are entirely
offline and use existing captures. They do not open audio devices, send packets,
request elevation, or change volume.

The initial 16 focused tests cover positive and negative synthetic delta reconstruction,
zero-width signed seeds, CRC corruption, padding/configuration/length rejection,
sample overflow, all 561 reference packets, the independent 951-packet capture,
and the persisted recovered-tone result. Synthetic test success establishes
implementation consistency, not independent proof of the wire format.

## Remaining gates

1. Test different left/right signals to establish channel boundaries and ordering
   without relying on channel equality.
2. Establish the complete four-byte configuration field and support unequal
   channel sizes, other formats and all relevant width/mode combinations.
3. Use an impulse or nonperiodic ramp and improved capture visibility to determine
   alignment and processing/scaling; require exact recovery where justified.
4. Determine feedback, pacing, session lifecycle and resend semantics before
   implementing a native sender.

## Encoder round-trip (verified)

`Test-EncoderRoundTrip.ps1` re-encodes decoded samples and compares to the captured bytes (captures ref, cycle1, cycle3):

* Channel = 3-byte signed 24-bit first sample, bytes `00 00 W W`, then `199` zigzag deltas, `W` bits each, MSB-first, zero-padded to a byte.
* **Width rule: `W` = bit length of the largest zigzag delta in the channel (minimal width).** Matched the original width for 100% of channels.
* Packet = 22-byte header + left channel + right channel + CRC-16/CCITT-FALSE + 128 zero bytes.
* **Result: 7,314 of 7,314 packets (7,222 playback, 92 preamble) re-encoded byte-for-byte identical.** The codec (both directions) is fully understood; the audio-level mismatch against the source WAV (rms ~8.5%) is therefore **not a codec issue**: it comes from what the sender does to the audio before encoding (gain, resampling or filtering), not from block format.
* A sender can therefore build valid blocks from any 24-bit-range stereo samples. What is still unknown is whether the Expert needs particular header bytes (6-7 session id, 10 generation, 11 phase) or the preamble.
