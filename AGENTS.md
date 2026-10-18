# Repository instructions

## Read first

- Published `air-protocol-research/` is canonical. Older root-level script
  copies are historical; do not maintain a second implementation there.
- Read [README.md](./air-protocol-research/README.md), [DEVELOPER-MANUAL.md](./air-protocol-research/DEVELOPER-MANUAL.md)
  and the latest section of [LONG-RUN.md](./air-protocol-research/LONG-RUN.md) before changing the
  sender or claiming integration readiness.
- [PROTOCOL.md](./air-protocol-research/PROTOCOL.md) is the tested contract, not a universal AIR
  specification. Distinguish observed behavior, mock assumptions and unknowns.

## Safety and privacy

- Default to offline tests. Obtain explicit current authorization before
  physical-device playback/capture, packet interference or driver operations.
  Preparing documentation or running loopback tests is not live authorization.
- Never change device/Windows/AIR volume, power, mute, input, firewall or
  network configuration automatically. Do not stop another sender.
- Preserve readiness, source/session/generation/CRC guards, watchdogs, sample
  bounds, final acknowledgement/drain and exclusive socket ownership.
- Keep captures, audio, logs, decoded samples, credentials and downloaded
  packages local and untracked. Publish only reviewed source/documentation.
  Do not fabricate unavailable capture evidence or upload it for analysis.

## Implementation and tests

- Scripts target Windows PowerShell 5.1 and embedded C# via Add-Type; preserve
  sibling-file/PSScriptRoot layout. Avoid PowerShell 7-only syntax.
- Follow existing helpers and named ReadPcm delegate. Keep PCM staging,
  resend cache, pending repairs and source queues bounded.
- Run affected tests from the developer manual. Watchdog/integration tests
  share loopback ports: run sequentially in separate PowerShell processes.
- Decoder changes require short-read/EOF/cap/error tests and complete PCM
  frame/hash comparisons when local sources are available. Packet validation
  alone cannot detect omitted source frames.
- Report exceptions, cancellation and incomplete playback explicitly; do not
  relax deadlines or return success to make a live test pass.
- Update directly affected manuals and results. Preserve failed experiments
  and qualify historical conclusions instead of rewriting them as successes.

## Boundaries for future integrations

- First target one Expert, stereo PCM16 input at 44100/48000, fresh sessions
  with default generation 30/32, play/stop and explicit failure handling.
- No acoustic/bit-perfect, universal generation-wrap, native PCM24/high-rate,
  remote flush, gapless, clock-sync or production reliability claims.
- Music Assistant and Windows ARM64 implementations do not exist yet.
  Pin actual MA APIs; keep the AIR core user-mode and separate virtual audio
  driver work from network protocol work.
- End each change with exact tests, missing prerequisites, known limitations,
  live processes/sockets left running and whether publication actually occurred.
