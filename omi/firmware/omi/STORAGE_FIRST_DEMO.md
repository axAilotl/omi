# Storage-first CV1 demo firmware

This experimental CV1 build applies the same reliability boundary used by
offline-first recorders: the pendant's SD ring is the authoritative audio
source, and the phone is a resumable synchronization peer.

## Behavior

- Every encoded Opus frame is accepted by the ordered storage packer before any
  optional live BLE preview.
- Temporary SD power, mount, queue, or write backpressure retains the exact
  frame and prevents later frames from overtaking it.
- Terminal SD failure may fall back to live BLE so simultaneous media failure
  does not force avoidable loss.
- Live preview is read from the newest bounded SD-ring slice. The legacy audio
  notification path is disabled, so there is still exactly one source for each
  frame and no cross-transport deduplication guess.
- After a reconnect, current audio is read first. The app repairs the newest
  uncovered interval on a separate durable lane and leaves old history alone
  unless the user explicitly starts a bounded sync.
- The existing bounded ring protocol remains the retrieval path: READ_BEGIN,
  exact sequence range, byte CRC, durable phone registration, then ADVANCE.

The public-candidate demo reports firmware `3.0.29`. The isolated diagnostic
line reports `3.0.30+106`, adds a 12-hour sampled trace, cumulative counters,
an uptime-based emergency reboot, a button-release fence before system-off,
and an advertising supervisor that remains active until a real connection,
and is compiled into the `codex/cv1-blackbox-diagnostics` branch only. Neither
line is a production release. Retain a hardware recovery path because an older
OTA image may be rejected as a downgrade.

## Build

Run the regular CV1 gate from this branch:

```sh
docker run --rm \
  -v "$PWD/omi/firmware:/omi/firmware" \
  -e CMAKE_PREFIX_PATH=/opt/toolchains \
  ghcr.io/zephyrproject-rtos/ci:v0.26.13@sha256:b0ac6334d1926cd0971a0a444f7adc6dd020e88ee3ce865aa070b6475a3ac4eb \
  bash /omi/firmware/scripts/ci/build-cv1.sh
```

Use `dfu_application.zip` for an app-driven OTA and `merged.hex` for a wired
full flash.

## Physical validation

Use a fresh or fully drained test CV1 so old ring records cannot contaminate the
result.

1. Record a timestamped reference track for 10 minutes while connected.
2. Disable phone Bluetooth for 2 minutes without stopping the reference track.
3. Re-enable Bluetooth, background the app, and let ring synchronization finish.
4. Repeat with app force-stop, phone reboot, CV1 reboot, weak RF, and a one-hour
   backlog.
5. Compare recovered Opus frames against the reference timeline and the
firmware's start/end ring sequence.

Required outcomes:

- No silent source-range loss.
- No ADVANCE before the exact range is durably registered on the phone.
- Interrupted ranges restart from their last durable sequence.
- Audio remains chronologically ordered across connected, disconnected, and
  recovered periods.
- Storage saturation or terminal media failure is explicit in diagnostics.

## App contract

The storage-first firmware is only testable with an app that honors all of the
following rules:

- never start the legacy live characteristic beside the SD-ring tail;
- reconnect at the newest bounded ring head before repairing recent coverage;
- preserve the active server conversation owner and preview across a transport
  replacement or process restart;
- keep individual sequence WALs local and compact the completed lifecycle
  window into one canonical recording;
- derive the canonical close from the server lifecycle in wall-clock time.
  Transcript offsets alone are invalid for this purpose because pendant VAD
  and disconnected intervals compress the audio clock;
- run historical backlog only after an explicit user request. Charging is not
  authority to compete with live transcription.

The exact authenticated Android/iOS build and provisioning process is recorded
in `app/e2e/CV1_BLACKBOX_DEVICE_TESTING.md`. Do not recreate Firebase files,
bundle identifiers, or signing settings from memory.

## Current physical evidence

Builds 101 and 102 of the diagnostic line were exercised over the app DFU path
and remained recoverable. A 12-hour build-101 firmware export reported no
storage rejection, packet drop, microphone, notification, or sync error; two
link-setup errors recovered and the final link negotiated 15 ms, MTU 498, 2M
PHY, and DLE 251.

Builds 105 and 106 are **not** physically qualified. A later MCUmgr image-list
audit proved the pendant's active, confirmed application core was still
`3.0.30.102`. The supposed build-106 run had selected the build-102 ZIP from
Flutter Documents while the correct build-106 artifact was staged in Android's
native `files` directory. The updater skipped identical application image 0
and refreshed only image 1. Any result previously attributed to build 105 or
106 without a post-reboot active-image listing is invalidated. See
`app/e2e/CV1_BLACKBOX_DEVICE_TESTING.md` for the corrected evidence and exact
artifact hashes.

On the Samsung Android fixture, a forced 23.6-second radio outage reconnected
without app relaunch. The replacement tail read the current 25-record head in
1.9 seconds after app-level connection, then repaired the preceding 96-record
gap. Live preview remained on the same owner. The same run exposed and fixed a
wall-clock ownership defect: STT offsets closed the canonical source before
speech captured after a recovered gap. The regression now uses the configured
conversation-silence lifecycle edge for storage-authoritative close bounds.
The corrected rerun compacted 27 ring WALs into one 69-second, 3,439-frame
canonical file containing the before/offline/after markers in order.

On the iPhone fixture, process termination and relaunch preserved 5,342 frames
across 46 ring fragments with no sequence gap and produced one 107-second
canonical artifact. The production conversation contained the before,
process-down, and recovered markers in order. The remaining negative first
segment offset is a backend projection-origin defect, not firmware loss.

These are targeted reliability passes, not release qualification. The next
gates are an overnight unplugged battery run, a user-authorized large backlog
benchmark, a foreground/background/locked-screen matrix on both phones, and a
wired fault-injection run once the JTAG adapter cable is available. The backend
must also implement the app's existing `transcript_mode=replace` request
atomically. Production currently appends the recovered canonical transcript to
the original live segments, so audio durability passes while final transcript
deduplication remains blocked outside this firmware/app branch.
