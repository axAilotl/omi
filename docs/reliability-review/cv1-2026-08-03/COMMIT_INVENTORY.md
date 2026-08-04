# Commit inventory

This inventory groups the committed branch work from `origin/main` through
`ef4c9355b3`. It does not include the current uncommitted diagnostic/recovery
delta or this review packet.

## Firmware durability and performance

- `4aeefbc0e2` — require durable app acknowledgment before discard
- `e9bbdf03db` — honor negotiated BLE intervals
- `0782e6220d` — preserve audio through BLE and SD faults
- `f38aa015ac` — bind dual-core OTA versions
- `d3fbb433ce` — accelerate durable backlog transfer
- `7307d21f8c` — make offline recovery fail closed
- `55f28e35a8` — raise controller TX capacity
- `e3950f24cc` — bound storage readiness recovery
- `3ac4ea9127` — add storage-first demo mode
- `28dd451fe5` — gate silence before durable capture
- `8a7847f21e` — make firmware formatting portable in CI
- `0fff1f7f63` — retain capture identity through reconnect
- `0a72e1f40b` — keep awake audio capture lossless
- `0e79f66122` — add internal black-box diagnostics
- `09c90e37b6` — harden internal black-box tracing

## Android/Limitless native BLE

- `4c6d87a1c8` — preserve contiguous Limitless flash ACKs
- `5c0a656449` — serialize and recover BLE GATT operations
- `8400eb9fa2` — recover backlog after background reconnect
- `a8e74b62ba` — bind GATT work to connection sessions

## Shared capture, sync, and durability

- `57cc14c9d8` — acknowledge records after durable storage
- `a6b342f47c` — make backlog recovery transactional
- `153429c7b1` — detect BLE continuity faults
- `774b666893` — bound WAL assembly allocations
- `d5557d14f2` — reclaim exact pendant after DFU
- `af161d047f` — isolate ring backlog protocol ownership
- `399600c3d3` — complete storage-authoritative capture
- `3590caebf6` — prioritize recent recovery
- `edc731a3d4` — prioritize storage-backed live continuity
- `6467438301` — bound offline WAL recovery work
- `ff63539caf` — assemble recovery as one conversation
- `9f444e7f29` — preserve live preview across reconnects
- `b9b83c7829` — compact overlapping replays
- `73884fbe85` — preserve logical backlog snapshots
- `7f319a3e02` — count logical recordings in Sync
- `fc3dba4208` — repair local recovery ownership
- `468deea23b` — restore explicit backlog authority
- `e73e53d11b` — pin live priority during backlog sync
- `3a53482271` — surface live transcription reconnect state
- `883bc13b57` — open logical Sync recordings for playback
- `ef4c9355b3` — preserve storage-first capture through reconnects

## iOS ownership and parity

- `f6adff4839` — republish GATT readiness after restore
- `b34b64f03a` — release unapproved restored pendant

## Diagnostics and evidence integrity

- `6a4b90d7f0` — serialize diagnostic log writes
- `4bec4c8300` — add authenticated black-box harness

## Product contract and physical-test configuration

- `69c41b921a` — define capture continuity invariant
- `70c3e58319` — record Android storage-first acceptance
- `251f56dc8b` — record iOS storage-first acceptance
- `9add980156` — guard authenticated iOS hardware setup
- `0a18ffdb15` — pin hardware tests to the customer data plane

## Toolchain and CI fixes

- `8e97caebf6` — run Android native tests with pinned Gradle
- `5022d4d63c` — configure Gradle Flutter SDK
- `d8a858558e` — pin Flutter SDK setup for native Gradle
- `eafd2c17fc` — isolate Flutter SDK detection in hooks
- `633c70f3d0` — normalize setup fixture paths

## Uncommitted work at packet creation

The dirty delta adds or modifies:

- build-106 advertiser recovery supervisor and diagnostics;
- microphone `-EAGAIN` recovery;
- immutable bounded-read behavior;
- button release/emergency reboot policy;
- Android foreground connection modes;
- black-box harness/export parsing;
- live-head readiness policy; and
- regression tests and public/internal recovery documentation.

Run these commands for the authoritative current list:

```bash
git status --short
git diff --stat
git diff --name-only
```

Do not treat an uncommitted source file as part of any previously built artifact
without recording the artifact time/hash and source diff.
