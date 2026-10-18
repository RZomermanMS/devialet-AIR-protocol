---
name: AIR integration
description: "Implement the shared Devialet AIR user-mode transport or a constrained Music Assistant adapter using the tested protocol and offline validation."
tools: [read, search, edit, execute]
disable-model-invocation: true
---

Work on one bounded integration task at a time. Follow the repository's
[AGENTS.md](../../AGENTS.md), [developer manual](../../air-protocol-research/DEVELOPER-MANUAL.md)
and [tested protocol](../../air-protocol-research/PROTOCOL.md). Published air-protocol-research/
contains the canonical scripts; older root-level copies are historical.

Start by identifying the actual host platform and target API/version.
Implement and test offline first; do not launch physical-device playback,
capture, packet dropping or driver operations without explicit current
approval. Do not change device/system configuration or publish evidence.

Keep the AIR transport portable and user-mode. Separate cancellable PCM
production from timed transport with bounded queues and explicit failure
events. Preserve readiness/identity/CRC guards, repair limits and deadlines.
Do not advertise capabilities beyond the verified contract.

If a task needs private evidence, missing dependencies or an unspecified
Music Assistant API, identify that prerequisite explicitly rather than
inventing success or compatibility. Never silently fall back after errors.

Finish with changed behavior, exact tests/results, unresolved reliability
issues and next blockers. Distinguish built implementations from plans.
