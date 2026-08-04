# Bug register

Statuses: `open`, `source-fixed/unqualified`, `mitigated`, `blocked`, or
`invalidated claim`.

| ID | Severity | Status | Boundary | Finding and evidence | Required closure |
|---|---:|---|---|---|---|
| CV1-R01 | Critical | open | DFU identity | Internal harness resolves the fixed ZIP from Flutter Documents, but the correct 106 artifact was staged in native `files`. The apparent 106 run selected build 102. | Harness displays/verifies ZIP hash, manifest version, signed header, and image sizes before release; post-reboot MCUmgr active image must match. Add a production-path regression test. |
| CV1-R02 | High | open on 102; source-fixed/unqualified on 106 | BLE advertising | Force-stopping the owner can disconnect GATT while the pendant never becomes observable again. Independent scan saw no Omi advertisement. | Physically run 106, force-stop without touching pendant, require advertisement and exact-device reconnect at every capped recovery interval; verify supervisor cancels only on real connection. |
| CV1-R03 | High | open on 102; source-fixed/unqualified | Microphone | 743 consecutive `dmic_read=-EAGAIN` errors froze ring `writeSeq` while UI remained Listening. | Run exact 106 image under pressure; require `mic_recovery`, resumed ring movement, audible marker, and no duplicate/drop. Add injected PDM test when JTAG is available. |
| CV1-R04 | High | source-fixed/unqualified | Bounded ring read | A 75-record request delivered 72 and timed out because a later chunk tried to drain a continuously replenished producer queue. No ADVANCE was sent. | Physical immutable-snapshot read while live producer runs; exact count/CRC/DONE and single ADVANCE after durable registration. |
| CV1-R05 | High | open | Backend canonical ownership | App sends `transcript_mode=replace`; `/v2/sync-local-files` does not declare/own it. Production appended recovered canonical text beside live text and kept the wrong origin. | Atomic idempotent backend replacement/merge with source coverage, correct `started_at`, derived-work invalidation, and end-to-end marker test. |
| CV1-R06 | High | partially mitigated | Conversation assembly | Raw one-to-nine-second ring files previously became Sync rows/jobs, overloaded local manifests and remote processing, and created fragmented conversations. | Keep physical WALs internal; one logical window/job; cheap VAD after assembly; regression with continuous 20-minute speech and noise-only input. |
| CV1-R07 | High | partially mitigated | Live readiness | Connected/Listening previously appeared with frozen audio or a closed/unready socket. Preview could restart as a new session after reconnect. | Readiness state machine must require GATT audio ownership + moving source + accepted STT session. Physical UI proof with unique markers across interruption. |
| CV1-R08 | High | open | Multi-client idempotency | A range retained on pendant could theoretically be downloaded by two clients before either advances/deletes it. App-local identities may not prevent two backend jobs. | Define pendant source ID + sequence coverage as global idempotency key; backend accepts once; second client reconciles same result. Physical two-phone handoff test. |
| CV1-R09 | Medium | open | DFU reclaim | Explicit reconnect retries ended around six seconds before Android native auto-reconnect succeeded in the observed DFU. | Reclaim waits on boot/advertisement evidence with bounded overall timeout; exact device only; app reports recovering instead of failure if native owner remains active. |
| CV1-R10 | Medium | source-fixed/unqualified | Shutdown | Legacy system-off could arm the still-held active-low button as wake source, appearing to power itself back on. | Physically qualify release fence and 30-second recovery on exact 105/106 image; document reset path. |
| CV1-R11 | Medium | mitigated | Recovery UX | Powered off-air CV1 looked bricked; two LED packages showing red were mistaken for two faults. | Public docs retain charger/button reset and LED topology; never advise shorting test pads/FPC/battery. |
| CV1-R12 | Medium | open | iOS performance | Isolated iOS container accumulated 936+ Documents files and became slow/jagged during Sync work. | Measure manifest/file scan cost, bound work, compact safely, retain recordings; no cleanup-as-fix without explicit user authority. |
| CV1-R13 | Medium | open | Battery | Concurrent historical drain plus live head can saturate BLE/CPU/radio and rapidly reduce pendant/phone battery. | Explicit historical authority, live preemption, matched overnight A/B power runs, charging-aware budget that never auto-starts history. |
| CV1-R14 | Medium | mitigated | Diagnostic evidence | Concurrent debug log append/rotation produced invalid JSON and weakened physical evidence. | Serialized log IO and deterministic concurrent-write/clear tests remain required; export validates every line before claiming a pass. |
| CV1-R15 | Medium | open | Platform parity | Android and iOS have passed different subsets; desktop is largely unqualified. A fix on one side has repeatedly regressed another. | One shared matrix on the same firmware/artifact and same marker protocol; parity table must contain no inferred pass. |
| CV1-R16 | Medium | open | Test methodology | UI, updater success, and source version strings were accepted without active-image proof. | Artifact ledger plus pre/post MCUmgr image list becomes mandatory; any missing identity invalidates the run. |
| CV1-R17 | Low runtime / high evidence | blocked | Fault injection | No Tag-Connect/JTAG cable; black-box telemetry cannot reproduce all power/SD/controller faults deterministically. | Obtain cable, use untouched second pendant, capture RTT/coredump/power data, inject bounded failures. |

## Review hotspots

### Data-loss hotspots

- Every call that advances a ring cursor or deletes a WAL.
- DONE handling after partial reads, CRC mismatch, timeout, disconnect, or
  stale callback.
- Compaction paths that retire physical members before canonical file fsync.
- Backend retries that mint a new identity.

### Concurrency hotspots

- Android completion registries and operation queues across session replacement.
- iOS restoration versus foreground ownership.
- Live head and historical slice coordination.
- DFU terminal callback plus page disposal plus native auto-reconnect.
- Log append/rotation/clear.

### Battery hotspots

- Connection-parameter renegotiation loops.
- MTU/PHY/DLE retries during active audio.
- Repeated advertiser reset while connected.
- Polling RingInfo with no eligible live consumer.
- Unbounded WAL assembly or file scanning.
- Live and historical transfer without preemption.
