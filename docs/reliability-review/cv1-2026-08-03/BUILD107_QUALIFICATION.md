# CV1 build 107 qualification record

Status: **flashed; failed no-touch postboot reconnect; active image unverified**
Built: 2026-08-04 UTC
Branch: `codex/cv1-blackbox-diagnostics`

## Physical result (2026-08-04)

The exact-hash Android gate accepted the sealed artifact and uploaded both
images. Before upload, MCUboot reported build 106 active and confirmed. After
upload, MCUboot reported build 107 in application slot 1 as bootable, pending,
and permanent; the reset command was acknowledged.

The pendant did not return on-air after reset. Three exact-device reclaim
attempts timed out, repeated Android Nearby cycles saw no BLE advertisement,
and a full Android Bluetooth controller off/on followed by a fresh direct
connection also timed out. There is no postboot active/confirmed listing,
DIS revision, or moving RingInfo yet. The harness's `Firmware installed` label
proves terminal DFU command completion only, not a healthy postboot device.

This fails the no-touch post-DFU reconnect gate. It is consistent with the
independent initial-boot advertising gap called out as R1 in the Kimi review,
but a charger/button reset and postboot image list are required to distinguish
an initial advertising failure from a deeper boot problem. See
`evidence/build107/physical-flash-android-20260804.txt`.

## Purpose

Build 107 is the first uniquely identified physical-test candidate after the
post-disconnect root cause was isolated. It removes the speculative advertising
supervisor, balances the referenced `bt_conn` returned to the production button
notification path, and pins the regression with a two-connection BabbleSim
test. It does not claim to qualify transcript assembly, backlog recovery,
battery life, or cross-platform parity.

## Sealed artifacts

The operator-facing copies are in:

`/Users/cgic/Downloads/Omi-CV1-build107/`

| Artifact | SHA-256 |
|---|---|
| `Omi_CV1_Blackbox_OTA_3.0.30_build107_SHA052faa45.zip` | `052faa4556c104b467ae60f38e7b76264bc7eb12ba3d3eebfb75eb971dffc4ef` |
| `Omi_CV1_Blackbox_3.0.30_build107_merged_SHAbae49198.hex` | `bae49198564a3b303b25693e51ff9ad63aa2fb9069d7922e9c5bed98fa7a5fc8` |
| `Omi_CV1_Blackbox_3.0.30_build107_CPUNET_SHA0105787f.hex` | `0105787fa6a08a32bba5df94d19326ebf209c95c1275f41d2327c272745380c4` |
| `Omi_Android_Blackbox_build107_DFU_gate.apk` | `e8c1ba1b38c5af790451e7529e8babc99a2184267c34854db11e3f0704929310` |

The repository evidence is under `evidence/build107/`. The reproducible Linux
workspace and artifacts are also retained at `/mnt/ai/omi-cv1-build107` on the
test host. The repository evidence intentionally excludes the binary OTA and
HEX payloads.

## OTA identity

- ZIP manifest format: `1`
- application image: `omi.signed.bin`, index `0`, 264,388 bytes,
  SHA-256 `6406b8b587e519f9f45b3cdb8f0e3401d977c444e21c0506b7d4efa19c0e36ac`
- network image: `ipc_radio.bin`, index `1`, 175,092 bytes,
  SHA-256 `0a9eee461fdb5b5179000554fa9ae4058c55a88f20fda52ed11a6620ad8e8f3b`
- manifest application version: `3.0.30+107`
- signed MCUboot application header: `3.0.30+107`
- compiled DIS firmware revision: `3.0.30`

The build-specific app verifier accepts only the exact OTA filename above and
then verifies the ZIP digest, member set, manifest identities, member sizes and
digests, MCUboot magic, and signed-header version before it is allowed to
suspend BLE for DFU. A same-name package with different bytes is rejected.

## Automated evidence

All of the following passed:

1. macOS host-native firmware tests: 2/2 (`audio_storage_packer_tests` and
   `blackbox_trace_tests`);
2. firmware version synchronization check;
3. fixed two-connection BabbleSim test: production button notification,
   disconnect at simulated 2.621814 seconds, reconnect at 2.730632 seconds,
   and `OMI_BSIM_PASS` at 5.182120 seconds;
4. deliberately leaky BabbleSim control: explicit
   `OMI_BSIM_FAIL reconnect -11` at 17.621827 seconds with no PASS;
5. complete pinned NCS 2.9 sysbuild;
6. local `sha256sum -c SHA256SUMS` over all sealed operator artifacts;
7. Flutter build-artifact verifier tests, including tamper and wrong-identity
   rejection;
8. exact-device DFU ownership tests, including a DFU request before the
   provider's debounced `connectedDevice` state is populated;
9. production verifier tool against the sealed OTA, which reported
   `verified 3.0.30+107` with all three expected digest prefixes;
10. the app analyzer ratchet.

The Android black-box application also completed a real `assembleDevDebug`
build with the build-107 verifier compiled into the DFU harness. The sealed APK
is the one listed above; it has not been installed.

The first remote build invocation stopped immediately because the source-sync
exclude pattern also excluded `build-cv1.sh`. The script was copied explicitly
and the full pinned build then passed. No artifact from the stopped invocation
is used here.

## Physical qualification gate

Build 107 has been uploaded but is **not physically qualified**. Do not record
it as installed or working until all of these are captured:

1. the app displays the verified exact filename, version, and hash summary
   before starting DFU;
2. MCUmgr shows `3.0.30.107` pending before reboot;
3. postboot MCUmgr shows the application active and confirmed;
4. the pendant reports DIS revision `3.0.30` and moving RingInfo with
   `dropped=0` during a unique audible marker;
5. at least 25 button event -> disconnect -> independent advertisement ->
   exact-device reconnect cycles pass without a hardware reset;
6. Android and iOS independently pass live-preview recovery on this exact OTA;
7. backlog drain remains explicit and does not steal the live lane.

The merged HEX build reports the existing generated NSIB-key warning and is a
laboratory full-flash image, not a production-signing claim. The OTA continues
to use the configured MCUboot signing path.
