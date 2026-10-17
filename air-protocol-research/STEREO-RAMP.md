# Asymmetric stereo and nonperiodic alignment experiment

17 October 2026. No Windows or amplifier volume setters were used. All 83 captured
amplifier status packets contain the same volume byte (0x56). This establishes
constant reported amplifier volume within this test, not a comparison to prior tests.

## Source and execution

`air-stereo-nonperiodic-ramp.wav` contains 480,000 frames of PCM16 stereo at 48 kHz.
Frames 0-95,999 and 384,000-479,999 are silent. Between those regions, independent
seeded knot values are joined with rounded linear ramps:

- Left: knots every 137 frames, values bounded by +/-32 PCM16 units.
- Right: knots every 211 frames, values bounded by +/-24 PCM16 units.
- Active edges have 50 ms fades.
- There are 280,464 frames with different left/right values.
- SHA256: `757ABE730E04A7CCBEE45938881477665CF03741267F2CDBA2651312A577FC99`.

AIR's Expert connection was selected, and the file was played directly through
the Devialet AIR waveOut device from 14:34:35 to 14:34:45 local time. Playback ended,
the capture stopped, and its filter was removed. The original capture is
`air-stereo-ramp.pcapng`; Packet Monitor again labeled native Wi-Fi frames as
Ethernet. `air-stereo-ramp-wifi.pcapng` is the separately corrected copy.

## Packet structure result

All 372 Dm packets decode with valid CRCs, trailing padding, block configuration,
and packed-bit padding. The blocks must be parsed independently, not split in half:

| First width | Second width | Packets | UDP payload bytes |
|---:|---:|---:|---:|
| 0 | 0 | 130 | 166 |
| 8 | 8 | 241 | 564 |
| 8 | 0 | 1 | 365 |

The first block's width determines its length as
`7 + ceil(199 * width / 8)`. The second block begins immediately after it and
has its own configuration and length. Both blocks together must terminate at
the verified CRC preceding the 128 trailing zeros.

## Channel correspondence

Each decoded block was compared against both source channels, allowing affine
gain/offset and an integer frame offset over -4096..4096. Every 23rd available
active sample selected the offset. Final fits use all 47,200 selected active
samples per block:

| Decoded block | Source channel | Best source offset | Correlation |
|---|---|---:|---:|
| 0 | left | +1376 | 0.9999689713 |
| 0 | right | -733 | 0.1672183397 |
| 1 | left | -393 | 0.1325910948 |
| 1 | right | +1376 | 0.9999833982 |

This gives independent signal-based evidence that block 0 is left and block 1
is right in this 48 kHz stereo configuration.

## Integer alignment validation

The other 45,147 samples per channel were held out of offset selection. Among
offsets 1373..1379, **1376 is the best on both held-out channels**. The first and
second time windows each independently prefer 1376 within the same neighborhood:

- Left held-out correlation: 0.9999689471.
- Right held-out correlation: 0.9999834055.
- Left first/second window correlations: 0.9999680965 / 0.9999714114.
- Right first/second window correlations: 0.9999827625 / 0.9999839889.

The convention is `decoded(counter) ~ gain * source(counter + 1376) + offset`.
The common source-relative offset is 28.6667 ms at 48 kHz.
**It is not an acoustic/network-latency measurement.** The integer alignment is
supported in observed regions, not a guarantee for every AIR session or format.
Fractional-delay behavior has not been excluded.

## Sample fidelity and remaining limits

Fitted gain is approximately 77.4196 on the left and 77.2424 on the right in
candidate 24-bit units per source PCM16 unit. This is not an unscaled bit-exact match.
After alignment and per-channel affine fitting:

| Held-out metric | Left | Right |
|---|---:|---:|
| RMSE in source PCM16 units | 0.12080 | 0.06883 |
| Maximum absolute error in source PCM16 units | 0.61124 | 0.42582 |
| Rounded source PCM16 equality | 99.8538% | 100% |

These figures use a fitted scale/offset; they must not be presented as bit-exact
transport fidelity. Rounding/clipping/processing or further codec details remain
possible explanations. Source fit does not prove which processing stage changed
the samples.

Capture visibility remains incomplete. No missing sample values were invented.
`stereo-ramp-decoded-samples.csv` preserves observed frame coordinates.

## Reproduce offline

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Compare-StereoRamp.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-ReferenceBlocks.ps1
```

The decoder tests now include synthetic unequal-width stereo, all 372 new packets,
channel/held-out/window alignment thresholds, and constant in-capture amplifier
volume. Previously validated tone captures remain regression tests.

The next protocol work is to identify the full configuration-field semantics,
test more sample formats, and map feedback/session/pacing behavior. This result
does not yet establish a native sender.
