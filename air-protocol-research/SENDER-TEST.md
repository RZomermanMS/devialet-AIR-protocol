# Minimal sender test (Send-Minimal.ps1)

Sender binds UDP 172.16.5.252:45456 (AIR streaming off), replays the 38-block captured preamble (byte 10 = generation, CRCs recomputed), waits 1 s, then streams a quiet 997 Hz tone (amplitude 30 LSB x 77, both channels) from counter 0 with byte 10 = generation+2, byte 11 = 02 (03 from block 250), 200 frames every 4.1667 ms, resending B+200 when a Df reports a gap.

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
