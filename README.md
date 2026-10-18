# Devialet AIR protocol research

Updated **18 October 2026**. Experimental standalone AIR sender and protocol
research for an eventual Music Assistant provider and Windows ARM64 transport.
Neither integration nor an ARM64 audio driver has been built yet.

## Current manuals and source

**[air-protocol-research/](./air-protocol-research/) is the canonical tree.**

- [Research overview and current status](./air-protocol-research/README.md)
- [Operator manual](./air-protocol-research/OPERATOR-MANUAL.md): dependencies,
  discovery, safe playback, stop, playlists and troubleshooting
- [Developer manual](./air-protocol-research/DEVELOPER-MANUAL.md): test matrix,
  architecture, Music Assistant and Windows ARM64 roadmap
- [Tested protocol reference](./air-protocol-research/PROTOCOL.md)
- [Latest results, failures and hashes](./air-protocol-research/LONG-RUN.md)
- [Repository agent instructions](./AGENTS.md)

Older scripts, research documents and the checksum file at repository root
remain historical copies from the first upload. **Do not use those root-level
copies as the current sender.** Run and modify the canonical research tree.
Only this root README, AGENTS, .gitignore and .github customizations are current
repository-level entry points.

## Readiness

Enough wire-protocol evidence exists to **start a constrained Music Assistant
provider/shared user-mode AIR transport**, not to claim production reliability.
The final sender passed complete 48 kHz playback/capture validation and
18 deterministic loopback cases. A prior 19-minute Qmusic run passed before
the final decoder staging fix, but the latest whole-Qmusic rerun stalled and
failed safely. Automatic outage recovery remains unimplemented; acoustic
fidelity is not established by packet acknowledgements.

The supported starting scope is one Expert, stereo PCM16 input at
44100/48000 Hz, generated startup, fresh sessions, bounded repair, play/stop
and explicit error handling. No native PCM24/high-rate, remote flush, gapless
or synchronization guarantee is made.

## Working with agents

[AGENTS.md](./AGENTS.md) applies repository-wide. VS Code also provides:

- **AIR integration** in the custom-agent picker
- **/validate-air** to run the six synthetic/loopback suites sequentially,
  without a physical device or private evidence

These do not grant permission for live playback, capture or driver changes.
Read the manuals before operating hardware.

## Publication boundaries

No audio, packet captures, decoded samples, local logs, credentials or
downloaded dependencies are included. Current publication copies replace
private home/session paths with `C:\Evidence` and lab network addresses with
documentation-only `192.0.2.x` examples. Those example addresses are not real
configuration defaults; set actual endpoints explicitly before any approved
live operation. Historical root copies are not rewritten by this update.

[SHA256SUMS.csv](./air-protocol-research/SHA256SUMS.csv) covers the current
publication package using repository-relative paths, excluding itself and
historical root copies. No new license is asserted; see the research overview.
