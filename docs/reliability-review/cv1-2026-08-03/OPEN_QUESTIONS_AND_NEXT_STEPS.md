# Open questions and next steps

## Immediate stop line

Do not continue broad firmware/app modification until the independent review is
read. Preserve the branch, dirty diff, OTA artifacts, phone data, and active
build-102 evidence. No production data deletion, backend deployment, or public
firmware release is authorized by this packet.

## Phase 0: recover the fixture

1. Use the charger/button hardware reset.
2. Let the authenticated Android dev app reconnect.
3. Require UI Listening, advancing ring `writeSeq`, `dropped=0`, and a unique
   live-preview marker.
4. Keep Auto Sync off and do not tap Sync.
5. Record that this is build 102, not a candidate qualification.

## Phase 1: make DFU identity impossible to fake

Before another build-106 attempt, update the internal harness/test workflow so
it:

- accepts the artifact only from its documented Documents location;
- computes and displays the ZIP hash;
- parses and displays manifest version/image indexes/sizes;
- parses the signed application header and requires it to equal the requested
  build;
- records the pre-update image list;
- fails if image 0 is absent from the requested set;
- records the post-reboot image list;
- declares success only if image 0 is active and confirmed at the expected
  version; and
- exports all of the above with the physical test record.

Add a regression test using two same-name ZIP fixtures in different directories
so the stale-path bug cannot recur. Add a test that updater success plus wrong
active image is failure.

## Phase 2: physically qualify build 106

After Phase 1 and adversarial review:

1. Start from recovered build 102 and capture its image list.
2. Stage the exact verified build-106 ZIP in Flutter Documents.
3. Launch DFU. Active build 102 may require the charger/button reset after GATT
   handoff so MCUmgr can attach.
4. Require active/confirmed `3.0.30.106` after reboot.
5. Export black-box counters immediately.
6. Speak a unique marker; require ring movement and live preview.
7. Force-stop the dev app without touching the pendant.
8. Independently scan for at least 60 seconds and record every advertisement.
9. Relaunch; require exact-device reconnect and preview continuation.
10. Repeat Bluetooth off/on and app background/lock cases.
11. Confirm the advertiser supervisor stops on real connection and does not
    burn battery while connected.

If 106 fails to boot or advertise, recover via hardware reset. Do not attempt
an OTA downgrade unless MCUboot policy and data retention are understood; use a
wired full flash on the spare pendant once hardware is available.

## Phase 3: close app parity

Run the same final firmware and same TTS sequence on Android and iOS:

- cold start;
- foreground/background/locked Bluetooth interruption;
- app process death;
- current-gap repair;
- one explicit immutable backlog snapshot;
- interruption mid-backlog read;
- long continuous speech;
- quiet/noise VAD;
- DFU and exact-device reclaim; and
- cross-phone handoff.

Compare source sequence coverage, canonical hashes, final conversation times,
preview ownership, retries, and battery. A pass on one platform does not imply
the other.

## Phase 4: split the change stack

The current branch is too large to review or bisect safely. Proposed order:

1. Firmware ring durability/protocol contract and host tests.
2. Android session-bound GATT and native tests.
3. iOS restoration/session-bound GATT and native tests.
4. Shared Dart storage-first scheduling/assembly plus product invariant.
5. Internal black-box diagnostics and harness, explicitly excluded from
   production builds.
6. Firmware PDM/bounded-read/advertiser/button fixes after physical proof.
7. Backend canonical replacement as a separate PR/deployment.

Each PR must be rebased independently, cite `INV-CAPTURE-1`, carry only its
failure class, and include exact test evidence. Avoid a 200-file payload stack.

## Phase 5: JTAG and fault injection

When the Tag-Connect/SWD cable arrives, use the untouched second pendant first.
Capture:

- application and network-core logs;
- reset reason and fatal/coredump state;
- PDM slab exhaustion/restart;
- SD power/mount/write fault behavior;
- BLE advertiser/controller state across disconnect;
- queue high-water marks;
- boot slot/swap state;
- power consumption by quiet, speech, live transfer, and history transfer.

Inject one fault at a time and verify the exact durability invariant. The
black-box trace remains useful for correlation but is not a substitute for
driver/controller evidence.

## Deferred backend work

The backend must eventually own an atomic canonical replacement/merge contract:

- source device and sequence coverage are the idempotency key;
- accepted canonical audio controls origin/duration;
- overlapping live fragments are replaced or reconciled exactly once;
- late recovery inside a conversation is inserted in order;
- summaries/events are recomputed once after the accepted timeline changes;
- noise/short fragments do not independently consume transcription/LLM work;
- two phones racing the same range converge on one result.

Until this is deployed and tested against non-production infrastructure, final
timeline correctness remains blocked even if firmware/app durability passes.

## Open questions for the reviewer

1. Does any cursor advance/delete path still bypass durable registration?
2. Can live and historical readers ever exist concurrently after lifecycle or
   reconnect races?
3. Can a stale Android/iOS callback complete work in a newer session?
4. Can app restart mint a new conversation/upload identity for existing source
   coverage?
5. Does app-side VAD operate on assembled audio, or can it accidentally erase
   weak/short legitimate speech?
6. Is build-106 advertiser refresh safe with Zephyr legacy advertising APIs and
   the connection callback ordering on nRF5340?
7. Can the emergency reboot interrupt a durability commit?
8. Does multi-image MCUboot confirmation handle partial app/network-core
   success safely?
9. What exactly makes Connected and Listening true, and can either state become
   stale without a watchdog tied to ring movement?
10. Are the app and backend using the same wall-clock source and silence
    boundary when reconstructing a conversation?

## Release gates

No public candidate until all are true:

- exact firmware artifact active/confirmed;
- firmware/app focused and component suites pass;
- Android and iOS final matrix passes on the same build;
- no raw fragment upload/display storm;
- no ADVANCE before durability in every injected interruption;
- no-touch advertising/reconnect passes;
- current conversation survives offline gap exactly once and in order;
- manual historical sync never starves live capture;
- controlled battery result is acceptable;
- backend final timeline/deduplication passes or the release explicitly excludes
  automatic canonical replacement;
- recovery procedure is public and safe; and
- independent adversarial review has no unresolved blocker.
