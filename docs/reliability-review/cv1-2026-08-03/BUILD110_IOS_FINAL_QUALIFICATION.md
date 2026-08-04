# Build 110 iOS composite physical qualification

Date: 2026-08-04 UTC
Status: team-test evidence; not a public-release qualification

This document records the final physical iPhone pass performed after the
build-110 firmware durability run. It supersedes any claim that the iOS home
preview still requires opening the Listening card, but it does **not** claim
that cold-launch-to-first-text latency is five seconds.

## Exact test surfaces

- Firmware artifact:
  `Omi_CV1_Blackbox_OTA_3.0.30_build110_SHA8ad0dad0.zip`
- Firmware ZIP SHA-256:
  `8ad0dad061fe637b922d5ed6667a4ac0713ebbe9539fa03ab0744b45e0dcabec`
- Application image SHA-256:
  `561ed42eb008440f840d0d3594b0d9cba4a516749511b0858aa8a80cc676bedf`
- Network image SHA-256:
  `39df96b86c94ed55dc06d282ca2d4b6c2b3103aa9f64456f8848d650d6dbe9c0`
- Composite iOS IPA:
  `OmiBlackbox-build110-composite-debug.ipa`
- Composite IPA SHA-256:
  `2ddaf0e3c63a6cf49f0630d9fa5858ca1306056aaa0a58d255f9f5f14b94db8f`
- Isolated bundle identifier:
  `com.omi.reliability.alexsmacbookpro`
- Customer plane: production Firebase account universe and
  `https://api.omi.me/`

The composite iOS app contained the storage-authoritative app stack plus the
serialized, session-bound CoreBluetooth scheduler, notification coalescing,
notification hot-path routing, bounded reconnect ownership, and restored
peripheral session reactivation from the iOS reliability work.

## BLE ownership correction

The first device inventory used `devicectl device info apps` without
`--include-all-apps`. That command lists developer apps by default and hid the
App Store Omi installation. An all-app inventory found both owners:

- production: `com.friend-app-with-wearable.ios12`
- isolated test app: `com.omi.reliability.alexsmacbookpro`

The user explicitly authorized removal of production from this dedicated test
phone. Production was uninstalled and a second all-app inventory proved that
only Omi Dev remained. This matters: two CoreBluetooth-restoring applications
on one iPhone can race for the single-connection pendant and invalidate blank
preview/reconnect evidence.

Always use this inventory form for future physical iOS BLE tests:

```sh
xcrun devicectl device info apps --include-all-apps --device <device>
```

## Cold app plus pendant power-cycle gate

Sequence:

1. Quit the previous Flutter run cleanly.
2. Terminate the detached isolated app process.
3. Have the user power-cycle the pendant.
4. Launch the exact prebuilt composite IPA with `flutter run
   --use-application-binary=...`.
5. Leave the app on Home and do not tap Listening.
6. Capture a blank Listening baseline.
7. Speak one unique TTS marker and inspect the home preview at fixed offsets.

Marker `Uniform` was spoken from `2026-08-04T19:49:49Z` through
`19:50:00Z`. The home preview contained marker text in the screenshot taken
five seconds after the marker finished, and still contained live text at the
fifteen-second checkpoint. The Listening card was never opened.

Result: **pass** for automatic preview delivery after cold app launch plus
pendant power cycle.

### Latency caveat

The five-second number is measured from the **end of the controlled marker** to
the first scheduled screenshot. It is not measured from app process launch,
pendant power-on, BLE connection, GATT readiness, or first spoken syllable.
Ambient speech before the marker may also have warmed the STT session.

The current run therefore proves:

- no tap is required to make preview text appear;
- the restored/cold connection can deliver live text;
- steady-state marker-to-visible-preview was at most about five seconds at the
  sampled checkpoint.

It does not yet prove a cold-launch first-text SLO. A future run must timestamp
`app_launch`, `ble_connected`, `gatt_ready`, `ring_tail_ready`,
`first_audio_durable`, `socket_ready`, `first_transcript_segment`, and
`preview_painted` separately.

## Manual backlog coexistence gate

The Sync screen initially showed:

- 560 recordings ready to sync;
- 196 MB of 470 MB used (42% full);
- historical transfer idle until the explicit Sync tap.

The tester tapped Sync, returned to Home, and left the transfer running. Marker
`Victor` was spoken from `2026-08-04T19:51:16Z` through `19:51:26Z`. Its text
was visible on Home at the five-second checkpoint while the historical upload
remained active.

During the same interval:

- device storage dropped from 196 MB / 42% to 195 MB / 41%;
- the logical recording count rose from 560 to 561 because new live capture
  continued while old data drained;
- no preview interruption, BLE disconnect, or whole-app freeze was observed;
- the user later observed storage at 188 MB, corroborating continued drain.

Result: **pass** for live-preview priority during a user-authorized historical
drain. This is not evidence that the entire backlog completed.

## Firmware evidence retained from build 110

The earlier build-110 physical transport run accepted 27,375 of 27,375 frames,
reported zero drops and zero sync errors, completed 132 INFO/READ/DONE
transactions, and transferred about 2.55 MB while SD health remained good.

Nothing in the final iOS pass points to a new pendant-side defect. The open
first-preview latency question spans app BLE ownership, GATT setup, durable ring
tailing, socket/auth readiness, server STT, and UI publication. Firmware should
only be blamed if phase timing shows the BLE-to-first-durable-audio interval is
dominant.

## Open qualification items

1. Let the manual drain complete, then audit canonical source ranges against
   historical archive manifests for duplicate binding.
2. Verify recovered process-death audio binds into the original conversation;
   durable bytes alone are not semantic success.
3. Measure cold-launch phase latency rather than inferring it from a five-second
   screenshot cadence.
4. Reproduce or clear the occasional whole-app freeze under a timeline trace.
5. Run matched battery/thermal measurements with live only, manual drain only,
   and live plus drain.
6. Repeat the final matrix on Android and desktop against the same firmware
   identity.

## Debug-build warnings observed

The physical debug console repeatedly emitted a Firebase logging `bad URL`
warning for `firebaselogging-pa.googleapis.com` and a duplicate Objective-C
class warning for `FileUtils` in OSAnalytics and Runner. Neither was proven to
cause the reported UI freezes. They must remain hypotheses until a timeline or
main-thread sample correlates one with a stall.

## Disposition

The physical result supports continued team dogfooding and a **go** for the
bounded final gate. It does not support public promotion until the post-drain
semantic audit and process-death conversation-ownership fix are complete.
