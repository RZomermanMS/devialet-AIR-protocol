# Full-stream decode of the dumpcap capture

Capture `air-dumpcap-ref.pcapng` (Wireshark/Npcap, host filter 192.0.2.20, reference tone, volume untouched).
Scripts: `Compare-FullStream.ps1`, `Find-Offset.ps1`, `Fit-FullStream.ps1`.

## Results

* All **2,400 unique `Dm` blocks (counters 0..479800, step 200, no gaps) decode with the narrow block decoder, 0 rejected.** This is the first capture that covers the whole stream, so the decoder is not limited to one block variant (modes 2 and 3 both decoded).
* Left and right are identical for this mono-in-stereo reference (0 differing frames).
* Level profile: decoded silence is exactly 0 outside the tone; the tone spans about 2.75-6.9 s of stream time and is steady (rms about 1,793 decoded units).
* The decoded scale is about **77 decoded units per source 16-bit LSB**, so decoded values are a scaled/24-bit-domain representation, not 16-bit PCM.
* After aligning with a single integer lag (decoded - source = -1569 frames; this lag is not constant between sessions, the earlier ramp test had +1376, because the stream counter starts at stream enable, not at file start), tone correlation is **0.9978** over frames 150,000-330,000.
* Tone length: source 191,597 frames, decoded 191,910 frames (within about 0.2%, edge thresholds are approximate).

## Caveats (not claimed)

* **Not bit-exact:** rms residual after gain fit is 76.8 decoded units against tone rms of about 903 (about 8.5%, roughly -21 dB). Causes not yet separated: mixer/volume scaling and rounding, sub-frame alignment, or encoder behaviour. Do not call the decoder lossless.
* 2,174 decoded frames are nonzero where the source is exactly 0, which fits an imperfect lag at the tone edges rather than leakage, but this was not isolated.
* The first ~30 blocks (counter 0..5800, mode 02, 1112-byte payloads, magnitude about 1.26 million constant) are not audio from the source. They look like a stream start preamble or sync pattern and must be excluded or understood before a sender can reproduce stream start.
* Only 48 kHz / 16-bit stereo, one level, one tone were tested; other rates, depths and high-level material (wider channel widths) are untested.
