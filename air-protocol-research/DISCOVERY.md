# Passive Expert discovery and startup eligibility

## Upstream evidence

[Devimote](https://github.com/gnulabis/devimote), inspected at commit
`da31d64973e263b47f806285612711e631bde45c`, provides a dependency-free
`pydevialet_expert_nonpro` library, plus a separate GUI. Its backend is
GPL-3.0-or-later; its README is CC0-1.0. No upstream implementation is copied here.

Its status decoding confirms offsets already present in Feedback.ps1:
name at 19, fifteen input entries from 52 with stride 17, ASCII enabled flag,
power bit 0x80 at 307, mute bit 0x02 and input mask 0x3C at 308, raw volume
at 310. Our existing dB interpretation is `(raw - 195) / 2`.
Discovery uses source IP from the status datagram, not the name as a unique ID.

Upstream describes/tests 512-byte status frames, whereas our captures show
345-byte payloads. Both lengths now validate CRC at the actual trailing two
bytes. The 512-byte variant has synthetic coverage only on this machine.
Neither the upstream advertised status frequency nor packet size is treated
as universal firmware behavior.

Devimote does not implement AIR audio, multi-sender arbitration, a stream-ready
handshake or remote ownership locking. Its control commands are NOT used by
our discovery implementation.

## Implementation

`Discovery.ps1` reuses Feedback.ps1 and Common.ps1. `Find-Experts.ps1` passively
captures four seconds of UDP 45454/45455 traffic using dumpcap, then uses tshark
to recover endpoints/timestamps/payloads. It sends no discovery query, does not
bind status port 45454 or audio port 45456, and does not interfere with a status
listener such as Devimote. Temporary captures are removed in a finally block.
Capture/parse failures are explicit errors; bad status frames produce warnings.

The inventory tracks each IPv4 address separately, keeping its newest valid
CRC-checked status. Automatic sender selection requires exactly one matching
device (stale devices remain visible, but cannot pass readiness). Supply
`-ExpertAddress` or a unique `-ExpertName` if more than one is present.

Startup eligibility requires:

- Valid status received within two seconds of the end of observation.
- Power on and unmuted; no commands are sent to change either state.
- The selected input is enabled and matches the intended network input.
- No Dm-shaped traffic to that Expert during the observation window.
- No existing local UDP 45456 endpoint.

Auto input inference only recognizes enabled labels WiFi, Wi-Fi, Wi Fi,
Ethernet or AIR, case-insensitively, and only when exactly one matches.
Renamed or ambiguous inputs require `-NetworkInputIndex`; this is an explicit
operator assertion, not detection of input type. No input is switched.

Both sender prototypes run this preflight after opening/loading their audio,
immediately before binding/sending. They choose the discovered target address
and Windows route's source address rather than hard-coding the original host.
They bind UDP 45456 exclusively, so a bind conflict cannot silently become a
shared listener. Send-Mp3.ps1 now generates its own startup/header by default
and decodes incrementally; it does not need a reference capture. The historical
Send-Minimal.ps1 and explicit Startup=Captured path remain capture-dependent.

## Usage (Windows PowerShell 5.1)

Passive status observation only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Find-Experts.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Find-Experts.ps1 `
  -CaptureInterface 5 -ExpertAddress 192.0.2.20 -NetworkInputIndex 9
```

`CaptureInterface` is the dumpcap interface number, not necessarily the Windows
adapter index. Discovery is IPv4/broadcast-domain based; a wrong interface,
firewall, VLAN or wireless client isolation can prevent observation.
Sender parameters now also accept CaptureInterface, ExpertAddress, ExpertName
and NetworkInputIndex. Use their existing live-playback approval workflow;
do not run senders simply to test discovery.

Offline tests:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Discovery.ps1
```

## Coexistence boundary: startup guard, not full arbitration

Observed traffic blocks startup regardless of sender identity. We do not kill,
stop, disable or reconfigure official AIR. Merely finding its process is not
proof it is streaming, so a running but idle app is not blocked solely by name.

A passive capture cannot see every other host's unicast on switched/WiFi
networks. A quiet observation is NOT proof of global exclusivity. Status cannot
prove stream acceptance or audibility either. Keep official AIR streaming off.
Starting another sender after preflight is not yet handled; there is no remote
lease, continuous conflict monitor, automatic takeover or ownership guarantee.
The exclusive socket closes the local bind race, not remote races.

The long-run feedback-stall problem in LONG-RUN.md is separate and not fixed by
discovery. Runtime feedback/progress watchdogs, continuous status monitoring
and a conservative abort policy remain required before production coexistence
can be claimed.

## Validation on 18 October 2026

- Discovery tests cover status lengths/CRC, enabled inputs, age, power/mute,
  selection ambiguity, competing traffic, local port conflicts, and the sender's
  preflight wiring with mocked network/environment functions.
- Existing feedback regression tests: 30/30 passed.
- Both embedded sender C# implementations compile without transmitting.
- A real reference-capture sample supplied 19 valid status packets identifying
  `Devialet-WIFI` at `192.0.2.20`, powered on, unmuted, input 9 selected.
  Explicitly requesting input 10 correctly refused startup.
- A bounded passive live scan on interface 5 completed successfully but found
  zero status packets. Current live readiness and actual post-change playback
  were therefore NOT validated; no sender was started.
