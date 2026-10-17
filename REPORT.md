# Offline AIR protocol analysis — final report

**Later update:** the reference-WAV analysis now has a narrow sample decoder that
recovers a measured 997 Hz tone. See [block decoder findings](./BLOCK-DECODER.md).
The codec-blocked statements below describe the earlier multi-agent batch, not
the later result. General codec coverage, bit-exact recovery and sender readiness
remain unproven.

Final consolidation: 17 October 2026. **The offline transport/feedback inspector is delivered and validated; the audio codec is not established.** This is not a complete protocol decode, PCM decoder, sender, or MusicAssistant integration.

## Scope, provenance, and confidence

All work used retained local files. No live capture, playback, network transmission, device changes, installation, or third-party uploads were performed. Windows PowerShell `5.1.26100.9711`/.NET was used because the Python WindowsApps alias was unavailable.

Inputs reside in:

`C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09`

Deliverables and this report reside in:

`C:\Users\rzome\.copilot\session-state\39c990a0-2ab4-4967-b74a-4a62955476fa\files\air-protocol-analysis`

The original `air-session.pcapng` and `air-baseline.pcapng` label native WiFi frames as linktype 1. Both originals are explicitly rejected by integration tests. The retained corrected `air-session-wifi.pcapng` and `air-baseline-wifi.pcapng` use linktype 105 and are the working inputs. They are distinct retained files, not silent mutations of the originals.

The supplied controlled-stimulus description is 48 kHz PCM16 stereo, identical channels: three seconds silence, four seconds 997 Hz at -60 dBFS, three seconds silence, without volume changes. This is stimulus provenance, **not a measurement recovered from these packets**.

Confidence vocabulary:

* **Observed / high:** bytes, counts, invariants, or reproducible validation results in the retained evidence.
* **Inferred / moderate:** interpretation supported by structure or stimulus association, not independently established.
* **Hypothesis / low:** plausible but unverified interpretation.
* **Unknown:** evidence does not establish the answer.

Numeric offsets below are zero-based **within the UDP payload**, not capture-frame offsets. Multibyte payload integers are big-endian (BE); pcapng container integers are little-endian.

## Evidence and acceptance

This report consolidates `PLAN.md`, `AUDIO.md`, `FEEDBACK.md`, `integration-results.json`, `audio-results.json`, `feedback-results.json`, `controlled-inspection.json`, `baseline-inspection.json`, and `MONITOR.md`. Parser implementations were consulted to disambiguate exact offsets and acceptance conditions. Persisted JSON is the source of numerical results; planned acceptance criteria are not substituted for results.

| Suite | Persisted result | Evidence |
|---|---:|---|
| Integration | 28/28 passed, 0 failed | `integration-results.json`, generated `2026-10-17T12:03:56.3020057Z` |
| Audio inspection | 18/18 passed | `audio-results.json`: `TestStatus=Passed`, `FocusedTestCount=18` |
| Feedback | 30/30 passed, 0 failed | `feedback-results.json`, generated `2026-10-17T12:00:38.4208868Z` |
| **Total** | **76/76 passed** | Validation of the inspector and tested invariants, not of a codec |

Integration covers CRC and integer helpers, malformed hex/ranges, synthetic WiFi/IPv4/UDP extraction, unsupported/truncated packet rejection, pcapng integrity/interface rejection, full-payload deduplication, rejection of both mislabeled originals, exact capture accounting, controlled CSV agreement, baseline feedback acceptance, and preservation of all eight inputs. Feedback tests include corrupt count/length/CRC cases and ordering flags. Audio tests cover transport/body inspection rather than decoded audio.

The documentation phase consumed these persisted results; it did not rerun the suites or manufacture fresh execution/exit-status evidence.

## Capture accounting

| Measure | Controlled corrected capture | Baseline corrected capture |
|---|---:|---:|
| Captured frames | 1,180 | 2,495 |
| UDP records | 1,176 | 2,495 |
| Other frames | 4 ARP, EtherType `0x0806` | 0 |
| `Dm` records | 951 | 1,833 |
| `Df` records, CRC/count/length valid | 162 | 526 |
| `Da` records, CRC valid | 63 | 136 |
| Rejected feedback records | 0 | 0 |

Thus controlled `951 + 162 + 63 = 1,176 UDP`, and `1,176 + 4 = 1,180 frames`; baseline `1,833 + 526 + 136 = 2,495 UDP/frames`. The 1,176 controlled UDP records match the existing CSV exactly for payload, timestamp, source/destination address, and ports.

The **full corrected baseline pcapng was parsed**, producing `baseline-inspection.json`; analysis is not limited to baseline CSV prefixes. Feedback CRC totals cover all 225 controlled and 662 baseline feedback records. There is no corresponding verified Dm checksum claim.

## Implemented parser scope

`Capture.ps1` reads little-endian pcapng version 1 section/interface/enhanced-packet blocks, linktype **105 native WiFi**, and default or explicitly specified microsecond timestamp resolution. Timestamp offsets, other resolutions/linktypes, legacy/simple packet blocks, unknown interfaces, invalid block sizes/trailers, truncation, and snaplen-truncated packets are rejected. Unneeded non-packet block types are skipped.

Supported payload extraction is unencrypted, unfragmented native WiFi data/QoS data, the implemented address/QoS/HT header variants, LLC/SNAP `AA AA 03 00 00 00`, and unfragmented IPv4 UDP with consistent IP/UDP lengths. Other WiFi types/subtypes, encrypted/fragmented WiFi, A-MSDU aggregation, unsupported LLC headers, malformed IPv4 headers, IPv4 UDP fragments, and invalid UDP lengths are rejected rather than guessed or reassembled. Non-IPv4 EtherTypes are returned and counted as `NonIPv4`; non-UDP IPv4 is classified `NonUDP`. This is not a general-purpose packet decoder. No independent IPv4/UDP checksum validation is claimed.

`ConvertFrom-AirDm` validates magic and minimum length and preserves an opaque remainder. `ConvertFrom-AirDf` rejects null, short, wrong-magic, inconsistent-length/count, and bad-CRC payloads. Invalid interval ordering is **flagged, not rejected**. `ConvertFrom-AirDa` requires exact length, magic, and CRC. `Get-AirFeedbackAnalysis` collects malformed-feedback rejections rather than aborting the whole analysis.

## Dm layout and audio transport evidence

### Exact implemented layout, with semantic confidence

| Offset | Width | Order | Parsed/observed field | Confidence and qualification |
|---|---:|---|---|---|
| 0–1 | 2 | bytes | Magic `44 6D` (`Dm`) | Observed / high |
| 2–4 | 3 | opaque | Uninterpreted bytes | Unknown |
| 5–6 | 2 | BE comparison | Candidate session value `0x11BE` in controlled Dm | Equality with Df bytes 4–5 observed / high; session meaning inferred |
| 7–10 | 4 | opaque | Uninterpreted bytes | Unknown |
| 11 | 1 | byte | Mode discriminator: controlled `02`, baseline `03` | Values observed / high; mode semantics unknown |
| 12–19 | 8 | BE64 | Counter (`SampleCounter` in API) | Numeric extraction/grid observed / high; sample-position interpretation inferred |
| 20–21 | 2 | BE16 | Count (`SampleCount` in API), controlled value 200 | Value observed / high; sample/frame-count interpretation inferred |
| 22–end | variable | opaque | Preserved `Body` | **Candidate boundary only**; codec/framing boundary unknown |

The API's sample-oriented names do not establish a codec, sample format, channel count, or sample rate. Bytes 4–5 of controlled Dm are `0x0011`, not `0x11BE`; the observed cross-message equality uses **Dm 5–6 versus Df 4–5**.

### Controlled sequencing and duplicates

* 951 Dm observations contain **746 unique counter positions** and **205 additional duplicate occurrences**; 163 positions are repeated.
* All 205 duplicate occurrences have identical **full UDP payloads**, with zero conflicts. Integration specifically tests different headers with identical bodies so body-only fingerprints cannot silently merge distinct payloads.
* There are **336 adjacent capture-order counter decreases**. This measures order in the retained capture, not sender order or a demonstrated network cause.
* Observed counter range is 4,600–478,600 on a 200-unit grid: 2,371 possible positions, 746 observed, **1,625 absent**.
* Duplicate observations are not proof of retransmissions. Missing observed positions are not proof of on-wire packet loss.

Baseline full-payload results contain 1,833 unique Dm counters, no duplicate occurrences, and no capture-order decreases; range 17,203,400–18,644,200, with 5,372 absent positions on the analysis grid. Different modes and body sizes do not by themselves identify different codecs.

### Body-size observations and bounded rejected hypotheses

| Controlled UDP payload bytes | Remainder bytes from 22 | Packets | Remainder bytes / candidate count 200 |
|---:|---:|---:|---:|
| 166 | 144 | 650 | 0.720 |
| 614 | 592 | 3 | 2.960 |
| 664 | 642 | 2 | 3.210 |
| 714 | 692 | 296 | 3.460 |

At exactly the candidate offset 22, an entire unframed block of 200 PCM16 stereo frames would require 800 bytes, PCM16 mono 400 bytes, and PCM24 stereo 1,200 bytes. The tested candidates (`PCM16LE stereo`, `PCM16LE mono`, `PCM24BE stereo`) match **0/951** controlled packets by this fixed-size test. This rejects only those complete unframed layouts **at that boundary**. It is not an endian/sample decode, and does not exclude framed, packed, compressed, differently bounded, or embedded PCM.

Counter-sorted payload-length transitions:

| Counter pair | Payload-length transition |
|---|---|
| 141,600 → 142,800 | 166 → 614 |
| 143,000 → 143,400 | 614 → 664 |
| 143,600 → 143,800 | 664 → 714 |
| 332,200 → 334,400 | 714 → 614 |
| 334,400 → 334,600 | 614 → 166 |

These transitions are observations; their association with the expected 144,000–336,000 stimulus interval, including fades, is an inference. Gaps and possible mixer effects prevent sample-level timing claims. Baseline payloads span 13 observed lengths from 1,012 to 1,312 bytes, documented in the full baseline JSON.

**No actual sample decoding, PCM file, channel interpretation, recovered silence/tone/silence waveform, spectral analysis, or 997 Hz measurement was produced.** RTP and RAOP identification are not established.

## Df layout, validation, and correlation

For `n` intervals, payload length `L = 41 + 4n`.

| Offset | Width | Order | Field | Confidence |
|---|---:|---|---|---|
| 0–1 | 2 | bytes | Magic `44 66` (`Df`) | Observed / high |
| 2–3 | 2 | opaque | Uninterpreted | Unknown |
| 4–5 | 2 | BE16 | Candidate session, controlled `0x11BE` | Value/equality observed / high; meaning inferred |
| 6–9 | 4 | opaque | Uninterpreted | Unknown |
| 10–17 | 8 | BE64 | `Field10` | Extraction observed / high; meaning unknown |
| 18–25 | 8 | BE64 | `Field18` | Extraction observed / high; meaning unknown |
| 26–36 | 11 | opaque | Uninterpreted | Unknown |
| 37–38 | 2 | BE16 | Interval count `n` | Observed / high; validated against length |
| `39 + 4i` | 2 | BE16 | Interval `Start`, `0 ≤ i < n` | Structure observed / high; units/meaning unknown |
| `41 + 4i` | 2 | BE16 | Interval `End` | Structure observed / high; units/meaning unknown |
| `L−2`–`L−1` | 2 | BE16 | CRC16 over bytes 0 through `L−3` | Observed / high |

CRC uses polynomial `0x1021`, initial `0xFFFF`; the standard `123456789` vector yields `0x29B1`. Stored feedback checksums are big-endian. The same algorithm applies to Da.

Controlled Df has 61 distinct lengths and up to 90 intervals. All 162 are structurally valid and their intervals satisfy `Start ≤ End` and each next `Start > previous End`. Synthetic unordered/overlapping intervals return `IntervalsOrdered=false` rather than rejection; do not mistake the observed ordering invariant for a parser hard requirement.

Controlled `Field10` is nondecreasing, 11,999–216,799; `Field18` is constant 11,800 (`59 × 200`). For all **161 nonempty** Df records:

* first interval start equals `Field18 / 200 + 1`;
* `(Field10 + 1) / 200` is at least the last interval end.

These are exact numeric invariants in this capture, not an established feedback vocabulary. The bounded correlation assumes interval values are block indices. It measures:

| Metric | Controlled result |
|---|---:|
| Interval positions seen in Dm before Df | 19,013 |
| Seen only after Df | 8,093 |
| Never seen | 14,095 |
| `P(seen before Df | in interval)` | 0.461 |
| `P(seen before Df | in gap)` | 0.430 |

This weak difference does not discriminate acknowledgments, missing ranges, or retransmission requests. A playout/consumed-position interpretation of Field10 is only a hypothesis. Sparse capture and capture-order reversals confound causal interpretation.

All 526 baseline Df records have zero intervals (one length, 41 bytes), so the interval correlation is unavailable there (`Confidence=none`, insufficient data). Baseline full bytes are available; absence of intervals, not prefix-only access, is the limitation.

## Da layout and decoded status

Da payload length is exactly **345 bytes**.

| Offset | Width | Order | Field / implemented interpretation | Confidence |
|---|---:|---|---|---|
| 0–1 | 2 | bytes | Magic `44 61` (`Da`) | Observed / high |
| 2–18 | 17 | opaque | Uninterpreted | Unknown |
| 19–50 | 32 | ASCII | Device name, trailing NUL/spaces trimmed | Extraction observed / high |
| 51 | 1 | opaque | Uninterpreted | Unknown |
| `52 + 17i` | 1 | byte | Input flag, `0 ≤ i < 15` | Extraction observed / high; flag meaning unknown |
| `53 + 17i` | 16 | ASCII | Input label, trailing NUL/spaces trimmed | Extraction observed / high |
| 307 | 1 | mask | PowerOn = `(byte & 0x80) != 0` | Mask tested / high; status interpretation implemented |
| 308 | 1 | masks | Muted = `(byte & 0x02) != 0`; channel = `(byte & 0x3C) >> 2` | Masks tested / high; status interpretation implemented |
| 309 | 1 | opaque | Uninterpreted | Unknown |
| 310 | 1 | byte | VolumeRaw; volume dB = `(raw − 195) / 2` | Formula tested; physical scale not independently swept |
| 311–342 | 32 | opaque | Uninterpreted | Unknown |
| 343–344 | 2 | BE16 | CRC16 over first 343 bytes (0–342) | Observed / high |

The fifteen 17-byte input records occupy bytes 52–306. Controlled Da reports one status: **Devialet-WIFI, power on, unmuted, channel 9, −28 dB** under these masks/formula. The baseline's last status agrees. Channel 9 corresponds to `WiFi` in the zero-based decoded label list; broader input-selection semantics were not experimentally varied.

All controlled 63/63 and baseline 136/136 Da CRCs pass. Validation of the status parser is not a claim that every Da byte has known semantics.

## Reproduction commands and artifacts

The following reproduce the offline workflow; do not treat these printed commands as a new execution in the documentation phase.

```powershell
Set-Location 'C:\Users\rzome\.copilot\session-state\39c990a0-2ab4-4967-b74a-4a62955476fa\files\air-protocol-analysis'
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Audio.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Feedback.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Inspect-Air.ps1 -CapturePath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-session-wifi.pcapng' -OutputPath '.\controlled-inspection.json'
powershell -NoProfile -ExecutionPolicy Bypass -File .\Inspect-Air.ps1 -CapturePath 'C:\Users\rzome\.copilot\chats\039f3399-aee8-46c9-a98f-2021da23cf09\air-baseline-wifi.pcapng' -OutputPath '.\baseline-inspection.json'
```

| Deliverable | Purpose |
|---|---|
| `Common.ps1` | Strict hex/range/BE integer/CRC utilities |
| `Capture.ps1` | Supported pcapng/native-WiFi/IPv4/UDP reader |
| `Audio.ps1` | Dm counter, duplicate, body-size and transition inspection; no PCM |
| `Feedback.ps1` | Df/Da structure, CRC, masks, bounded correlation |
| `Inspect-Air.ps1` | Composed offline inspector producing JSON |
| `Test-Integration.ps1`, `Test-Audio.ps1`, `Test-Feedback.ps1` | 28, 18, and 30 focused tests respectively |
| `integration-results.json`, `audio-results.json`, `feedback-results.json` | Persisted suite evidence |
| `controlled-inspection.json`, `baseline-inspection.json` | Full corrected-capture analysis results |
| `PLAN.md`, `AUDIO.md`, `FEEDBACK.md`, `MONITOR.md`, `REPORT.md` | Plan, specialized findings, monitor checkpoints, final consolidation |

### Input preservation

The integration test **All eight original inputs unchanged throughout integration** passes. `InputSHA256` records:

| Retained input | SHA-256 |
|---|---|
| `inspect-air-capture.ps1` | `92595AC17AE0AEFD56BA43C326D3E64D5FF100389CDA3BAB7566C05F5A92C242` |
| `air-session-wifi.pcapng` | `6F53E2056F15D4846D30C5B4A66A5871AD20B73224D933DB3622D76509B31E5D` |
| `air-session-packets.csv` | `BDBC89D4319F50BBEAD46037C4C23B783F8DE40FCD4C69DFB1236BDB573A6A6D` |
| `air-session-test.log` | `0790A7D34E36EEBAB0518DF945823EB1AC807CC49F5A0083A894696F331BB27B` |
| `air-baseline-wifi.pcapng` | `7826BA4D4AFFAE22C934B284C20E5D7DC2CD2E56D0CC7130922516F2E4659590` |
| `air-baseline.pcapng` | `36E99F94FF36B484D1CE535F9045520460A96ACE7DC88D17E00A2E6F1A1D4044` |
| `air-session.pcapng` | `DB63C7AE4D047E58FC4351DCE2E4DB540FC741731CED3B40481E5CD5B703C930` |
| `air-baseline-packets.csv` | `3CAC3763AB814382796E1F04AF40CED4CE7D1913606EE269FB4DF9770A8B6B0D` |

This preservation claim is scoped to the integration interval; documentation did not independently rehash the inputs.

## Limitations and smallest next experiments

1. **Codec/framing blocker:** bytes from 22 remain opaque, and sample-counter/count interpretations are inferred. First seek an offline sender/codec specification or an already retained contiguous full-payload segment spanning a stable part of the known 48 kHz stimulus. Test one explicit framing/codec hypothesis with a bounded byte budget. Promote it only after real sample decoding and reproducible tone/coverage measurements; never emit fallback PCM.
2. **Only if offline evidence is insufficient:** propose a short, contiguous full-payload controlled recording with the same known silence/tone stimulus, fixed settings, and documented capture coverage. **This experiment was not performed and requires new user authorization before any live capture/playback/device/network operation.**
3. **Feedback semantics:** after coverage is established, compare Df interval membership against complete observed block positions around a single controlled condition change. Do not deliberately induce loss or change live settings without authorization. Require evidence distinguishing acknowledged from missing ranges before implementing retransmission logic.
4. **Status semantics:** an authorized, separate single-variable status change could validate one channel/mute/volume mapping at a time. Current tests validate masks/formulas, not a complete physical-control sweep.
5. **Integration remains blocked:** no PCM decoder, sender, MusicAssistant integration, full protocol identification, sample-level 3–7 second bounds, or measured 997 Hz recovery is delivered.

## Finite lifecycle and final outcome

The monitor recorded one initial inventory and one final phase-handoff checkpoint. Original worker task calls were synchronous; `write_agent` continuation handoffs were rejected rather than resuming those completed calls. Final monitoring and documentation used finite follow-up task calls in the same roles, not recursive delegation or autonomous polling. No watcher, repeated retry loop, or live operation is scheduled.

**Completed:** persistent, tested offline capture/transport/body and feedback/status inspection, exact capture accounting, input-preservation evidence, and this final report. **Unresolved:** codec/sample decoding and feedback interval meaning. These explicit blockers preserve the distinction between useful partial protocol structure and a fully decoded audio protocol.
