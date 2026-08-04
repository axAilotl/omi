# CV1 digital-twin reliability campaign

## Purpose and boundary

This campaign converts the storage-first design into repeatable, adversarial
qualification before another pendant is flashed. It is a **digital twin of the
state and protocol contracts**, not a claim to emulate CV1 RF, SD timing,
microphone acoustics, power draw, or every nRF5340 peripheral.

The product boundary is the proposed
[`INV-CAPTURE-1`](../../product/invariants/capture-continuity.md) contract:
one durable conversation timeline across pendant storage, Android, iOS,
desktop, live transcription, retry, and backend projection. Campaign results
may strengthen its guard surfaces but do not change that invariant.

The initial Linux runner uses the production firmware in BabbleSim where the
model exists, production policy/state-machine code in host-native tests, and
explicit phone/backend reference models where hardware or cloud behavior is
not emulated. Every result must name which boundary it proved. Hardware-only
claims remain open for a later build-109 physical run and JTAG qualification.

Build 108 is the frozen starting point:

- source HEAD: `ef4c9355b397c64789ef936d76b8619c93788f14` plus the recorded
  working-tree delta and untracked files;
- exact source-manifest SHA-256:
  `6c84e31aa19e9ca3a295ef6cd9221a671e0867465df10a3026fd4aade96ecd1d`;
- OTA SHA-256:
  `dc04db60610baf34494f321c171f377d1f15cc728e05b1c9a22577eb4e78d8fd`;
- application version: `3.0.30+108`; and
- physical status: sealed, never flashed, not qualified.

The Linux worktree at
`/mnt/ai/omi-cv1-digital-twin-2026-08-04/source` was independently
re-manifested and matched the exact 71-entry source manifest above before any
campaign change.

## End-to-end correctness model

The unit of identity is a source range, not a BLE packet, file name, upload,
WebSocket session, or UI row:

```text
SourceRange {
  device_id,
  capture_epoch,
  seq_start,
  seq_end,
  captured_at_start,
  captured_at_end,
  codec,
  payload_sha256
}
```

`capture_epoch` changes only when sequence identity can no longer be compared
with the prior boot/session. A consumer must reject two payload hashes claiming
the same `(device_id, capture_epoch, sequence range)`.

Ownership advances in this order:

```text
pendant durable SD range
  -> phone durable WAL + manifest
  -> canonical conversation audio
  -> backend idempotent acceptance
  -> derived transcript/summary/events
```

`CMD_RING_ADVANCE` is permitted after the phone has durably registered the
exact complete range. It is forbidden after a partial transfer, CRC/count
mismatch, timeout, session replacement, local-write failure, or ambiguity
about the source identity. Backend failure may retain phone work but must not
recreate or mutate the physical source identity.

## Scheduling and product invariants

1. **Live is the head lane.** It is always preemptive over historical work.
2. **Recent-gap repair is automatic only for the open conversation.** The
   configured silence boundary, approximately two minutes, determines whether
   recovered audio belongs to the current conversation.
3. **Historical backlog is explicit.** Charging may increase its slice budget
   but never authorizes it and never permits live starvation.
4. **Transport transitions are not conversation boundaries.** Bluetooth
   off/on, reconnect, app restart, five-minute storage rotation, and upload
   retry preserve the open conversation owner.
5. **Physical fragments are internal.** Adjacent records are assembled before
   upload/display; short/noise-only material cannot fan out into summaries.
6. **UI state is evidence-based.** `Listening` requires an accepted
   transcription session and ordered audio movement, not merely a GATT link.
7. **All consumers are idempotent.** Android, iOS, desktop, and backend use the
   same source-range identity; a second phone cannot create a second logical
   recording from an already accepted range.
8. **Fault recovery is bounded.** Retry loops declare attempts, elapsed time,
   terminal state, and escape path. No failure may cause unbounded advertiser,
   GATT, SD, upload, or wake-lock churn.

## Campaign layers

### Layer A — production firmware simulation

BabbleSim executes the real CV1 transport/button/GATT code against the
nRF5340 app and network-core BLE model. Extend it through narrow test-only
seams to inject:

- initial `bt_le_adv_start()` failure;
- disconnect/reconnect and stale session completion;
- GATT notification pressure/errors; and
- bulk-transfer interruption.

The first advertising failure is a priority because build 107 physically
booted off-air and the current production path logs an error and continues
without a recovery owner.

### Layer B — production policy/state machines

Host-native tests execute extracted production policy functions with fake
clock, SD, notify, and durable-registration adapters. These tests cover state
space that BabbleSim cannot model faithfully:

- snapshot commit failure/success/failure monotonicity;
- transfer read/count/CRC/DONE/ADVANCE ordering;
- SD stage faults and reboot recovery;
- live/history arbitration; and
- sequence/time/ring-wrap identity.

A source-string assertion is not behavioral proof. Every regression test must
be mutation-checked by running a broken control (or an equivalent injected
invalid transition) and demonstrating that the test fails for the expected
reason.

### Layer C — app/backend reference model

A deterministic model replays source ranges through phone durable WAL,
conversation assembly, upload retry, and backend idempotency. It validates the
cross-layer properties while Android/iOS implementations remain separately
covered by their native/shared-Dart tests. The model must never be cited as
proof that either OS grants background execution or that the production
backend already owns atomic replacement.

## Campaign 001 scope

Campaign 001 is intentionally bounded to the failures most likely to brick or
invalidate another physical run:

1. initial advertising failure recovers through one bounded owner without
   stop/start churn;
2. storage snapshot state exactly reproduces `failure -> success -> failure`
   and preserves the published durable window;
3. disconnect during `INFO`, `READ`, `DONE`, or `ADVANCE` never advances an
   incomplete range and reconnect resumes without a second user Sync action;
4. clean and faulted paths emit enough black-box evidence to distinguish the
   transition and retry owner; and
5. each passing fix has a broken control that the new test rejects.

Campaign 001 may add test-only seams and production telemetry. It must not:

- flash a physical device;
- change MCUboot, partitioning, network-core firmware, release version, radio
  power, or production auth/backend configuration;
- broaden into Android/iOS/backend feature implementation; or
- optimize throughput before the correctness oracle is green.

## Evidence and pass criteria

Every scenario emits a result conforming to
[`digital-twin/evidence.schema.json`](digital-twin/evidence.schema.json), plus
raw command logs and deterministic seeds. A campaign passes only when:

- all required scenarios pass;
- the runner exits nonzero on any scenario failure;
- all broken controls fail for the intended invariant;
- no unexpected source files or generated artifacts changed;
- host-native tests and the pinned x86_64 BabbleSim lane pass independently;
- the exact source snapshot, container digest, tool versions, command line,
  seed, duration, and produced patch are recorded; and
- an independent reviewer can rerun the campaign from the report alone.

Primary correctness thresholds are zero durable source-range loss, zero
duplicate acceptance, zero illegal `ADVANCE`, zero live starvation, and zero
unbounded retries. Performance is reported, not optimized, in Campaign 001:
reconnect-to-first-audio, live p50/p95 latency, clean/faulted backlog kB/s,
notify retries, SD commits, simulated wake/radio work, and memory high-water
where the model exposes them.

## Promotion ladder

1. Campaign 001 passes on Linux and is independently rerun by Codex.
2. The accepted patch is reviewed against the entire pendant-to-backend
   ownership model; no Kimi-generated change is trusted by default.
3. Full pinned NCS sysbuild and all affected component tests pass.
4. A uniquely versioned build 109 candidate is sealed with exact hashes.
5. Only the designated test pendant is flashed; the untouched pendant remains
   the control until a recoverable hardware-debug path exists.
6. Physical gates cover postboot advertising, exact-device reconnect, active
   image, live preview, ring movement, interrupted current-gap recovery, and
   manual backlog preemption.
7. Battery/RF/SD-driver claims require real hardware evidence and are never
   inferred from this campaign.

No green virtual result authorizes a flash or release by itself.

## Division of labor

Kimi owns Linux implementation, deterministic exploration, fault-matrix runs,
and complete raw evidence. Codex owns the end-to-end product contract,
independent patch review, cross-platform implications, reproduction, and the
promotion decision. Disagreements are resolved by a discriminating test or
physical evidence, never by model consensus.
