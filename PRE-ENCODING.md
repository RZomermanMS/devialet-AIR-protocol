# AIR pre-encoding processing: what the decoded samples really are

Scripts: `Analyze-Residual.ps1`, `Analyze-FractionalDelay.ps1`, `Analyze-SineFit.ps1`, `Analyze-Spectrum.ps1`, `Analyze-LocalStability.ps1`, `Analyze-RampFit.ps1`, `Analyze-NoiseSharing2.ps1`, `Analyze-Lattice.ps1` (all offline, on `air-dumpcap-ref.pcapng` and cycle1/3/4; reference WAV = 997 Hz, 32.8 LSB amplitude, 48 kHz / 16-bit).

## Result

Per 200-frame block, decoded samples follow

    dec[i] = dec[0] + g * k[i] - b * i        (i = 0..199, k[i] integer, g = 77.276, b = 0.48)

with **g = 77.276 (= 256 x 0.3019, i.e. 16-bit to a 24-bit-style domain with about 30% gain) and a linear ramp of -0.48 decoded units per frame that restarts in every block**. Deviation from this model is 0.012 lattice units (about 1 decoded unit, rounding). Reproduced identically in four independent sessions (ref, cycle1, cycle3, cycle4: same g and b).

Evidence, in order:
1. Gain 77.26 and a stable pure 997 Hz tone. Local 20 ms windows: amplitude std 0.057%, phase std 0.0045 frames, no drift, so the earlier 8.5% mismatch is not clock drift or a rate change.
2. Tone phase offset of 0.423 frames (-0.0551 rad) relative to the source. Constant over the whole stream.
3. Residual after the sine fit is 35.65 units. **Adding a per-block linear ramp (slope -0.4735/frame) drops it to 22.89 = 0.296 LSB**, the quantisation noise of a 16-bit signal. A gain ramp or delay ramp adds nothing (checked).
4. Spectrum: above 4 kHz the decoded noise floor equals the source's 16-bit noise floor; the excess below 2 kHz is the sawtooth ramp (240 Hz harmonics). Odd harmonics H3/H5 are at -59/-63 dB.
5. Lattice: the decoded values minus the ramp are integer multiples of 77.276 (rms 0.012 versus 0.289 for random).

## Consequences

* **The earlier 8.5% error was not codec loss.** Codec is exact (see BLOCK-DECODER.md round-trip); the differences come from (a) a constant 0.423-frame phase shift, (b) a per-block ramp of -0.48/frame, (c) the integers k[i] being a re-quantised 16-bit version of the tone rather than the source integers.
* **k[i] noise is uncorrelated with the source's own quantisation noise** (correlation below 0.12 at all integer shifts, same rms 0.292 LSB). So AIR re-quantises (or resamples then re-quantises) the audio to 16-bit once; it is not a plain scaled copy of the WAV samples.
* **Sender implication:** the Expert needs no special ramp; any integer sequence scaled by g is a valid payload (blocks are self-contained: first sample + deltas). Starting `dec[0]` anywhere is fine. Whether the Expert plays a ramp-free signal identically is untested.

## Not explained (be honest)

* Why the ramp exists: candidates are a per-block DC/dither term or a volume-smoothing artefact; its slope (0.48 per frame, about 96 per block, roughly 1.24 x g) has no confirmed origin.
* Why the phase offset is 0.423 frame (about 8.8 us), possibly filter group delay of a resampler.
* Only one tone at one level and 0.30 gain were tested, mono-in-stereo. Different volume, level or music may change g, b, or the ramp. The stereo-ramp capture and a loud multitone test would resolve this.

## Multitone capture (air-multitone, ~-35 dBFS, distinct L/R tones)

All 2400 blocks decode, 0 rejected (widths up to 16). Lattice model holds on both channels: best g=77.136, ramp=0.497/frame, rms lattice distance 0.034 (L) / 0.026 (R), versus 0.289 for uniform. Using the earlier constants (77.276, 0.48) gives 0.25, so g and ramp vary slightly between sessions (~0.2%) and are not universal constants. Peak decoded magnitude 36723 (475 source LSB x 77.3). Script: Analyze-Multitone.ps1.
