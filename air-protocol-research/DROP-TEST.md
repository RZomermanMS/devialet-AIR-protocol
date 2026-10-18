# Controlled single-block drop test

## Later interval mapping (2026-10-18)

The historical unresolved interval interpretation below is superseded for
the tested captures by `counter = F - (F % 200) + 200 * intervalIndex`.
F is the big-endian field at offset 26. Across six official loss captures,
the first predicted counter equals B+200 in all 22 interval reports; 21
have a matching outbound packet within 250 ms. The known adjacent-pair
example maps F=230841 and [246,247] to counters 280000 and 280200.
See FORMATS.md and Test-SenderWatchdog.ps1 for fixtures and safety limits.
This supports a relative 200-frame-block interpretation, not a complete
specification for counter wrap/reset, other block sizes or receiver playout.
Live exact-recovery tests recovered some requests before F reached their
counters, but sustained Qmusic runs still stalled; see LONG-RUN.md.

Date: 2026-10-17. Approved by the user. Volume untouched. Reference tone `air-test-48k16-stereo-997hz.wav`.

## Method

* Sender-side capture: Wireshark `dumpcap` (Npcap) on the Wi-Fi adapter, filter `host 192.0.2.20`, file `air-dumpcap-drop.pcapng`. Npcap captures below the WFP layer, so a packet dropped by WinDivert does not appear in the capture.
* Drop: `Drop-OneBlock.ps1` (WinDivert 2.2.2, elevated) discarded only the **first outbound `Dm` with counter 240000** (flow 192.0.2.10:45456 -> 192.0.2.20:45455) and forwarded everything else unchanged. Log: `drop-test.log` (seen 2436, forwarded 2435, dropped 1).
* The WinDivert driver service was removed afterwards.

## Observed sequence (capture times in seconds)

| Frame | t | Event |
|---|---|---|
| 1530 | 13.0962 | `Dm` counter 239800 |
| 1531 | 13.1009 | `Dm` counter **240200** (240000 absent; deliberately dropped) |
| 1532-1540 | 13.111-13.141 | `Dm` 240400 ... 242000 continue in order |
| 1541 | 13.1480 | **`Df` from Expert**: A=241399, B=239800, interval count 1, interval `[246-246]` |
| 1542 | 13.1515 | **`Dm` counter 240000 (resend)**, 3.5 ms after the `Df` |
| 1543 | 13.1516 | `Dm` 242200 (stream continues) |

Every other `Df` in the surrounding 0.25 s has interval count 0. Counter 240000 appears exactly once on the wire (the resend). The stream is otherwise gap-free.

## Conclusions

* **Established (causal):** a missing `Dm` block causes the Expert to send a `Df` with a non-empty interval list, and the sender resends that exact block (same counter), about 3.5 ms after the `Df` and about 51 ms after its original slot.
* **Established:** in `Df`, B stays at the last contiguous block start (239800) while a block is missing; with no loss B trails the newest block by one block and the interval count is 0.
* **Not resolved:** what the 16-bit interval value 246 measures. It is not counter/200 (1200). It may be a modular block or sequence index; one data point is not enough. Next step: repeat with different targets (e.g. 120000, 360000, two adjacent blocks) and fit the mapping.
* **Not tested:** multiple lost blocks, repeated loss of the resend, loss of `Df` packets, and resend timing limits (the sender must handle a resend request for blocks far in the past).

## Follow-up run: eight drops in one session (inconclusive, session wedged)

`Drop-Blocks.ps1` armed targets 120000, 200000, 280000, 280200 (adjacent pair), 320000, 320800 (separated pair), 360000, 420000. Capture: `air-dumpcap-multi.pcapng`.

* Dropped: 120000, 200000, 280000, 280200. The sender then **stopped at counter 296200** (dropper `maxCounter 296200`), so 320000 and later were never sent. Dropper log `drop-multi.log`.
* Counters 120000, 200000, 280000, 280200 were **never resent**, unlike the single-drop test.
* The Expert's feedback was abnormal before any drop: 122 of 123 `Df` carried one interval `[2-3]` with A stuck at 2399 and B at 200 from t=2.2 s (the clean capture has none), and `Df` stopped entirely after t=8.2 s.
* Afterwards AIR was no longer streaming (a clean no-drop run captured 0 `Dm`), so the session needs the Expert re-enabled in the AIR tray menu.

Conclusion: this run does not support or contradict the resend model. The abnormal `Df` before the first drop points to a bad session start rather than to the drops, but that is not proven. It also shows the risk of dropping several blocks per session. Repeat with one drop per session, and check a clean start (no `Df` intervals before the first drop) before arming.


## Second single-drop run (counter 120000, clean session)

Capture `air-drop-120000.pcapng`, dropper log `drop-multi.log` (seen 2548, forwarded 2547, dropped 1; WinDivert removed afterwards).

| Frame | t (s) | Event |
|---|---|---|
| 983 | 10.6231 | `Dm` 120800 |
| 984 | 10.6263 | `Df`: A=120799, B=119800, 1 interval `[248-248]` |
| 985 | 10.6284 | `Dm` **120000** (resend, the only copy on the wire), 2 ms after the `Df` |
| 986 | 10.6285 | `Dm` 121000, stream continues to counter 479200 |

* **Repeat of the first result:** one dropped block gave one single-block interval, then exactly one resend of that counter about 2 ms later. Two independent single drops (240000, 120000) now behave the same.
* **Interval value:** 246 (counter 240000) and 248 (counter 120000). It is **not** a function of the counter (block index would be 1200 and 600) and not a simple wrap of it, so the earlier idea that it is a block index is rejected. In both cases B = last contiguous block start.
* **New field:** the `Df` has a third BE64 at payload offset 26 (0x1135f = 70495 here) that the parser did not name; it may help explain the interval and is worth fitting.
* **Start-up bursts:** the first ~0.5 s of this session had many interval lists (`[7-12]`, `[14-23]`, ... with B=1200..2600), i.e. the Expert reports initial gaps before steady state; the clean `air-dumpcap-ref` capture had none. Start-up gap handling must be implemented in a sender.
* Still untested: adjacent and separated pairs, a dropped resend, dropped `Df`.

## Adjacent-pair run (counters 280000 and 280200, clean session)

Capture `air-drop-pair.pcapng`; dropper saw 2 targets and dropped both; WinDivert removed afterwards.

| Frame | t (s) | Event |
|---|---|---|
| 1773 | 14.1940 | one `Df`: A=280799, B=279800, **one interval `[246-247]`**, field at offset 26 = 230841 |
| 1774 | 14.1959 | `Dm` **280000** (resend) |
| 1775 | 14.2003 | `Dm` **280200** (resend) |

* Both lost blocks appear once each on the wire (the resends), in ascending order, about 1.9 ms and 6 ms after the `Df`. Stream continues to counter 480000.
* **Adjacent lost blocks are merged into one interval** (`246-247`, a range of two consecutive values) rather than listed twice, so interval endpoints are consecutive indices, not byte or counter values.
* The first interval value was 246 for counters 240000 and 280000 and 248 for 120000, so the index is not counter-proportional. It could be a wrapped or time-based index; more positions are needed (and the offset-26 field, 70495 / 230841, has not been fitted).
* Clean start this time: no `Df` with intervals before the drop.
* Still untested: separated pair, dropped resend, dropped `Df`.

## Separated-pair run (counters 320000 and 320800, four blocks apart, clean session)

Capture `air-drop-sep.pcapng`; both targets dropped; WinDivert removed afterwards.

| Frame | t (s) | Event |
|---|---|---|
| 1973 | 15.0061 | `Df`: A=320799, B=319800, one interval `[237-237]`, offset-26 field 272671 |
| 1974 | 15.0106 | `Dm` **320000** (resend) |
| 1987 | 15.0558 | `Df`: A=323599, B=320600, one interval `[229-229]`, offset-26 field 275071 |
| 1988 | 15.0563 | `Dm` **320800** (resend) |

* **Each loss was reported and resent independently**, as soon as the Expert saw the gap (the second `Df` came 50 ms later, when 320800 was missed), not batched into one two-interval list. Both counters appear exactly once on the wire; stream continues to 478800 within the capture.
* B always equals the start of the last contiguous block (319800 and 320600), consistent with earlier runs.
* **Interval value is still unexplained:** 237 for counter 320000 and 229 for 320800, versus 246 (240000, 280000), 247 (280200), 248 (120000). It is not monotonic in the counter, so it is neither a block index nor a simple modulus of it. The offset-26 field (70495, 230841, 272671, 275071) has not been fitted. With 5 data points this is not yet solvable; next, capture the Expert's feedback with several consecutive single drops at known counters in one session is unsafe (the 8-drop run wedged the session), so collect more data points one drop per session, or look for the meaning in the field at offset 26.
* Start was clean (0 `Df` intervals before the drop).
* Still untested: dropping a resend, dropping a `Df`.

## Automated tests: dropped resend, dropped Df (Drop-Mode.ps1 / Drop-Both.ps1, one clean session each)

`Drop-Mode.ps1 -Mode resend|df` drops a counter via WinDivert (outbound `Dm`); `df` mode also drops the first inbound `Df` carrying intervals. Captures `air-drop-resend.pcapng`, `air-drop-df.pcapng`. Note dumpcap still shows the inbound `Df` that WinDivert dropped (capture is below the drop point); the dropper log confirms the drop.

**Test A: drop 360000 and its first resend** (log: both drops 40 ms apart)
* `Df` f2228 t=15.8611: A=360599, B=359800, `[243-243]`: original lost. Resend (dropped by us) not visible.
* `Df` f2243 t=15.9133 (52 ms later): A=363399, B=359800 (unchanged), `[231-231]`: the Expert asked again.
* `Dm` 360000 seen once on the wire (f2244, 1 ms later), stream then continued with no further loss; 2,395 unique counters up to 478800.
* => A lost resend is recovered by the Expert re-sending the request on its next feedback (~50 ms). The sender needs no timer of its own.

**Test B: drop 400000 and the first `Df` that reports it**
* `Df` f2430 t=16.7161: A=402199, B=399800, `[230-230]`: dropped before reaching AIR.
* `Df` f2444 t=16.7623 (46 ms later): A=404999, B=399800, `[218-218]`: repeated request.
* `Dm` 400000 resent f2445 t=16.7661 (3.8 ms after the second `Df`), once.
* => A lost feedback packet also self-heals via the next periodic `Df` (~50 ms); B stays pinned at the last contiguous block until the gap is filled.

**New observation about the interval value:** within one gap it falls by 12 per `Df` (243?231, 230?218) while ~46-52 ms pass, i.e. ~4 ms per unit, 4.2-4.3 ms per unit. Across experiments the first value is 229-248. Working hypothesis: it is a time-to-deadline/ring-buffer-age counter for the missing block (about 1 s of headroom), not a block index. Unproven; needs a drop at a controlled delay.
