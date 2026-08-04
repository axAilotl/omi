# Test methodology

## Principle

Test the product contract from microphone to final conversation, while keeping
each durability boundary independently observable. A compile, unit test,
Connected label, upload response, or updater success is necessary evidence for
its own boundary only; none is an end-to-end pass.

## Run identity

Every physical run must record, before touching Bluetooth:

- source commit and dirty-diff hash;
- phone model/OS and app package/version;
- APK/app bundle SHA-256;
- pendant identity in a private evidence file (redacted in published docs);
- OTA ZIP SHA-256;
- manifest version and image sizes;
- signed application header version and binary hash;
- MCUmgr image list before the transfer;
- app policy: Auto Sync, background mode, Remote VAD, charger state;
- initial battery and `RingInfo(read, write, dropped, packetSize)`; and
- unique spoken marker script and wall-clock start.

After DFU, record the MCUmgr image list again. The claimed application image
must be active and confirmed. If it is not, stop: every behavioral observation
belongs to the image actually listed, not the source tree or ZIP label.

## Evidence validity rules

Invalidate a run if any of these occur:

- artifact path or hash is unknown;
- app was built from a different shared-Dart revision than claimed;
- production/dev Firebase or API target is wrong;
- two clients may have owned the pendant simultaneously;
- firmware active image was not checked after reboot;
- audio marker is missing or cannot be heard in canonical audio;
- phone/device times cannot be reconciled;
- log corruption prevents reconstructing the transition;
- backend returned success but final conversation/timeline was not inspected; or
- a manual reset was used in a test whose purpose was no-touch reconnect.

Keep invalidated runs as evidence of the test-system failure; never silently
delete or relabel them.

## Automated preflight

### Firmware

From the repository root:

```bash
docker run --rm \
  -v "$PWD/omi/firmware:/omi/firmware" \
  -e CMAKE_PREFIX_PATH=/opt/toolchains \
  ghcr.io/zephyrproject-rtos/ci:v0.26.13@sha256:b0ac6334d1926cd0971a0a444f7adc6dd020e88ee3ce865aa070b6475a3ac4eb \
  bash /omi/firmware/scripts/ci/build-cv1.sh
```

Run the host suite described in
`omi/firmware/omi/tests/audio_storage_packer/README.md`. It covers the storage
packer, durability policies, ring integrity, black-box trace, VAD policies,
time recovery, and pure advertising/button policies. It cannot prove driver,
RF, SD-controller, or power behavior.

### Flutter/shared app

From `app/`:

```bash
flutter test \
  test/providers/capture_provider_test.dart \
  test/providers/device_provider_test.dart \
  test/providers/sync_provider_sync_wal_wake_test.dart \
  test/services/capture/conversation_session_window_test.dart \
  test/services/capture/device_audio_streaming_policy_test.dart \
  test/services/capture/live_transcript_preview_test.dart \
  test/services/wals/ring_storage_sync_test.dart \
  test/unit/conversation_audio_assembler_test.dart \
  test/unit/device_transport_exclusive_release_test.dart \
  test/unit/firmware_dfu_connection_handoff_test.dart \
  test/unit/local_wal_sync_test.dart \
  test/unit/native_ble_transport_exclusive_release_test.dart \
  test/unit/omi_mcu_dfu_policy_test.dart \
  test/unit/omi_ready_generation_time_sync_test.dart \
  test/widgets/transcription_paused_warning_test.dart

bash scripts/test_verify_android_physical_test_auth_config.sh
bash scripts/test_verify_ios_physical_test_auth_config.sh
scripts/analyze_ratchet.sh
```

### Native Android/iOS

- Run Android GATT queue, completion registry, reconnect backoff, notification
  transition, and readiness tests.
- Run iOS scheduler/restoration/legacy ownership tests.
- A platform test must key stale callbacks to session and characteristic
  identity, not merely verify a callback map is empty in the happy path.

### Repository gates

Before any PR claim:

```bash
make preflight
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

Use focused loops while editing, then the component runner. Record failures as
well as passes; do not imply the whole suite ran if only focused tests ran.

## Physical acceptance matrix

Use one pendant owner at a time. Generate deterministic TTS markers that include
the phase and a random number, for example online-before, offline, and
online-after. Preserve raw audio privately.

| Case | Procedure | Required result |
|---|---|---|
| Cold start | Launch authenticated dev app with Auto Sync off. Speak marker. | Exact pendant connects; time sync once; ring moves; live preview contains marker; no old backlog read. |
| Bluetooth off/on | Turn phone Bluetooth off for 15 seconds while speaking, then on. | No ADVANCE for interrupted range; exact device reconnects; preview retains owner; offline marker recovered once in order. |
| App force-stop | Force-stop only the dev app while speaking; independently scan. | Pendant becomes observable without touch, app reconnects after launch, and current conversation resumes. A hardware reset makes this test fail. |
| Background/lock | Background and lock phone before interruption. | Same behavior as foreground within documented OS budget; truthful degraded UI if OS delays work. |
| Current-gap repair | Interrupt during one conversation and reconnect before silence boundary. | Missing range auto-repairs behind live head; one canonical conversation. |
| Manual backlog snapshot | Tap Sync once, then continue producing live audio. | Historical target is immutable; new live writes do not extend it; live slices preempt history; one serial reader. |
| Backlog interruption | Disconnect between READ_BEGIN and DONE. | No ADVANCE; retry resumes from last durable cursor without a second Sync tap. |
| Long speech | Play 20–40 minutes of continuous speech. | One logical conversation until the silence boundary; internal rollovers do not create user rows/jobs. |
| Quiet/noise | Keyboard, pocket noise, clicks, laughter, and silence. | No upload storm or independent summaries; assembled fragments are VAD-gated or retained locally. |
| DFU | Record active image, flash, reboot, record active image, speak marker. | Exact image active/confirmed; exact pendant reclaimed; ring moves; live preview works; prior stored audio retained. |
| Cross-phone handoff | Release Android, acquire iOS, then reverse. | Only authorized owner holds pendant; same source range is not uploaded twice; live policy matches. |
| Power/reset | Test normal off, release fence, long-hold recovery, hardware reset. | No wake-on-held-button race; storage survives; reset path documented. |
| Battery | Matched quiet/speech runs with/without authorized history. | Report energy/time and throughput; live correctness stays constant. |

## Exact positive signatures

- `RingInfo` write cursor increases and `dropped=0`.
- `CMD_RING_READ` matches `NOTIFY_READ_BEGIN` start/count.
- Exact record count and CRC precede `NOTIFY_DONE status=0`.
- WAL registration is durable before `CMD_RING_ADVANCE`.
- Reconnect targets the same pendant and republishes readiness once per session.
- Preview recovery explicitly preserves existing segments/owner.
- Canonical artifact contains before/offline/after markers in order.
- Final conversation uses correct start time/duration and contains each marker
  once.

## Exact failure signatures

- PDM `-EAGAIN` loop with frozen `writeSeq`.
- DATA before READ_BEGIN, truncated range, CRC mismatch, or DONE count mismatch.
- ADVANCE timeout/nonzero ACK or any advance after partial read.
- `dropped` increases or overwrite warning appears.
- repeated wrong-device reconnect, time sync, upload job, or canonical identity.
- Connected/Listening while no new audio reaches preview.
- raw ring/archive files appear as user-visible one-second conversations.
- historical read begins with Auto Sync off and no Sync tap.
- updater success without matching active image.

## Throughput

For one clean range, report both:

- record throughput: `count * 444 / elapsed`;
- audio throughput: `count * 440 / elapsed`.

Use decimal kB/s and retain clean p50/p95 separately from interrupted retries.
Do not compare tiny recovery slices to the approximately 88.77 kB/s clean
large-range fixture baseline.

## Battery

Record pendant percentage/history, phone battery, charger state, duration,
speech duty cycle, live/head bytes, history bytes, reconnect count, and radio
parameters. Minimum useful comparisons:

1. quiet, live enabled, no backlog;
2. conversational speech, live enabled, no backlog;
3. same speech plus user-authorized backlog;
4. charging plus user-authorized backlog; and
5. disconnected offline capture.

Percentage over a short development session is observational only. A release
claim needs matched overnight runs or external power instrumentation.

## Evidence preservation

Preserve privately:

- app WAL manifests and backups;
- inventory and SHA-256 of audio files;
- debug/black-box export;
- BLE diagnostics and battery history;
- sanitized logcat/iOS logs with epoch timestamps;
- OTA ZIP and inner-image hashes;
- pre/post MCUmgr image lists;
- screenshots of UI state; and
- final backend conversation ID plus sanitized timeline facts.

Do not publish device addresses, account IDs, tokens, raw transcript/audio, or
Firebase credentials.
