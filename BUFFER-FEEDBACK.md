# AIR buffering and missing-block feedback

Offline comparison of the three retained controlled recordings, 17 October 2026.
No playback, network manipulation, packet injection or volume changes were used.
Reproduce with `Analyze-BufferFeedback.ps1`; numerical results are persisted in
`buffer-feedback-results.json`.

## Established structure

Dm packets carry a candidate frame position at payload offset 12 (BE64) and
200 samples per channel at offset 20 (BE16). At 48 kHz a fresh 200-frame block
represents 4.1667 ms, hence nominal production is 240 fresh blocks/second.
This arithmetic does not establish actual network scheduling or burst behavior.

Df packets return to UDP port 45456. Their two BE64 fields start at offsets
10 and 18, called A and B until semantics are independently established.
The BE16 interval count at 37 is followed by pairs of BE16 endpoints from 39,
and a trailing CRC16. Packet size is 41 + 4 * interval count.

## Healthy/reference recordings

- Reference tone: all 230 feedback packets have empty interval lists;
  all satisfy B = A - 199. No repeated audio counters are observed.
- Stereo ramp: all 213 feedback packets have empty lists;
  all satisfy B = A - 199. No repeated audio counters are observed.
- Active A-counter advance is approximately 48,442 and 47,780 units/second
  respectively. Active-span endpoints exclude the final stopped-counter plateau,
  but sparse observation and startup effects still affect these rate estimates.
- Mean observed feedback spacing from the initial timing inspection is about
  56 and 61 ms. These are capture observations, not a guaranteed feedback period.

The relationship suggests A is an inclusive endpoint and B is a block-start
frontier, but does not distinguish received, buffered, consumed or played frames.
Neither field is yet proven to be an acoustic playout clock.

## Repeat-heavy earlier recording

- 161 nonempty feedback lists, growing to 90 intervals.
- B remains 11,800 while A eventually reaches 216,799.
- In all 161 lists, the first interval begins at B / 200 + 1 (block index 60).
- 205 additional audio observations repeat previously seen frame positions.
- **185 / 205 (90.24%)** repeat positions fall in the latest preceding captured
  feedback interval list.
- Only **223 / 730 (30.55%)** first-observed positions after feedback fall in those
  lists. A first observation is not necessarily the first transmission.

This is stronger evidence for missing-block/resend ranges than the earlier
uncorrelated field inventory: repeats are preferentially associated with listed
blocks, while the no-range captures show no repeats. Nevertheless, capture
duplicates, incomplete timing visibility, and unobserved sends/feedback prevent
conclusive causal attribution. Endpoints are provisionally treated as inclusive
block indices; range semantics remain a well-supported hypothesis, not a complete
protocol contract.

## Candidate sender model (not implemented or verified)

1. Generate fresh 200-frame blocks from the source clock.
2. Keep encoded blocks indexed by frame/block position in a bounded history.
3. Process Expert feedback and service candidate missing-block ranges using
   original encoded blocks, without advancing the source position for repeats.
4. Use an established receiver frontier and target lead to pace fresh sends.

Steps 2-4 are design hypotheses. We have not established buffer lead, startup
prefill, window limits, resend deadline, acknowledgement retirement, wraparound,
congestion/backoff or underrun recovery. Do not implement a production sender by
guessing these values or treating A as confirmed consumed audio.

## Next bounded experiment

Obtain more complete sender-side capture with reliable timestamps and correlate
unique send positions minus A/B over time. In a separately approved test, introduce
a small, precisely logged loss of selected test-signal packets and check whether
the exact block indices appear in feedback and are resent afterward. The loss
test has not been performed or authorized by this offline analysis.
