# CV1 black-box physical testing

This runbook is for `codex/cv1-blackbox-diagnostics` only. It installs an internal diagnostic firmware and dev apps;
it is not a production or beta release procedure.

## Fixed identities and configuration

- Firmware: `3.0.30+101`, built from the `3.0.29` storage-first/AAD policy lineage.
- Android black-box package: `com.friend.ios.dev.blackbox`. It is installed beside the authenticated `com.friend.ios.dev` app,
  whose signing key is not present locally; the original app and its recordings must remain untouched.
- iOS test package: `com.omi.reliability.alexsmacbookpro`, team `6DV84DW2BA`. Updating this exact bundle preserves the signed-in app data and keychain access group.
- Physical Firebase project: `based-hardware`. `based-hardware-dev` is a placeholder on this machine and must never be used for a physical auth test.
- The app admits `3.0.30` to the storage-authoritative live-audio lane only when compiled with
  `OMI_BLACKBOX_HARNESS=true`. Ordinary app builds still fail closed for every version except the production test line `3.0.29`.
- Canonical ignored inputs live outside Git at `~/.config/omi-mobile-test`. They include `dev.env`, the generated Envied files,
  and both platform Firebase registrations. Never run `flutterfire configure` for this flow. The bootstrap finishes by running
  the repository's Android and iOS customer-plane preflights; either failure is a hard stop before building or installing.

Bootstrap from the app directory. The script aborts unless Android JSON, iOS plist, and both Dart platform options all say
`based-hardware`:

```bash
./e2e/scripts/bootstrap_physical_dev_config.sh
flutter config --jdk-dir /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
flutter pub get
```

Do not substitute `flutterfire configure`, a generic `flutter run`, the
`based-hardware-dev` Firebase project, a new iOS bundle identifier, or an app
uninstall. Those are the previously observed causes of the auth-success stall,
lost device identity, and provisioning churn. Re-run the bootstrap and the
platform build helper instead; both are idempotent and fail before installation
if the customer-plane identity has drifted.

## Build and update Android without losing auth

```bash
blackbox_apk="$(./e2e/scripts/build_android_blackbox.sh)"
adb -s R5CY70NZW5X install -r "$blackbox_apk"
./e2e/scripts/clone_android_test_identity.sh
adb -s R5CY70NZW5X shell am force-stop com.friend.ios.dev.blackbox
adb -s R5CY70NZW5X shell monkey -p com.friend.ios.dev.blackbox 1
```

The clone copies only the existing auth/pairing preferences and Firebase auth store, never recordings or WAL files, and forces
automatic offline sync off. Confirm the package is `com.friend.ios.dev.blackbox` before testing. Do not uninstall, update, or clear
the original `com.friend.ios.dev` app.
The build helper temporarily selects the workstation debug key that signed the already-authenticated side-by-side package, verifies
the resulting APK certificate, and restores the repository's normal physical-test key selection before returning.
The dev build disables Crashlytics mapping upload locally; it must not depend on the symbols endpoint to produce an APK.

## Build and update the signed iPhone app without losing auth

The personal profile does not contain Omi's production entitlements or companion targets. The checked-in helper builds the dev
Flutter payload without signing, copies it without companion plug-ins, installs the known-good profile, signs every framework and
the app with the same identity, and verifies the result:

```bash
signed_app="$(./e2e/scripts/build_signed_ios_physical_dev.sh)"
xcrun devicectl device install app --device D019FCB0-B857-5C7B-95C7-D28071D0E113 "$signed_app"
```

The resulting app must have all of these properties before installation:

```text
CFBundleIdentifier = com.omi.reliability.alexsmacbookpro
application-identifier = 6DV84DW2BA.com.omi.reliability.alexsmacbookpro
Firebase PROJECT_ID = based-hardware
no PlugIns/ or Watch/ payloads
```

Never stop `/Applications/Omi.app`, `Omi Beta.app`, or the production iPhone
bundle. Install the exact custom bundle in place. iOS may relaunch that custom
bundle for CoreBluetooth restoration; when handing the pendant to Android,
disable iPhone Bluetooth or terminate only the custom dev bundle.

Known-good local shell/profile source:

```text
/private/tmp/omi-ios-storage-first-known-good-auth-20260729.o1Z4dQ/OmiDev-storage-first.app
```

Device identifiers:

```text
Flutter/CoreDevice UDID: 00008110-001E4D681E6B801E
CoreDevice ID: D019FCB0-B857-5C7B-95C7-D28071D0E113
```

Use `xcrun devicectl device install app --device D019FCB0-B857-5C7B-95C7-D28071D0E113 <signed-app>` to update in place.
Do not uninstall the existing custom bundle.

For a locked-screen lab run, copy the fixed-name artifact into the app's Documents directory and launch the exact internal URL
`omi://blackbox/dfu`. The route does not exist unless `OMI_BLACKBOX_HARNESS=true`, accepts no arbitrary path or device identifier,
waits for the already-paired Omi CV1, and uses the same `prepareDFU()`/MCUmgr path as the visible developer screen.

After the pendant reconnects, launch `omi://blackbox/export`. That exact opt-in
route writes `omi-blackbox-export-latest.json` to the app Documents directory.
The export contains the firmware and hardware revisions, pendant counters and
event ring, SD-ring status, and native mobile BLE disconnect/reconnect history.
It accepts no command, file path, or device identifier from the URL.

## Firmware build and DFU

Run the pinned build from the repository root:

```bash
docker run --rm \
  -v "$PWD/omi/firmware:/omi/firmware" \
  -e CMAKE_PREFIX_PATH=/opt/toolchains \
  ghcr.io/zephyrproject-rtos/ci:v0.26.13@sha256:b0ac6334d1926cd0971a0a444f7adc6dd020e88ee3ce865aa070b6475a3ac4eb \
  bash /omi/firmware/scripts/ci/build-cv1.sh
```

The OTA artifact is `omi/firmware/v2.9.0/build/dfu_application.zip`. Confirm firmware `3.0.30` after DFU before collecting data.
The artifact flashed for the 2026-08-01 physical run had SHA-256
`38c8d25de638eda065b88d04e4be854ce1bdc07b491a199a4fa453ad1ff12393`.
The fresh pinned-gate rebuild from the final source produced SHA-256
`cbebda3e9fce626fe997b535fa76377f42a66d80d9d12e8048c74fc65057ebf8`.
Record a new hash after every rebuild and never substitute one artifact's hash
for another physical run's evidence.

## Test order and evidence

Only one phone owns the pendant at a time. Use Android first, disable Android Bluetooth before iOS, and reverse that order when
returning to Android.

For each platform:

1. Start a 12-hour pendant trace in Device diagnostics.
2. Verify connected means battery updates and live transcription preview receives spoken TTS.
3. Toggle phone Bluetooth off for 15 seconds, continue TTS, re-enable Bluetooth, and measure reconnect/preview recovery.
4. Leave the app backgrounded and repeat the interruption.
5. Initiate SD sync explicitly; verify live preview remains usable and no unsolicited backlog drain starts merely because the pendant is charging.
6. End a continuous 5-minute speech sample and verify it does not become one-second recordings or multiple conversations without the two-minute boundary.
7. Export Device diagnostics. The JSON includes mobile BLE history, OS identity, pendant snapshot/counters, trace events, and SD ring status.

For Samsung radio testing, `adb shell svc bluetooth disable` can return a
non-zero shell status even after printing `disable: Success`, and the phone may
restore Bluetooth automatically. Do not put the disable command in an
`errexit` script. Start the offline TTS immediately after it, record the actual
GATT disconnect/reconnect timestamps from logcat, and run the enable/recovery
step separately.

The pendant keeps exact cumulative counters for every observed frame, error, and sync operation. High-frequency timeline events are
sampled by event class (1 second to 5 minute minimum spacing, depending on the event) so a sustained failure cannot overwrite hours of
connection history in seconds. Connect/disconnect, negotiated-link, boot, trace-lifecycle, and storage-health transitions remain
available as discrete timeline events.

Capture Android logs with `adb logcat` and iOS logs with `xcrun devicectl device process launch --console`. Record firmware version,
phone OS, wall-clock start/end, initial/final battery, ring unread counts, live-preview recovery time, recording durations, and any
server processing IDs. Never delete pendant or production recordings as part of this diagnostic flow.

## 2026-08-01/02 black-box results

The 3.0.30+101 firmware export was clean: no queue-full, storage-reject,
microphone, dropped-frame, notification, or sync error was recorded. Two
link-setup errors recovered. The steady Android link used a 15 ms interval, MTU
498, 2M PHY, and DLE 251. The firmware artifact SHA-256 is recorded above.

Android physical reconnect evidence from the final scheduler build:

- Bluetooth disconnected at 21:35:56.090 and GATT reconnected at
  21:36:19.654, a 23.564-second transport outage.
- Dart reported connected at 21:36:20.050 and began the newest 25-record head
  read at 21:36:21.996 (1.946 seconds later).
- The following transfer repaired the immediately preceding 96-record gap;
  old history did not run ahead of the live head.
- Preview resumed without a new user connection or app launch. Existing
  preview state is preserved when present; an empty preview remains empty until
  the server returns its first segment.
- The run exposed an audio-clock/wall-clock mismatch in canonical ownership.
  Storage-authoritative completion now uses the configured silence lifecycle
  edge as the wall-clock lower bound and retains transcript offsets only as an
  additional signal. Focused regression coverage pins both storage and legacy
  policies.
- The rerun closed at the exact intended wall-clock window: 27 physical ring
  WALs became one canonical replacement with 3,439 frames over 69 seconds
  (01:35:39–01:36:47). It contains pre-outage Lima, Bluetooth-off Mike, and
  post-reconnect November in that order. Production returned all three.
- Production also appended the canonical transcript beside the original Lima
  and November live segments. The client sent `transcript_mode=replace`, but
  `/v2/sync-local-files` does not declare that query parameter. Atomic backend
  replacement is therefore a release prerequisite; app-side audio durability
  is proven, transcript deduplication is not.

iOS physical process-restart evidence from the same shared Dart ownership
code, before the final wall-clock-bound rebuild:

- the custom dev app was killed for 19 seconds and relaunched in place;
- it reclaimed the exact in-progress server owner before opening the socket;
- 46 ring fragments contained 5,342 frames with zero sequence gaps across the
  before/down/after interval;
- one 107-second canonical artifact was published, and the production result
  contained the three spoken markers in order.

The iOS app must be rebuilt and installed from the helper after every shared
Dart change. A signed app built before the Android boundary fix is stale even
if its native Swift payload is unchanged.

The final shared-Dart iOS build was installed in place from
`/private/tmp/omi-ios-blackbox.OzDVPz/OmiBlackbox.app`. The production process
remained running at its original path and PID throughout. Oscar produced a
live completed conversation. The custom dev process was then terminated at
01:49:46, Papa was spoken during the process-down interval, the app relaunched
at 01:50:01, and Quebec produced a live completed conversation after recovery.

The phone persisted 33 exact contiguous ring ranges covering
`[1724089, 1725811)` with no source-sequence gap across that test. This proves
iOS transport recovery and local durability on the final shared scheduler.
It does **not** prove final semantic parity: Papa remained in durable local
`miss` ranges and was not attached automatically after the backend had already
closed Oscar. Without app-local speech proof, timestamp proximity alone cannot
safely decide whether an offline interval is conversation speech or keyboard/
pocket noise. Release therefore still requires either a real local VAD-backed
ownership signal or an atomic backend canonical replacement/merge contract.

The custom iOS container currently has 936 Documents files accumulated across
the earlier tests, including large historical recordings. That is a credible
cause of the observed slow sync UI and large WAL-manifest work; this run did
not delete user recordings or use container cleanup as a performance fix.

The final Android diagnostic export is stored locally at
`/private/tmp/omi-blackbox-export-20260802.json` (SHA-256
`163101a0104a9195170136bd4f60629cf79687149f464f9341bc77c1dac4c9e0`).
After 20 pendant connections and 2,853 ring reads it reported zero audio queue
full, storage rejection, frame drop, microphone read, SD write rejection, SD
health, sync, or diagnostics-busy errors. Two of 80 link-setup attempts failed
and recovered. The final link remained 15 ms / MTU 498; battery was 93%.
