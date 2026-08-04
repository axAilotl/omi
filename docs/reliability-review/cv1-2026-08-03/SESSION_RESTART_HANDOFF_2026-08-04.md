# CV1 reliability session restart handoff

Authoritative as of 2026-08-04 after the build-110 physical iPhone pass.

This file is the minimum context a fresh engineering session must read before
changing or retesting the CV1 reliability stack. Read it together with
`BUILD110_IOS_FINAL_QUALIFICATION.md` and
`KIMI_IOS_PROCESS_RECOVERY_SUMMARY_2026-08-04.md`.

## Product contract

- The pendant SD ring is the durable source of truth.
- Normal connected behavior prioritizes live preview.
- A gap inside the still-open conversation may repair automatically.
- Old unrelated history drains only after Sync or the existing Auto Sync
  opt-in. Charging alone is never transfer authority.
- Physical ring/archive boundaries are not conversation boundaries.
- Short raw fragments remain local until one ordered canonical owner is proven.
- Advance/delete the pendant cursor only after durable local acceptance.
- Android and iOS share policy; native code owns transport mechanics only.
- Transport or process death inside the conversation boundary must not create a
  second conversation.

## GitHub surfaces

- Firmware draft: BasedHardware/omi #10654,
  `codex/cv1-storage-authoritative-demo` on the fork.
- Shared Android/iOS app draft: BasedHardware/omi #10656,
  `codex/cv1-storage-first-app` on the fork.
- Separate iOS serialized GATT/DFU draft: BasedHardware/omi #10573,
  `codex/ios-ble-dfu-reliability` on the fork.
- Broad internal diagnostic branch: `codex/cv1-blackbox-diagnostics`.
- Physical composite qualification branch: `codex/ios-build110-qualification`.

The composite qualification branch is evidence/integration scaffolding, not a
replacement for the reviewable platform PRs. Do not merge the broad black-box
stack as one production PR.

## Local worktrees

```text
/private/tmp/omi-cv1-blackbox
  codex/cv1-blackbox-diagnostics

/private/tmp/omi-cv1-end-to-end-pipeline
  codex/cv1-end-to-end-pipeline
  remote PR head: fork/codex/cv1-storage-first-app

/private/tmp/omi-ios-build110-qualification
  codex/ios-build110-qualification
```

Before rebasing or cleaning any of them, run `git status -sb`, save the diff,
and confirm which PR owns each file. Existing changes belong to this experiment.

## Build-110 identities

```text
Firmware ZIP SHA-256
8ad0dad061fe637b922d5ed6667a4ac0713ebbe9539fa03ab0744b45e0dcabec

Firmware application SHA-256
561ed42eb008440f840d0d3594b0d9cba4a516749511b0858aa8a80cc676bedf

Firmware network SHA-256
39df96b86c94ed55dc06d282ca2d4b6c2b3103aa9f64456f8848d650d6dbe9c0

Composite iOS IPA SHA-256
2ddaf0e3c63a6cf49f0630d9fa5858ca1306056aaa0a58d255f9f5f14b94db8f
```

Never identify a DFU package by its display filename alone. Hash the ZIP,
manifest, signed application header, and network image before suspending BLE.

## Physical iOS setup that works

- Isolated bundle: `com.omi.reliability.alexsmacbookpro`.
- Use the production Firebase account universe and canonical
  `https://api.omi.me/` customer plane.
- Reuse the signed isolated bundle to preserve auth and pairing.
- Build with `app/e2e/scripts/build_signed_ios_physical_dev.sh`.
- For an exact prebuilt composite, use Flutter's
  `--use-application-binary=<IPA>` option.
- Run `agent-flutter connect <VM-service-websocket>` and use ref-based controls
  on physical iOS. ADB-backed commands do not work.

### Critical inventory quirk

`xcrun devicectl device info apps` shows developer apps by default and can hide
the App Store Omi app. Always use `--include-all-apps` before claiming only one
BLE owner exists. Production Omi is
`com.friend-app-with-wearable.ios12`; Omi Dev is
`com.omi.reliability.alexsmacbookpro`.

On the dedicated final-pass phone, the user authorized uninstalling production
and the all-app postflight proved only Omi Dev remained.

### Debugger/process quirks

- `q` in `flutter run` terminates the application; `d` detaches and leaves it
  running.
- Do not send a raw `devicectl` SIGKILL while the Flutter debugger is attached;
  the debugger can intercept it and leave the UI apparently frozen. Quit or
  detach first.
- Do not touch Listening during a no-touch preview gate. Tapping only navigates;
  it is not a valid recovery action.
- Debug console noise includes Firebase logging `bad URL` messages and a
  duplicate `FileUtils` Objective-C class warning. Neither is a proven freeze
  cause.

## Physical test sequence

1. Prove exactly one app owns the pendant.
2. Record firmware/app artifact identities.
3. Quit the app completely.
4. Power-cycle the pendant.
5. Cold-launch the exact app artifact.
6. Leave Home untouched and record when BLE connected, GATT became ready, ring
   tail became ready, socket became ready, first audio became durable, first
   transcript arrived, and preview painted.
7. Speak a unique marker and capture +5/+15/+30 screenshots without tapping.
8. Open Sync through the device page and explicitly tap Sync.
9. Return Home, speak another marker, and prove live preview continues while
   device storage decreases.
10. After drain, audit source ranges for duplicate canonical/backfill ownership,
    short-fragment spam, and wrong-conversation attachment.

The 2026-08-04 pass completed steps 1–9. Step 10 remains open.

## What is proven

- Build-110 firmware transport accepted 27,375/27,375 frames with zero recorded
  drops and zero sync errors.
- The final iOS composite restored preview after cold app + pendant restart
  without opening Listening.
- A controlled marker was visible at the five-second sampling checkpoint.
- User-authorized historical drain and live preview coexisted.
- Storage moved from 196 MB to 195 MB during the controlled interval and the
  user later observed 188 MB.

## What is not proven

- Five seconds is not a cold-launch-to-first-text measurement; it is measured
  from marker completion to the first scheduled screenshot.
- The entire 560-recording backlog has not been completion-audited.
- Process-death recovered WALs are durable but are not yet guaranteed to bind
  into the original canonical conversation.
- Backend summary/event regeneration and exact final timeline replacement are
  not qualified.
- Battery, thermal behavior, desktop parity, and a final Android repeat remain
  open.

## Immediate next engineering work

1. App: persist a boundary-validated conversation-session checkpoint and
   harden pre-socket reclaim.
2. Backend: add authoritative conversation start to the session event and
   reset inactivity accounting on resume.
3. App: add phase timing for cold first-preview latency.
4. App: finish the post-drain duplicate/semantic audit.
5. Qualification: matched battery/thermal and Android/iOS parity runs.

Do not weaken raw-fragment upload guards or blindly append to a completed
canonical to solve the ownership problem. Repair the owner and boundary.
