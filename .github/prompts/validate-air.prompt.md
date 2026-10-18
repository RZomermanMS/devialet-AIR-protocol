---
name: validate-air
description: "Run the six synthetic and loopback AIR regression suites sequentially without a physical Expert, captures or audio."
agent: agent
tools: [read, search, execute]
---

Follow [AGENTS.md](../../AGENTS.md) and the
[validation matrix](../../air-protocol-research/DEVELOPER-MANUAL.md#validation-matrix).
From the canonical air-protocol-research directory, run these scripts
sequentially, each using a fresh
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File` process:

1. Test-PcmStreaming.ps1, without -Mp3
2. Test-SenderWatchdog.ps1
3. Test-SenderIntegration.ps1
4. Test-Feedback.ps1 -SyntheticOnly
5. Test-Discovery.ps1
6. Test-FormatCoverage.ps1

Do not run other scripts just because their names start with Test.
Do not launch live playback/capture, install dependencies or change device,
network or driver configuration. Watchdog/integration share loopback ports;
report a bind conflict rather than terminating an unknown process.

Report each command's exit/result, test counts where emitted, missing
prerequisites and any cleanup failures. Preserve full failure details.
Mock passes do not establish acoustic fidelity or physical long-run success.
