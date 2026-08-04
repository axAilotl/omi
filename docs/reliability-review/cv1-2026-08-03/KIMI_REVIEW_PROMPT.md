# Independent adversarial review prompt

You are the independent reviewer. You did not author this implementation. Be
skeptical, evidence-driven, and explicit about uncertainty.

## Inputs

- `review/` contains architecture, incident chronology, bug register, test
  methodology, artifact ledger, and current-status correction.
- `source/` is the exact uncommitted working-tree snapshot under review.
- `patches/committed-since-origin-main.patch` contains the committed branch
  delta.
- `patches/working-tree.patch` contains tracked uncommitted changes.
- `evidence/pinned-zephyr/` contains the exact legacy advertising and
  connection reference implementation from NCS 2.9.0.

Read `review/CURRENT_STATUS_AND_REVIEW_BRIEF.md` first. It supersedes stale
build-106 statements in the earlier chronology.

## Required work

1. Reconstruct the intended end-to-end system: pendant capture, SD durability,
   live preview, recent repair, explicit historical drain, phone canonical
   assembly, upload, transcript/timeline ownership, DFU, Android/iOS parity.
2. Audit the specific off-air incident from first principles. Verify or refute
   the `button_notify()` connection-reference leak and the pinned Zephyr
   lifecycle explanation.
3. Determine whether removing the repeated advertiser stop/start supervisor is
   correct. Identify any distinct boot/wake/controller failure it might have
   hidden.
4. Search every BLE connection acquisition/release and every GATT callback for
   leaks, double-unrefs, stale-session completion, races, and ownership gaps.
5. Evaluate whether the new BabbleSim scenario is behavioral, deterministic,
   CI-discovered, and capable of failing on the old production code. Propose a
   stronger test if it is not.
6. Adversarially inspect audio durability and ordering: no advance before local
   durability, immutable bounded reads, exact retry identity, live priority,
   no duplicate backfill, and conversation boundaries independent of transport.
7. Inspect Android and shared Flutter changes for foreground/background owner
   conflicts, automatic deep drain, stale callbacks, false Listening state,
   one-second fragment amplification, and battery-amplifying loops.
8. Identify claims that are unsupported, contradicted by code, or based only on
   UI/log inference.
9. Run focused tests and static searches. You may set up Docker/NCS/BabbleSim on
   this x86_64 Linux host. Do not access production services or flash hardware.
10. Produce `ADVERSARIAL_REVIEW_KIMI.md` in the packet root.

## Report format

Lead with a verdict: `block`, `approve after fixes`, or `ready for physical
qualification` (not ready for release).

For each finding include:

- severity (`critical`, `high`, `medium`, `low`);
- exact file and line(s);
- violated contract and concrete failure sequence;
- whether the current tests catch it;
- minimal fix and required regression test;
- confidence and evidence type.

Separate:

- verified defects;
- plausible risks requiring discriminating tests;
- invalidated concerns;
- test/environment defects;
- release/physical-qualification gates.

Do not rewrite the implementation. Do not soften findings to match the packet's
conclusions. Preserve commands and test outputs used to reach the verdict.
