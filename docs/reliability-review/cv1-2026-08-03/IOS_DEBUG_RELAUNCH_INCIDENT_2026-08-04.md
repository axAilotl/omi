# iOS debug relaunch incident

Date: 2026-08-04
Status: recovered; operational failure classified

## Symptom

The isolated Omi Dev app died while pulling a historical backup and every
subsequent Home-screen launch exited immediately. The authenticated app
container and pendant archive were not cleared.

## Crash evidence

Five reports were copied from the iPhone into the permanent archive:

    /Users/cgic/Omi-CV1-Reliability-Work/evidence/ios-crashes-2026-08-04

The three final launch attempts at 17:42:19, 17:42:25, and 17:43:15 were
identical:

- EXC_BAD_ACCESS / SIGSEGV on the main thread;
- swift_getObjectType;
- SwiftAwesomeNotificationsPlugin.register(with:);
- GeneratedPluginRegistrant.register(withRegistry:);
- AppDelegate.application(_:didFinishLaunchingWithOptions:).

The app died before Flutter restoration, backup enumeration, or Dart code ran.
This was not evidence of corrupt backed-up audio.

## Cause

The installed artifact was a Flutter debug/JIT build. It had been left running
after detaching flutter run. Once the backup operation caused a real process
death, launching that debug binary from SpringBoard did not have the Flutter
tool attached to prepare the debug runtime. Plugin registration received an
invalid registrar and crashed at the first affected Swift plugin.

This matches the upstream null-registrar/debug-launch failure class:

- https://github.com/flutter/flutter/issues/149214
- https://github.com/flutter/flutter/issues/175088

The notification plugin is where the invalid registrar became observable; the
backup payload and notification state were not the root cause.

## Recovery performed

1. Preserved the crash reports before another launch.
2. Reattached the exact tested debug IPA with flutter run and
   --use-application-binary. It immediately reached the authenticated Home
   widget tree, confirming that the container was intact.
3. Built the same composite source in profile/AOT mode with the production
   Firebase/customer-plane preflight and the isolated bundle identifier.
4. Signed and installed the profile app in place. No uninstall or data clear
   occurred.
5. Launched it without flutter run, terminated PID 5932, and launched it again
   as PID 5933.
6. Confirmed PID 5933 remained alive after the observation interval, no new
   Runner crash report appeared after 17:43, and the existing 1.4 MB app
   preferences file remained in the data container.

## Permanent artifact

    /Users/cgic/Omi-CV1-Reliability-Work/artifacts/build110/OmiBlackbox-build110-composite-profile.app

Identity:

    Runner SHA-256
    833776270fbead60bf9ac754b35e1a43b45a992a39102130ea00c885c5edf39c

    Info.plist SHA-256
    7ea8a5810081ec27766784e7c8d1060fe8fa6c2783218e0278011d629fed4861

    embedded.mobileprovision SHA-256
    1c1d88356dfd5e2d41271a7c2f0861f4284c206b659dc050ad09b0f845ce801f

    arm64 Mach-O UUID
    2E224680-212D-32E8-B0C6-7EE3CFE05471

## Permanent operating rule

- Use debug only while flutter run remains attached for instrumentation.
- Before unattended backup, background, or dogfood use, install the profile
  artifact in place under the same isolated bundle.
- Detach is not qualification that a debug build can cold-relaunch.
- Never recover this condition by uninstalling or clearing app data.
- A backup crash and a subsequent debug-runtime launch crash are separate
  failures; preserve both evidence streams before attribution.

## BLE reclaim follow-up

The first standalone profile process remained alive but the tester did not see
the pendant in the app. That means crash-free launch alone was not a complete
recovery gate.

A subsequent controlled profile relaunch with native console evidence showed:

- CoreBluetooth powered on with the Flutter API installed at 17:57:46;
- exact saved pendant 425529A3-6F68-F264-C0CA-DAC438DA1240 connected at
  17:57:47;
- battery, audio, diagnostic, and transfer notification subscriptions enabled
  by 17:57:51;
- exported firmware 3.0.30, battery 71%, and no mobile BLE error;
- firmware counters with 385,510 audio frames, zero dropped frames, zero sync
  errors, and 152,926,476 historical sync bytes;
- 87,155,868 ring bytes and 196,297 unread packets still available.

The live profile process remained PID 5946 after detaching the local console.
The exported evidence is permanently stored at:

    /Users/cgic/Omi-CV1-Reliability-Work/evidence/build110-ios/omi-blackbox-profile-reconnect-20260804.json

Disposition: the pendant is reclaimed now, but the first profile launch's
missed UI/device state remains an intermittent cold-start bootstrap finding.
Future qualification must require native didConnect, all required
subscriptions, Dart/UI connected state, and live audio—not merely a surviving
process.
