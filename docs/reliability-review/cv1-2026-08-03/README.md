# Omi CV1 reliability review packet

> **Latest handoff (2026-08-04 UTC):** Start with
> [SESSION_RESTART_HANDOFF_2026-08-04.md](SESSION_RESTART_HANDOFF_2026-08-04.md),
> [BUILD110_IOS_FINAL_QUALIFICATION.md](BUILD110_IOS_FINAL_QUALIFICATION.md),
> and
> [KIMI_IOS_PROCESS_RECOVERY_SUMMARY_2026-08-04.md](KIMI_IOS_PROCESS_RECOVERY_SUMMARY_2026-08-04.md).
> They record the build-110 durability evidence, the final single-owner iPhone
> cold-reconnect/manual-drain pass, the exact five-second latency caveat, and
> the remaining app/backend conversation-ownership defect. Earlier build
> 106–108 material remains incident chronology.

> **Status correction (2026-08-04 UTC):** Read
> [CURRENT_STATUS_AND_REVIEW_BRIEF.md](CURRENT_STATUS_AND_REVIEW_BRIEF.md)
> and [BUILD108_QUALIFICATION.md](BUILD108_QUALIFICATION.md) first. Build 107 was
> uniquely sealed and uploaded, but failed the no-touch postboot reconnect gate
> and then exposed a permanent live status-9 loop after a transient snapshot
> flush failure. Build 108 is sealed but not flashed; it test-pins and repairs
> that readiness-latch failure. Build 107 fixes
> the isolated BLE connection-reference leak and removes the speculative
> advertiser supervisor. Earlier build-106 and advertiser statements below are
> retained as incident chronology and are superseded where they conflict with
> those documents.

Date: 2026-08-03
Branch reviewed: `codex/cv1-blackbox-diagnostics`
Base repository: `BasedHardware/omi`
Scope: CV1 firmware, Android, iOS, shared Flutter capture/sync, and the deferred backend boundary

## Executive status

The later, manually selected build-106 run proved that the intended application
image was uploaded and booted, but did not capture an explicit postboot
active/confirmed slot listing. That installed candidate still contains the
button connection-reference leak and the speculative advertising supervisor.

Build 107 was the replacement laboratory candidate. Its exact OTA identity is
sealed, its app preflight rejects stale or tampered packages before BLE is
touched, the fixed simulator reconnects in about 109 ms, and a deliberately
leaky control fails. The physical upload succeeded, but the device stayed
off-air after reset even after an Android Bluetooth-controller reset. Build 107
is not physically qualified.

Build 108 is the next sealed laboratory candidate. It preserves an already
published durable SD snapshot after a later partial-tail flush failure, which
prevents the permanent `STORAGE_NOT_READY` live-audio loop observed on build
107. It has passed the host and full pinned NCS build gates but has not been
flashed or physically qualified.

## Disposition

- **Next physical candidate:** build 108 only, using its exact sealed artifact
  and the preflight/postflight gates in `BUILD108_QUALIFICATION.md`.
- **Do not reuse:** generic or stale build-102/build-105/build-106 filenames.
- **Do not merge as one stack:** this branch contains roughly 30,000 added lines
  across firmware, Android, iOS, Flutter, CI, docs, and tests. It needs to be
  split into reviewable contracts.
- **Do not claim end-to-end transcript correctness:** the app requests
  `transcript_mode=replace`, but the current `/v2/sync-local-files` backend does
  not own that contract atomically. Audio durability has stronger evidence than
  final transcript/timeline deduplication.
- **Do not infer firmware behavior from UI labels alone:** Connected and
  Listening previously coexisted with a frozen SD write cursor. Physical
  evidence must include active image, ring movement, and a known audio marker.

## Packet map

- [SESSION_RESTART_HANDOFF_2026-08-04.md](SESSION_RESTART_HANDOFF_2026-08-04.md)
  — minimum context, working branches, setup quirks, proven claims, and the next
  safe actions for a fresh session.
- [BUILD110_IOS_FINAL_QUALIFICATION.md](BUILD110_IOS_FINAL_QUALIFICATION.md) —
  exact firmware/app identities and the final cold-preview plus manual-backlog
  physical evidence.
- [KIMI_IOS_PROCESS_RECOVERY_SUMMARY_2026-08-04.md](KIMI_IOS_PROCESS_RECOVERY_SUMMARY_2026-08-04.md)
  — independent process-death ownership analysis and the recommended app/backend
  split.
- [IOS_DEBUG_RELAUNCH_INCIDENT_2026-08-04.md](IOS_DEBUG_RELAUNCH_INCIDENT_2026-08-04.md)
  — detached-debug launch crash classification, no-data-loss recovery, and the
  permanent profile-build rule for unattended drains.

- [ARCHITECTURE_AND_INVARIANTS.md](ARCHITECTURE_AND_INVARIANTS.md) — intended
  end-to-end ownership and non-negotiable behavior.
- [CHANGELOG_AND_FINDINGS.md](CHANGELOG_AND_FINDINGS.md) — work chronology,
  firmware-build ledger, and corrected claims.
- [BUG_REGISTER.md](BUG_REGISTER.md) — open, mitigated, and invalidated findings
  with severity and evidence.
- [TEST_METHODOLOGY.md](TEST_METHODOLOGY.md) — repeatable automated and physical
  acceptance methodology.
- [ARTIFACTS_AND_REPRODUCTION.md](ARTIFACTS_AND_REPRODUCTION.md) — branches,
  hashes, build inputs, auth setup, and evidence locations.
- [OPEN_QUESTIONS_AND_NEXT_STEPS.md](OPEN_QUESTIONS_AND_NEXT_STEPS.md) — phased
  restart plan and release gates.
- [COMMIT_INVENTORY.md](COMMIT_INVENTORY.md) — grouped inventory of the work on
  this branch.
- [CURRENT_STATUS_AND_REVIEW_BRIEF.md](CURRENT_STATUS_AND_REVIEW_BRIEF.md) —
  authoritative status after the real build-106 flash and advertiser root-cause
  isolation.
- [VALIDATION_STATUS.md](VALIDATION_STATUS.md) — commands, results, gaps, and
  the exact reconnect regression now pinned in BabbleSim.
- [BUILD107_QUALIFICATION.md](BUILD107_QUALIFICATION.md) — sealed artifact
  identities, automated evidence, and the physical acceptance gate.
- [BUILD108_QUALIFICATION.md](BUILD108_QUALIFICATION.md) — build-107 physical
  live-path failure, narrow firmware correction, sealed artifacts, and the next
  physical acceptance gate.
- [ADVERSARIAL_REVIEW_KIMI.md](ADVERSARIAL_REVIEW_KIMI.md) — independent Kimi
  review of the reconnect candidate and the wider experimental stack.
- [KIMI_REVIEW_PROMPT.md](KIMI_REVIEW_PROMPT.md) — independent-review mandate
  and required report format.
- [DIGITAL_TWIN_CAMPAIGN.md](DIGITAL_TWIN_CAMPAIGN.md) — executable virtual
  qualification contract, ownership model, promotion gates, and division of
  labor for the Linux/Kimi campaign.
- [`digital-twin/scenarios.json`](digital-twin/scenarios.json) — deterministic
  fault and soak matrix consumed by the campaign runner.
- [`digital-twin/evidence.schema.json`](digital-twin/evidence.schema.json) —
  required machine-readable result and provenance shape.

## Evidence labels used in this packet

| Label | Meaning |
|---|---|
| **Physical proof** | Observed on the named real device with artifact/build identity and durable evidence. |
| **Automated proof** | Hermetic unit/host/native test executed against production code through a controllable seam. |
| **Source present** | Implemented in the branch and compiled/tested, but not physically exercised on the claimed build. |
| **Inference** | Best explanation consistent with evidence; requires a discriminating test. |
| **Invalidated** | A previous claim depended on the wrong artifact, stale app, wrong backend, or insufficient identity proof. |
| **Blocked** | Requires unavailable hardware, account authority, or backend deployment. |

## Review instructions

An adversarial reviewer should assume every claim is wrong until it can point to
one of the following:

1. an active-image listing plus exact artifact hash;
2. a behavioral test that executes the production boundary;
3. a timestamped physical log with a unique audio marker and durable sequence
   coverage; or
4. a backend response proving the final timeline, not merely upload success.

The reviewer should prioritize incorrect ownership, accidental concurrency,
data deletion/advance before durability, stale callbacks, cross-platform
asymmetry, battery-amplifying loops, and tests that can pass while the user
experience is broken.
