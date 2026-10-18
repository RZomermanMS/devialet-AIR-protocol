# Tested AIR protocol reference

Scope: one observed Devialet Expert, stereo 200-frame blocks, PCM16-derived
samples, 44100/48000 Hz. This is an empirical implementation contract, not a
vendor specification. Offsets are zero-based UDP payload offsets, multibyte
integers big-endian. Source acoustic fidelity is not inferred from feedback.

## Transport

| Message | Flow |
|---|---|
| Da | Expert broadcast from UDP 45454; passive status/discovery |
| Dm | Sender local UDP 45456 to selected Expert UDP 45455 |
| Df | Expert UDP 45456 to sender UDP 45456; acknowledgement/repair |

The current sender binds the routed local IPv4 address exclusively. Passive
readiness and exclusive local bind are not remote ownership arbitration.
Da validates trailing CRC on observed 345-byte status and synthetic 512-byte
status. [DISCOVERY.md](./DISCOVERY.md) describes eligibility and limitations.

## Dm audio block

| Offset | Size | Tested meaning |
|---:|---:|---|
| 0 | 2 | Magic `44 6d` |
| 2 | 1 | `02` |
| 5 | 2 | Session identity |
| 10 | 1 | Stream generation |
| 11 | 1 | Rate/start-versus-steady mode |
| 12 | 8 | Frame counter, block start |
| 20 | 2 | Frame count, 200 |
| 22 | variable | Left channel, then right channel |
| after channels | 2 | CRC16/CCITT-FALSE |
| after CRC | 128 | Zero bytes |

Generated headers zero other unspecified fields; this works in tested starts,
but does not assign semantics to every header byte.

Each channel is a signed 24-bit starting sample (3 bytes), configuration
`00 00 W W`, then 199 deltas, each W bits MSB-first. Zigzag encode:
`(d << 1) ^ (d >> 31)`; decode: `(u >> 1) ^ -(u & 1)`.
W is the minimum width for the channel's maximum zigzag delta. Byte-pad each
channel with zeros. W=0 is a constant channel.

CRC: polynomial 0x1021, initial 0xffff, no reflection, xorout zero, stored
big-endian over all bytes before the CRC. The following 128 zeros are not
included in the CRC.

Wire samples currently equal rounded PCM16 input times gain times 77.276.
Signed-24-bit bounds are enforced. This is an empirical scale, not calibrated
full scale or a required vendor transform. Full signed-24-bit extreme deltas
can require 25 bits; the independent decoder supports widths up to 24.
Receiver acceptance of width 25 is unknown; do not advertise full-range PCM24.

Observed sender mode choices:

| Rate | Initial mode | Steady mode | First steady block (zero-based) |
|---:|---|---|---:|
| 44100 | 00 | 01 | 227 |
| 48000 | 02 | 03 | 250 |

These fixed thresholds work in tested streams; complete rate negotiation
semantics are not known.

## Startup and identity

1. Pass fresh passive status/input/port/traffic readiness guards.
2. Generate 38 stereo-silence Dm packets, counters 0 through 7400, using a
   random nonzero 16-bit session and default generation 30.
3. Require matching Expert endpoint, session, generation, valid CRC/length
   and B=7400 with no missing intervals within two seconds.
4. Wait one second, reset audio counters to zero and use generation 32.
5. Pace one 200-frame audio block every `200 / sampleRate` seconds.

No reference capture or vendor AIR service is used by generated startup.
Random sessions are not collision-free and session expiry is incompletely
known. Generation 253/255 worked; a later fresh-session generation-zero
startup acknowledged only A=199/B=0/F=0 and failed. Do not infer universal
modulo wrap, required monotonicity or acceptance of all generations.

## Df feedback

| Offset | Size | Meaning used by sender |
|---:|---:|---|
| 0 | 2 | Magic `44 66` |
| 4 | 2 | Session identity |
| 9 | 1 | Generation |
| 10 | 8 | A: highest observed frame endpoint |
| 18 | 8 | B: last contiguous block start |
| 26 | 8 | F: receiver/reference frame counter |
| 37 | 2 | Number n of missing intervals |
| 39 | 4n | n pairs of inclusive BE16 start/end indexes |
| end | 2 | CRC16/CCITT-FALSE |

Total length is `41 + 4*n`; CRC covers preceding bytes. Other fields are
not fully specified. F is not a verified acoustic/DAC position.
Require expected source IP/port, session/generation, CRC, consistent
length/count and nondecreasing B within already-sent bounds.

For interval index i, the requested block counter is:

```text
base = F - (F % 200)
counter = base + 200 * i
```

Expand each inclusive interval using the F in that same feedback packet.
Bounds, sorted nonoverlapping intervals, counters after B and not beyond
already-sent/A endpoints, maximum request size and cache presence are
mandatory. The relative-F mapping is cross-checked against official controlled
loss captures; mock tests exercise this interpretation but are not additional
independent protocol discovery.

Cache at most 400 encoded audio packets. Repairs are ordered/deduplicated,
skip blocks already acknowledged and send at most one resend per 200-frame
period in addition to normal audio. A request exceeding 400 blocks or missing
from cache is a visible error, not an invitation to fabricate samples.
400 cached blocks do not guarantee recovery from every outage of that size.

## Completion, cancellation and known failure

- Two seconds without valid feedback fails playback.
- Two seconds without B progress while sent data remains outstanding fails.
- At EOF, pad the final block with zeros; require B at last sent block.
- Then require F at least last counter + 200, with bounded three-second drain
  waits and a feedback timeout. This is transport completion only.
- Stop ceases sending and closes the socket; buffered receiver audio may
  finish. There is no demonstrated remote flush/pause command.

Live tests have frozen B while valid feedback/F continued and interval count
was zero. The sender fails safely rather than inventing repair requests.
Cause and automatic recovery remain open. Higher rates, exact clock control,
other firmware, cold boot, session expiration, native PCM24 and multiroom
synchronization are not established.

Detailed evidence: [STARTUP.md](./STARTUP.md), [FEEDBACK.md](./FEEDBACK.md),
[DROP-TEST.md](./DROP-TEST.md), [BLOCK-DECODER.md](./BLOCK-DECODER.md),
[FORMATS.md](./FORMATS.md), [LONG-RUN.md](./LONG-RUN.md).
