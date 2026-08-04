# CV1 black-box physical testing

This runbook is for `codex/cv1-blackbox-diagnostics` only. It installs an internal diagnostic firmware and dev apps;
it is not a production or beta release procedure.

## Fixed identities and configuration

- Firmware candidate: `3.0.30+110`, built from the `3.0.29`
  storage-first/AAD-policy lineage. Build 110 retains the build-109 durable
  prefix policy and removes the two lower-level SD flushes that build 109 still
  performed from INFO and every latched READ chunk. A bounded transfer now
  reads only its already-durable window while recording continues behind it.
  It was built, sealed, flashed, and physically exercised on iPhone on
  2026-08-04. The firmware durability/transfer gate passed; app/backend
  conversation ownership across a true process death remains a separate
  release blocker documented below.
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

The helper defaults to a profile build. For Marionette/`agent-flutter` UI
assertions on the physical iPhone, build the same preserved bundle as a debug
artifact instead:

```bash
signed_app="$(OMI_IOS_BUILD_MODE=debug ./e2e/scripts/build_signed_ios_physical_dev.sh)"
```

Debug and profile use the same bundle identifier, signing identity, profile,
Firebase project, and customer API. Installation is always an in-place update;
do not uninstall the app to change build modes.

Debug is only for an actively attached flutter run/Marionette session. Do not
hand a detached debug build to a tester for unattended backup or dogfooding:
after a real process death, a physical iPhone may crash that JIT artifact
during GeneratedPluginRegistrant before Dart starts. Before detaching for
unattended use, rebuild with the helper's default profile mode, install it in
place under the same bundle identifier, then prove one terminate/relaunch
cycle. This preserves auth and recordings while producing a standalone AOT
app.

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

Known-good durable local profile source (expires 2027-07-25):

```text
~/Downloads/omi-ios-personal-8c1321a908-20260725/OmiDev-personal-profile-signed.app
```

Do not point the helper at a `/private/tmp` build artifact. Temporary app
directories are cleanup-prone and caused a previously working authenticated
build procedure to fail before compilation. The durable profile above has
application identifier
`6DV84DW2BA.com.omi.reliability.alexsmacbookpro`; the build helper verifies
that identifier again after signing.

Device identifiers:

```text
Flutter/CoreDevice UDID: 00008110-001E4D681E6B801E
CoreDevice ID: D019FCB0-B857-5C7B-95C7-D28071D0E113
```

Use `xcrun devicectl device install app --device D019FCB0-B857-5C7B-95C7-D28071D0E113 <signed-app>` to update in place.
Do not uninstall the existing custom bundle.

For a locked-screen lab run, copy
`Omi_CV1_Blackbox_OTA_3.0.30_build110_SHA8ad0dad0.zip` into the app's Documents
directory and launch the exact internal URL `omi://blackbox/dfu`. The route does
not exist unless `OMI_BLACKBOX_HARNESS=true`, accepts no arbitrary path or
device identifier, waits for the already-paired Omi CV1, and uses the same
`prepareDFUForDevice()`/MCUmgr path as the visible developer screen. Before it
touches BLE it verifies the exact filename, ZIP SHA-256, ZIP members, manifest,
image sizes and hashes, and signed MCUboot application-header version.

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

The raw build output is `omi/firmware/v2.9.0/build/dfu_application.zip`, but do
not stage or flash that generic filename. Copy it to the unique sealed filename
and verify its hash first. Confirm DIS firmware `3.0.30`, MCUboot application
`3.0.30.110`, and active/confirmed state after DFU before collecting data.
The build-110 OTA is
`Omi_CV1_Blackbox_OTA_3.0.30_build110_SHA8ad0dad0.zip`, SHA-256
`8ad0dad061fe637b922d5ed6667a4ac0713ebbe9539fa03ab0744b45e0dcabec`.
The manifest application image is 264,532 bytes with SHA-256
`561ed42eb008440f840d0d3594b0d9cba4a516749511b0858aa8a80cc676bedf`;
the network image is 175,092 bytes with SHA-256
`39df96b86c94ed55dc06d282ca2d4b6c2b3103aa9f64456f8848d650d6dbe9c0`.

Historical artifacts follow for incident reconstruction only; none may be
substituted for build 110. Build 109 was
`Omi_CV1_Blackbox_OTA_3.0.30_build109_SHAc818aa1c.zip`, SHA-256
`c818aa1c1bf16bf0d55250c23aab50d9dd27be50795dbcb3e7c93d1c756e8568`.
It flashed successfully and proved postboot advertising, exact-device iOS
reclaim, live Tango transcription, zero frame drops, and durable-prefix entry.
The process-restart test then recorded 15 prefix entries and 15 sync errors:
the SD worker still drained/flushed the producer tail from INFO and latched
READ, so build 109 failed continuous reconnect qualification. Build 107 was
`Omi_CV1_Blackbox_OTA_3.0.30_build107_SHA052faa45.zip`, SHA-256
`052faa4556c104b467ae60f38e7b76264bc7eb12ba3d3eebfb75eb971dffc4ef`;
it failed the no-touch postboot reconnect gate and has no postboot
active/confirmed proof.
The artifact flashed for the 2026-08-01 physical run had SHA-256
`38c8d25de638eda065b88d04e4be854ce1bdc07b491a199a4fa453ad1ff12393`.
The fresh pinned-gate rebuild from the final source produced SHA-256
`cbebda3e9fce626fe997b535fa76377f42a66d80d9d12e8048c74fc65057ebf8`.
The superseded build 103 artifact containing microphone, bounded-read, and
post-disconnect advertiser recovery fixes has SHA-256
`f1536e940406adc39f8fdc39e1701b0d45a0ffb1b43323caf85d1094cfddf9a3`.
The build 104 artifact that also recovers an initial advertising failure after
application-core wake has SHA-256
`b59a2e5aa21da85e67de19466e4c7af57b6fb762a781a3897062c80d43855bbc`.
The build 105 artifact that adds the system-off release fence and 30-second
emergency cold reboot has SHA-256
`74719711fcdc7a750c03918d59a3566ebdc2a70a95568f5fc26e5611247f449d`.
The build 106 artifact that supervises post-disconnect advertising until a real
connection and records each reset result has SHA-256
`0eec4835d53b0667fee71f1f9f40105a508cd3eeab8f60942d7e5707cd4cd209`.
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

### Recover a powered but off-air CV1

The mainboard has two RGB LED packages, D2 and D7, on the same three control
nets. Both packages showing red is one disconnected/error color and does not
identify two independent hardware faults.

Use the hardware-assisted MCU reset before opening the device or waiting for
the battery to drain:

1. Remove the pendant from the powered magnetic charger.
2. Hold the center user button.
3. While the button is already held, place the pendant on the powered charger.
4. Continue holding for about 2 seconds, then release and scan for advertising.

The charger insertion edge and held button drive the mainboard force-reset
circuit. It is not a storage erase or factory reset. Never short test pads,
battery rails, or FPC pins; the FPC carries battery, reset, and SWD signals.

Firmware on this branch also separates ordinary shutdown from recovery. Three
seconds requests a durability-preserving power-off. The normal path waits for
physical release before arming the button's active-low system-off wake source.
If shutdown returns because audio/SD teardown failed, a continuous hold through
30 seconds issues one cold reboot; begin a new hold if the original was already
released. Release rearms the policy. If the software work queue itself cannot
run, use the charger-button hardware reset above.

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

### 2026-08-04 build-110 iPhone qualification

The checksum-locked iOS harness displayed and flashed exactly
`3.0.30+110` / ZIP `8ad0dad0` / app `561ed42e` / net `39df96b8`, completed
both MCUboot images, and reported `Firmware installed`. A separately installed
production iPhone app initially won CoreBluetooth ownership after the reboot;
terminating only that competing process let the custom app own the pendant.
The original post-DFU dev session did not retry after that ownership loss, so
the custom app required one process restart. This is a dev/prod side-by-side
ownership and bounded-retry defect, not evidence that build 110 stayed off-air.

The clean dev-only run then proved:

- battery and capture state republished as `100%` / `Listening`;
- the pre-outage November marker appeared in live preview;
- a true app-process-down Papa marker was retained by the pendant;
- the relaunched app reclaimed the exact device without user pairing, and the
  post-reconnect Quebec marker appeared in live preview;
- no `Device storage is not ready` error occurred after the build-110
  reconnect, unlike build 109.

The final export at `2026-08-04T19:08:44Z` is stored locally at
`/Users/cgic/Omi-CV1-Reliability-Work/evidence/build110-ios/omi-blackbox-ios-build110-postclose3-20260804.json` (SHA-256
`1a0948cf285eae4023922ceef81e56091fe2bfa53692861feabaaf81214b6236`).
It reported a healthy SD card and 15 ms / MTU 498 / DLE 251 / 2M PHY. All
27,375 audio frames were accepted by storage; storage rejection, frame drop,
microphone read error, SD write rejection, link setup error, and sync error
were all zero. The scheduler completed 132 READ/DONE pairs and durably moved
2,553,000 bytes while capture continued. This is the physical proof that
removing INFO/latched-READ producer-tail flushes fixed build 109's repeated
storage-readiness failure.

The same export also reproduces the remaining semantic blocker without data
loss: exact ring source ranges are continuous across Papa, but the
`19:01:30Z`–`19:03:29Z` app-down interval remains local, unbound `miss` WALs.
Only the later `19:03:32Z`–`19:04:01Z` live owner became a canonical recording.
The raw ranges were not uploaded independently and remain recoverable, but a
transport/process death still became a backend conversation boundary. Do not
claim one-conversation iOS recovery until ownership survives process death and
the backend atomically replaces/merges the canonical transcript by source
coverage.

The final Android diagnostic export is stored locally at
`/private/tmp/omi-blackbox-export-20260802.json` (SHA-256
`163101a0104a9195170136bd4f60629cf79687149f464f9341bc77c1dac4c9e0`).
After 20 pendant connections and 2,853 ring reads it reported zero audio queue
full, storage rejection, frame drop, microphone read, SD write rejection, SD
health, sync, or diagnostics-busy errors. Two of 80 link-setup attempts failed
and recovered. The final link remained 15 ms / MTU 498; battery was 93%.

## 2026-08-03 recovery findings

> **Evidence correction (23:16 run):** the run originally described below as
> build 105/106 qualification did not install either application-core image.
> The harness resolves its fixed ZIP from Flutter's Documents directory
> (`app_flutter` on Android), while the build-106 ZIP had been staged in the
> native Android `files` directory. The DFU log proves that the selected ZIP
> was build 102: image 0 was 264,404 bytes with SHA-1
> `3f1ca5b91e568fe74f2d42f8ce3e78a9574b358f`, exactly matching the retained
> build-102 ZIP. MCUmgr listed active, confirmed application image
> `3.0.30.102` both before and after the transfer. Image 0 was therefore
> skipped as identical and only image 1 was refreshed. The build-105 and
> build-106 observations below are retained as historical hypotheses, not
> physical evidence. Neither build is physically qualified.

Build 102 reproduced two false-ready states that the earlier acceptance run did
not cover:

- The UI remained connected/listening while the ring write sequence was frozen.
  The pendant trace contained 743 consecutive `dmic_read(...)= -EAGAIN` errors.
  On nRF PDM, exhausting the RX slab stops capture; build 104 issues an
  idempotent start on `-EAGAIN` and records `mic_recovery` when the next block
  arrives.
- After recovery, the live tail completed several reads, then a 75-record read
  delivered 72 records and returned status 9 after the 15-second SD-worker
  timeout. The third chunk attempted to re-drain a write queue that live audio
  continuously replenished. Bounded reads now reuse the durable snapshot
  latched before `READ_BEGIN` instead of waiting for the producer to quiesce.
- Force-stopping only the Dev app disconnected GATT, but the pendant did not
  advertise again. The first recovery worker had accepted `-EALREADY` as proof
  that the legacy advertiser was on air; an independent CoreBluetooth scan
  found no Omi advertisement. Build 104 explicitly stopped and restarted that
  advertiser, retried every failed start including `-EALREADY`, and also
  entered recovery when the first advertising attempt after an application-core
  wake failed.
- A long-press appeared to power the pendant off, but the red disconnected LED
  returned several seconds later. Shutdown deliberately restores operation
  when its audio/SD durability gate cannot commit cleanly; treat that symptom
  as a cancelled shutdown, not evidence that either nRF5340 core rebooted.
- In the physical recovery incident, both RGB packages remained red and an
  independent CoreBluetooth scan found no Omi advertisement. Holding the center
  button before placing the pendant on its powered charger restored it. The
  repository history confirms the legacy shutdown path could arm the still-held
  active-low button as a wake source without a release fence; factory firmware
  could therefore appear to turn itself back on as well. Repository issue search
  found no pre-existing public bug report or regression test that named this
  exact race; the behavior was established from the historical implementation
  and the physical reproduction, not from an earlier tracked issue.

The first two observations preserve the ring cursor: no ADVANCE was sent for
the incomplete range. An export attributed at the time to build 105 showed
1,312 audio frames, 1,310 storage accepts, a healthy SD ring, and zero
queue-full, storage-reject, frame-drop, microphone, SD-write, or sync errors.
Because no active-image proof accompanied that export and the later MCUmgr
inspection still showed build 102, it cannot qualify build 105. After
force-stopping Android, independent CoreBluetooth scans found no Omi
advertisement for more than 60 seconds, including after an acoustic wake. That
is valid evidence for the active build-102 baseline only.

Build 106 source waits 1.5 seconds for Zephyr connection-object recycling,
atomically tracks connection state, then refreshes the legacy advertiser at
2/4/8/16/30-second capped intervals until a real connection callback cancels
it. Every reset records `stop_err`/`start_err` in the black-box trace and
increments `ble_advertising_recovery`. Physical qualification requires staging
the exact ZIP in Flutter Documents, verifying its manifest and application
header before DFU, and proving MCUmgr reports active image `3.0.30.106` after
reboot. Only then may the no-touch independent-scan/reconnect test be used as
build-106 evidence.
