# Kimi task: CV1 digital-twin Campaign 001

Work only in:

`/mnt/ai/omi-cv1-digital-twin-2026-08-04/source`

The exact build-108 source snapshot was verified before this task with manifest
SHA-256
`6c84e31aa19e9ca3a295ef6cd9221a671e0867465df10a3026fd4aade96ecd1d`.
The tree is intentionally dirty because it contains the frozen experimental
stack. Do not discard, normalize, rebase, or commit pre-existing changes.

Read completely before acting:

1. root `AGENTS.md`;
2. `omi/firmware/AGENTS.md`;
3. `docs/reliability-review/cv1-2026-08-03/DIGITAL_TWIN_CAMPAIGN.md`;
4. `docs/reliability-review/cv1-2026-08-03/digital-twin/scenarios.json`;
5. `docs/reliability-review/cv1-2026-08-03/digital-twin/evidence.schema.json`;
6. `docs/reliability-review/cv1-2026-08-03/ADVERSARIAL_REVIEW_KIMI.md`;
7. `docs/reliability-review/cv1-2026-08-03/BUILD108_QUALIFICATION.md`; and
8. existing firmware host and BabbleSim tests plus production transport,
   storage, ring-integrity, and black-box code.

## Mandate

Implement and run the smallest production-bound harness that executes the
required Campaign 001 scenarios. Prioritize:

1. `ADV_INIT_FAIL_ONCE` and `ADV_INIT_FAIL_PERSISTENT` through the production
   advertiser lifecycle in BabbleSim or the closest production-linked seam;
2. `SNAPSHOT_FAIL_SUCCESS_FAIL` through the production readiness/retry policy;
3. the four disconnect-during-transfer cases through a deterministic protocol
   model tied to production transition functions; and
4. `LIVE_PREEMPTS_MANUAL_HISTORY` only if a production-owned scheduler seam
   already exists or can be extracted narrowly without app/backend expansion.

Do not implement speculative throughput optimization in this campaign. First
make the oracle capable of disproving the current implementation.

Every repair must include:

- a behavioral regression test through production behavior;
- a broken/mutated control that the new test rejects for the intended reason;
- bounded retry/terminal semantics;
- black-box evidence sufficient to distinguish attempt, recovery, exhaustion,
  and disconnect; and
- no new polling loop or permanent wake/radio supervisor.

If BabbleSim cannot inject `bt_le_adv_start` without replacing production
behavior, document the exact blocker and implement the narrowest test-owned
adapter at the call boundary. Do not claim a policy-only test proves Zephyr
controller behavior.

## Prohibitions

- Do not access, flash, reset, or otherwise control physical devices.
- Do not change firmware version, MCUboot/sysbuild/partition configuration,
  network-core image, auth, backend target, or production apps.
- Do not use the network except for already-authorized toolchain/container
  dependency retrieval.
- Do not delete or rewrite pre-existing user changes.
- Do not commit or push.
- Do not modify Android, iOS, desktop, or backend production code in Campaign
  001.
- Do not report a pass from compile-only or source-string assertions.

## Required execution

Run focused tests while editing, then:

1. the complete host-native firmware suite documented in
   `omi/firmware/omi/tests/audio_storage_packer/README.md`;
2. the pinned x86_64 BabbleSim product scenario;
3. every required scenario implemented from `scenarios.json` with its exact
   deterministic seed;
4. every implemented broken control; and
5. the relevant pinned NCS compile if production firmware code changes.

Use the already available Docker/NCS/BabbleSim setup on this host. Preserve
commands and raw output. A required scenario that cannot honestly run is
`incomplete`, not `pass`.

## Evidence output

Write outside the source tree to:

`/mnt/ai/omi-cv1-digital-twin-2026-08-04/evidence/campaign-001/`

Required files:

- `REPORT.md`: verdict, implementation, findings, failures, limitations, and
  exact rerun commands;
- `results.json`: conforming to `evidence.schema.json`;
- `commands.log`: every executed command and exit code;
- `changed-paths.txt`: only paths changed during this task;
- `kimi.patch`: binary-safe patch of only your campaign changes, excluding the
  frozen build-108 baseline;
- `SHA256SUMS`: hashes of every evidence artifact and preserved raw log; and
- per-scenario raw logs named by scenario ID.

Do not overwrite or fold the frozen baseline into `kimi.patch`. A passing
report must be reproducible, must exit nonzero when a required assertion fails,
and must say explicitly what still needs physical hardware.
