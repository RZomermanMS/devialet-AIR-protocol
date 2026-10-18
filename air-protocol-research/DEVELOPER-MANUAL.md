# Developer manual

## Layout and current implementation

Published `air-protocol-research/` is canonical; preserve its flat sibling-file
layout. Older root-level script copies are historical, not a second current
source. Read [AGENTS.md](../AGENTS.md) and [PROTOCOL.md](./PROTOCOL.md).
PowerShell scripts target Windows PowerShell 5.1 / .NET Framework with
embedded C# compiled by Add-Type. There is no solution/package build or
completed MA/ARM64 implementation.

| Files | Responsibility |
|---|---|
| Send-Mp3.ps1 | Local Media Foundation/NAudio decode wrapper; embedded Snd2 codec, PCM reader, startup, transport/repair/drain |
| Send-Playlist.ps1 | Per-track PowerShell process/session, stop/failure propagation |
| Common.ps1, Feedback.ps1 | Shared byte/CRC and Da/Df parsing helpers |
| Discovery.ps1, Find-Experts.ps1 | Passive capture, device inventory, readiness and routed endpoint |
| Decode-ReferenceBlocks.ps1 | Independent wire decoder; DefinitionsOnly mode |
| Test-PcmStreaming.ps1 | Actual reader class extraction, synthetic fixtures and optional complete source decode comparisons |
| Test-SenderWatchdog.ps1 | Actual sender compilation, health/identity/recovery/startup/cancel guards |
| Test-SenderIntegration.ps1 | Actual sender against independent loopback mock; decode/check every audio packet |
| Test-SenderCapture.ps1 | Streaming tshark capture validation, independent Dm decode and matching Df drain |
| Test-Lifecycle.ps1 | LIVE stop/suppress-next-track/reconnect check |
| Analyze/Compare/Fit helpers | Historical offline signal/capture analysis with private inputs |
| Play/Drop/Send-Minimal/Select-Wifi helpers | Historical LIVE operations; inspect first, not routine validation |

Do not dot-source the whole sender to reuse C#: its wrapper can play audio.
Existing offline tests extract the class definition through the PowerShell
AST without executing the wrapper.

## Decoder and transport constraints

PcmBlockReader uses a named native ReadPcm delegate, 65536-byte decoder staging
and an 800-byte wire-PCM buffer: 66336 application PCM bytes total, independent
of source length. Decoder internals and 400 encoded resend packets are extra.
Do not regress to whole-track buffering or direct 800-byte native resampler
reads: the latter omitted nine frames at a 48 kHz source EOF.

The callback consumer does not need Length/Position/seek, but the current
wrapper is local-file Media Foundation, not HTTP/live-radio ingestion.
Reads are synchronous and cannot be interrupted mid-call. Feedback and stop
polls run around calls; native decoder stalls can therefore affect pacing.
Busy-wait scheduling is research code, not a cross-platform async design.

Preserve explicit errors, exact duration/no-overread semantics, short-read
accumulation, partial-frame rejection, final padding, readiness and B/F drain.
The protocol reference documents the recovery/cache bounds and identity guards.

## Validation matrix

Run each script in a separate PowerShell process from the research directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-PcmStreaming.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SenderWatchdog.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SenderIntegration.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Feedback.ps1 -SyntheticOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Discovery.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FormatCoverage.ps1
```

These six are synthetic/loopback only, without physical Expert playback,
Wireshark, NAudio or retained captures. Watchdog/integration bind shared
loopback UDP 45455/45456: **run sequentially**, not parallel.
Expected current coverage: 48 reader fixtures; watchdog/startup/recovery
checks; 18 loopback cases; feedback 22 synthetic cases, discovery 22 and codec
10 fixtures. Test-Feedback without SyntheticOnly additionally requires the
specific retained CSV and runs eight captured-evidence assertions (30 total).
An explicit missing CsvPath still fails; SyntheticOnly is not an automatic
fallback and cannot be combined with CsvPath. The test writes a local JSON
result which must not be published.

| Validation | Additional requirements | What it proves |
|---|---|---|
| Six scripts above | PS5.1, .NET, available loopback ports | Implementation invariants and deterministic mock behavior |
| Test-PcmStreaming -Mp3 | NAudio and local source file | Complete decoded frames/hash equals 65536-byte native-read baseline at both rates |
| Test-SenderCapture | tshark, local capture, actual session/rate/frame count/endpoints | Complete transmitted blocks, CRC/PCM structure, exact resends/padding and observed final B/F |
| Reference/encoder/audio analyses | Specific retained captures/signals and script-specific dependencies | Claims about that supplied evidence, not universal behavior |
| Test-Lifecycle or senders | Explicit live approval, ready Expert, capture, source and dependencies | Actual receiver interaction; not acoustic fidelity |

Decoder changes should run the optional complete-file comparison, not just a
short excerpt. With operator-provided evidence:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-PcmStreaming.ps1 `
  -Mp3 'C:\Audio\test-track.mp3'

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SenderCapture.ps1 `
  -CapturePath 'C:\Evidence\air-run.pcapng' -ExpectedFrames 8903209 `
  -SessionId 40797 -Gen 30 -SampleRate 48000 `
  -SourceAddress 192.0.2.10 -ExpertAddress 192.0.2.20
```

Those frame/session numbers identify one historical run, not defaults for
arbitrary files. Use actual decoded frames and session from the current log.
Block count is ceil(frames/200), final counter `(blocks-1)*200`, padding
`blocks*200-frames`. The validator must reject incomplete captures; successful
decode of every received packet is insufficient if source frames are missing.

No fresh source/capture evidence is shipped. Missing evidence is a reported
prerequisite, never a reason to fabricate fixtures and relabel them observed.
Mock tests establish behavior under their assumptions, not new wire semantics.

## Integration roadmap

### Shared portable user-mode core

1. Extract codec/CRC, Da/Df parsing, startup/session state machine and repair
   into a portable component with deterministic timing and transport seams.
   Retain independent decoding and golden/synthetic vectors.
2. Separate cancellable source production from timed network work with bounded
   queues/backpressure, explicit underruns and structured lifecycle events.
3. Implement direct passive UDP discovery so the deployed integration does not
   depend on Npcap/tshark; account for broadcast domains and socket coexistence.
4. Instrument B/A/F, queue/cache occupancy, scheduler/native-read stalls and
   event timestamps. Investigate frozen-B/no-interval failures before claiming
   reliable long-run operation. Define bounded outage/reconnect policy and
   user-visible state, rather than silent restarts or relaxed watchdogs.
5. Validate natural EOF, stop while blocked, session transitions, outage
   recovery, long duration, Linux/ARM behavior and actual acoustic output.

### Music Assistant

Pin the exact MA version/commit and inspect its current PlayerProvider and
Player contracts. Implement one Expert player, passive discovery/status,
44100/48000 stereo PCM input, play/stop and explicit input selection semantics.
Map cancellation separately from source completion and transport failure.
Do not advertise native pause/flush/seek, gapless, sync groups, high rates or
native 24-bit support without implementing and verifying them.
HTTP/live streams, event-loop integration, packaging/configuration and actual
MA runtime validation are still to be built.

Public API references, moving main branches:
[PlayerProvider](https://github.com/music-assistant/server/blob/main/music_assistant/models/player_provider.py),
[Player](https://github.com/music-assistant/server/blob/main/music_assistant/models/player.py).
These are architecture references, not a pinned compatibility guarantee.

### Windows ARM64

First build/test the user-mode transport on physical Windows ARM64.
If system-wide audio capture is required, design a virtual endpoint and
bounded PCM handoff to a user-mode service; keep networking/session logic out
of the kernel where practical. Do not assume an x64 vendor driver works on ARM.

Separate work includes WDK/SDK setup, ARM64 builds, endpoint format negotiation,
clocking/latency/underruns, driver/service lifecycle, suspend/resume, recovery,
installation/uninstallation, signing and applicable validation/submission.
No ARM64 sender, virtual endpoint or signed driver exists in this repository.

Official references:
[ARM64 driver builds](https://learn.microsoft.com/en-us/windows-hardware/drivers/develop/building-arm64-drivers),
[universal audio / SysVAD](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/audio-universal-drivers),
[code signing](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-reqs).

## Agent customization

Repository-root [AGENTS.md](../AGENTS.md) provides always-on instructions.
VS Code additionally discovers:

- `.github/agents/air-integration.agent.md`: manually selected implementation
  role, scoped to the tested contract and offline-first development.
- `.github/prompts/validate-air.prompt.md`: `/validate-air` runs the six
  no-device suites sequentially and reports actual results.

No fixed model, credential, local evidence path, automatic live hook or
automatic publication is configured. Customization text is guidance, not
an OS security boundary; inspect scripts before running them.

## Publication and evidence hygiene

Publish reviewed research `*.ps1`, `*.md`, `.gitignore`, agent/prompt Markdown and
the generated SHA256SUMS.csv only. Do not recursively upload a research folder.
Exclude audio, captures, decoded data, JSON results, logs, dependencies,
archives, credentials and local machine/session paths. `.gitignore` is an
additional guard, not a replacement for an explicit upload allowlist.

Hash the exact publication copies after any path anonymization. Verify
PowerShell syntax, local Markdown links, YAML frontmatter and affected tests.
Compare against the current remote revision before publishing; do not overwrite
unexpected concurrent edits. Verify the resulting remote commit and file
contents before reporting uploaded. Include this trailer in commits:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

Keep dated successes and failures in [LONG-RUN.md](./LONG-RUN.md). Do not
erase history or infer an acoustic guarantee from a successful packet trace.
