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
