# Offline AIR analysis execution plan

All work is offline. Inputs remain unchanged; no capture, playback, network transmission, process changes, installation, or third-party uploads. Runtime: Windows PowerShell 5.1/.NET (Python WindowsApps alias fails).

## Shared interfaces and ownership

Scripts are dot-sourceable PowerShell modules (`*.ps1`) without execution side effects. Input packet objects have TimestampRaw, Source, Destination, SourcePort, DestinationPort, PayloadLength, PayloadHex. Byte offsets are zero-based. Hex decoders reject odd length/nonhex. All numbers explicitly state byte order. Analysis output JSON is local only.

Coordinator exclusively owns `Common.ps1`, `Capture.ps1`, `Inspect-Air.ps1`, `Test-Integration.ps1`, `integration-results.json`, and this plan. Common functions: ConvertFrom-AirHex(string)->byte[]; Get-AirUIntBE(byte[],offset,width)->UInt64; Get-AirCrc16(byte[],count)->UInt16 (CCITT polynomial 1021/init FFFF); Assert-AirRange(byte[],offset,count). Workers may dot-source Common.ps1. Capture reader: Read-AirCapture(path)->objects including Kind/Reason and, for UDP, shared packet fields.

Audio worker exclusively owns `Audio.ps1`, `Test-Audio.ps1`, `audio-results.json`, `AUDIO.md`. Export ConvertFrom-AirDm(byte[]), Get-AirAudioAnalysis(packet[]); preserve uncertainty and do not produce PCM absent an established codec.

Feedback worker exclusively owns `Feedback.ps1`, `Test-Feedback.ps1`, `feedback-results.json`, `FEEDBACK.md`. Export ConvertFrom-AirDf(byte[]), ConvertFrom-AirDa(byte[]), Get-AirFeedbackAnalysis(packet[]). Df structural/CRC errors must reject; correlation remains a hypothesis unless demonstrated.

Monitor exclusively owns `MONITOR.md`; read-only artifact/test inspection with one initial checkpoint and one final handoff, no autonomous polling. Documentation worker exclusively owns `REPORT.md`; consolidate worker and integration evidence after coordinator handoff, no decoding or recursive delegation. Workers must not edit each other's files.

## Dependency-aware tasks and acceptance gates

| ID | Owner | Prerequisites | Executable work | Measurable acceptance |
|---|---|---|---|---|
| P0 | coordinator | none | Persist plan and verify runtime/input headers | Plan on disk; Python absence explicitly recorded; PowerShell selected |
| C1 | coordinator | P0 | Implement byte/CRC utilities and native-WiFi pcapng reader | Deterministic hex/range/BE/CRC tests; reject corrupt block lengths/truncation; account for every controlled capture frame |
| A1 | audio | P0 | Parse Dm, inspect encoding and unique-counter sequence | Synthetic short/magic/dedupe/reorder tests; measured capture counts, frame steps, lengths, body/transition analysis |
| F1 | feedback | P0 | Parse Df and Da; investigate correlation | Df length=41+4n/count/range/CRC tests including corrupt cases; Da status masks; controlled CRC totals; bounded range correlation |
| I1 | coordinator | C1,A1,F1 | Compose inspector; run workers and integration on original controlled/corrected controlled/baseline captures | Exact packet accounting; independent CSV match; deterministic tests all pass; original mislabeled input rejected explicitly; no source changes |
| M1 | monitor | P0 | Check plan/file ownership and initial blockers once | Artifact-backed checkpoint, not speculation |
| M2 | monitor | I1 | Read persisted results and report readiness/blockers | Matrix names exact files/test counts; no decoding duplication |
| D1 | documentation | P0 | Create report skeleton from plan and known provenance | Confidence vocabulary and evidence sources explicit |
| D2 | documentation | I1,M2 | Consolidate final findings and commands | Offset/order/confidence table, actual validation results, open questions, minimal next experiments |
| G1 | coordinator | I1,M2,D2 | Verify deliverables and close batch | Persisted working inspector/tests/report; claim audio decode only if real decoded samples establish tone near 997Hz and 3–7s bounds |

## Audio success / bounded blocker

Aspirational: establish a lossless/other codec from packet evidence, decode actual silence/tone, measure dominant tone near 997Hz and bounds near frames 144000/336000, documenting coverage and mixer effects. A failed codec hypothesis is not a decoder. If evidence is insufficient, ship validated transport/body inspector and explicitly block PCM/sender/MusicAssistant integration, naming the narrowest additional offline evidence or future controlled experiment needed.

## Execution commands

From this directory: `powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Audio.ps1`; `...\Test-Feedback.ps1`; `...\Test-Integration.ps1`; `...\Inspect-Air.ps1 -CapturePath '<corrected pcapng>' -OutputPath '.\inspection.json'`.

## Stop conditions

Each decoder worker performs a bounded single investigation and runs its focused tests. Monitor/documentation wait for a coordinator phase-handoff message rather than poll. No nested delegation by any worker. Coordinator integrates or records a precise blocker; no infinite retries and no success-shaped audio fallback.

## Executed gates and orchestration record

P0/C1/A1/F1/I1/M1/M2/D1/D2 completed. G1 closes with a validated offline inspector and an explicit audio-codec blocker, not a PCM-decoder claim. Actual persisted validation: audio 18/18, feedback 30/30, integration 28/28 (76 checks total). Both inspector invocations completed with exit 0. Controlled frame accounting is 1,180 = 1,176 UDP + 4 ARP; baseline is 2,495 UDP. All eight retained inputs have matching before/after SHA256 hashes in `integration-results.json`.

Runtime worker IDs:

| Role / phase | Runtime ID | Outcome |
|---|---|---|
| Audio | `567478fa-bdc4-4ca8-ac4f-3191e67cf43a` | Transport/body inspector and 18 checks; codec blocked |
| Feedback | `b964a189-8376-40c8-b06c-85c9a2d222af` | Structural/status parser and 30 checks |
| Monitor initial | `9605de2e-7b7d-4bd6-beab-1ea78bc4600a` | One initial inventory |
| Documentation initial | `c3ccf744-7111-4dca-b737-8bd405f67938` | Evidence/report skeleton |
| Monitor final handoff | `74ce0cb8-f6ca-4317-b838-336f5e2bb5b4` | One final artifact-backed checkpoint |
| Documentation final handoff | `27b13e24-92bc-45be-b36a-f867a7a43ef4` | Final report consolidation |

Tool limitation: `task` invocations were synchronous; `write_agent` rejected resuming sync child workers. No nonexistent background monitoring is claimed. Final monitor/documentation phase handoffs therefore used bounded new task invocations for those same roles; decoder workers were not relaunched. No worker recursively delegated and no autonomous long-lived monitor was launched. The feedback worker reported using PowerShell file writes because its child tool surface lacked patch support; coordinator-owned edits used `apply_patch`.

Coordinator integration strengthened audio deduplication to full payload fingerprints and tested equal bodies with different headers. Capture reader rejects unsupported/truncated inputs instead of quietly treating them as decoded data. `REPORT.md` and `MONITOR.md` contain final evidence and blockers. No PCM file, sender, or MusicAssistant integration was emitted.
