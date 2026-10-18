# Devialet AIR protocol research

Current handoff: **18 October 2026**. Experimental Windows PowerShell/C#
sender and independently checked protocol research for Devialet Expert AIR.
This is not a released Music Assistant provider, an ARM64 driver, a complete
AIR specification or a production-reliability claim.

## Manuals and navigation

| Start here | Contents |
|---|---|
| [Operator manual](./OPERATOR-MANUAL.md) | Requirements, dependency setup, safe playback, stop and troubleshooting |
| [Developer manual](./DEVELOPER-MANUAL.md) | Code map, offline validation, integration architecture and publication |
| [Protocol reference](./PROTOCOL.md) | Tested packet layout, startup, feedback, repair and completion |
| [Latest results](./LONG-RUN.md) | Complete successes, unresolved failures, exact frame counts and hashes |
| [Sender detail](./SENDER-TEST.md) | Bounded PCM, fault harness and supported integration contract |
| [Agent instructions](../AGENTS.md) | Repository-wide safety, evidence and coding rules |

In the published repository, **air-protocol-research/ is canonical**.
Older script copies at repository root are historical, not another supported
source tree. Do not edit, run or package those stale copies as current code.
Older investigation documents are retained for provenance; dated current
follow-ups and the manuals above take precedence over superseded hypotheses.
Historical machine paths and addresses are examples, not setup instructions.

## Current status

- Standalone sender with generated silence startup, automatic nonzero sessions,
  readiness checks and validated session/source/generation/CRC feedback.
- Stereo PCM16 input at 44100 or 48000 Hz, encoded in 200-frame AIR blocks
  using signed-24-bit numerical channel values and empirical gain scaling.
  This is **not native PCM24, calibrated full-scale or bit-perfect output**.
- Relative-F missing-interval repair, bounded 400-packet cache, paced resends,
  two-second feedback/progress watchdogs and final B/F drain.
- Incremental local-file decoding uses fixed 66336-byte application PCM
  staging. Separate sessions support sequential playlists and explicit stop;
  no remote flush, gapless playback or native pause/resume.
- Final-code complete 48 kHz Track1: **8903209 source frames, 44517 blocks**,
  12 resends, independently validated complete capture and partial tail.
- All 18 loopback fault cases pass; stop/reconnect, watchdog, codec, parser,
  reader and discovery regressions pass.

**Reliability remains open.** A prior 19-minute Qmusic run completed with
generated startup and incremental decoding. After the final decoder staging
fix, a new whole-Qmusic attempt and one 48 kHz attempt stalled and correctly
failed; the fresh-session 48 kHz retry completed. Their cause is unresolved.
The successful 19-minute run predates the staging fix. Complete offline PCM
hashes match at both rates, but there is no final-code 19-minute live pass.
Acknowledgements and PCM equivalence do not prove glitch-free acoustic output.

## First use

Read the [operator manual](./OPERATOR-MANUAL.md) before sending audio. The
current wrapper needs Windows PowerShell 5.1, Windows Media Foundation,
NAudio 2.2.1 and Wireshark/Npcap. Neither official AIR nor a reference capture
is needed for the normal generated-startup path.

For **offline, no-device validation**, run from this research directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-PcmStreaming.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SenderWatchdog.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SenderIntegration.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Feedback.ps1 -SyntheticOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Discovery.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FormatCoverage.ps1
```

Run socket tests sequentially: they share loopback UDP ports. Other `Test-*`
scripts can require private captures, NAudio or live hardware; the filename
alone does not make a script safe/offline.

## Next implementation

Enough evidence exists to start a constrained **Music Assistant provider and
shared user-mode AIR transport**. First implement cancellable PCM ingestion,
discovery/status, play/stop, explicit error events and a deliberate outage
recovery policy; pin the Music Assistant version and test the actual runtime.
Do not expose unsupported high-rate/native-24-bit, sync-group or flush features.

For **Windows ARM64**, port and test the user-mode transport first. A
system-wide virtual audio endpoint is an additional WDK, signing and physical
ARM64 validation effort; no driver or ARM64 binary has been built here.
See the [developer roadmap](./DEVELOPER-MANUAL.md#integration-roadmap).

## Evidence and licensing

Audio, packet captures, decoded samples, local logs, credentials and downloaded
dependencies are deliberately not published. Published source and summaries
do not allow someone without the retained evidence to repeat capture-based
claims. The [test matrix](./DEVELOPER-MANUAL.md#validation-matrix) separates
synthetic tests from evidence-dependent and live checks.

No new license is asserted by this handoff. Review repository ownership and
licensing before redistribution. Public upstream references are attributed in
the relevant documents; no vendor driver binaries or upstream implementation
are included. `SHA256SUMS.csv` lists hashes of the published source/docs
package using repository-relative paths, excluding the checksum file itself
and legacy root-level copies.
