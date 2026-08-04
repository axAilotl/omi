# CV1 build 108 qualification record

## Status

Build 108 is **built and sealed, but not flashed or physically qualified**.
It is the next laboratory candidate after the physical build-107 run exposed a
live-path failure: after an initially healthy storage-authoritative session, a
transient partial-tail flush failure cleared `storage_snapshot_ready`. Every
subsequent `CMD_RING_INFO` was then rejected with status 9 (`STORAGE_NOT_READY`)
even though the SD ring had already published readable durable packets.

Build 108 makes snapshot readiness monotonic for a BLE connection. The first
successful commit publishes a readable window; a later failed attempt may delay
only the newest partial tail and schedules another commit retry, but cannot
revoke access to the already-durable window. Disconnect/reconnect remains the
explicit boundary that clears the latch and requires a new initial commit.

## Sealed artifacts

Local artifact directory:

`/Users/cgic/Downloads/Omi-CV1-build108/`

| Artifact | SHA-256 |
| --- | --- |
| `Omi_CV1_Blackbox_OTA_3.0.30_build108_SHAdc04db60.zip` | `dc04db60610baf34494f321c171f377d1f15cc728e05b1c9a22577eb4e78d8fd` |
| `Omi_CV1_Blackbox_3.0.30_build108_merged_SHAe4128f57.hex` | `e4128f574ffee4739f6a10defc225623cb03f73333b335a0fd13bc2528c8cf80` |
| `Omi_CV1_Blackbox_3.0.30_build108_CPUNET_SHA373bfb76.hex` | `373bfb76e4646df11bb3bc4c28ee42cc0b33280ca8f00c5a0b782820f5595ca8` |

OTA contents:

| Member | Size | SHA-256 |
| --- | ---: | --- |
| `omi.signed.bin` | 264,404 bytes | `7b811baf621a2568fc4e64d65feccdd2634bddb69328c4bdcc1e25de1f2556c8` |
| `ipc_radio.bin` | 175,092 bytes | `f39e947d3b074c9a090eb2421cb41f9c19962d984614fb76277aad110722acd6` |
| `manifest.json` | 903 bytes | not independently sealed |

The OTA manifest reports application `3.0.30+108`; MCUboot `imgtool dumpinfo`
independently reports signed application-header version `3.0.30+108`.

## Automated evidence

- macOS host-native firmware tests: 2/2 passed;
- pinned Zephyr CI image host-native firmware tests: 2/2 passed;
- pinned NCS 2.9 CV1 sysbuild: passed;
- output generated: `dfu_application.zip`, `merged.hex`, and
  `merged_CPUNET.hex`;
- no phone app was rebuilt for this artifact and no physical device was
  flashed.

The regression test drives the production policy seam through the exact state
sequence observed on hardware: initial failure remains not-ready, a successful
commit publishes readiness, and a later failure preserves readiness. The
connection lifecycle still clears the state before a new session.

## Required physical qualification

Do not call build 108 stable until all of these pass on the exact sealed OTA:

1. pre-DFU MCUmgr image list records the current active/confirmed build;
2. OTA upload bytes and hashes match this record;
3. post-reset advertising and exact-device reconnect succeed without a charger
   or button intervention;
4. postboot MCUmgr shows `3.0.30.108` active and confirmed;
5. continuous live speech remains readable for at least 15 minutes while
   repeated tail commits occur;
6. Android Bluetooth off/on and app force-stop/relaunch resume the same live
   conversation and do not produce a permanent status-9 loop;
7. a deliberate transient SD/flush fault preserves already-durable live audio,
   retries the newest partial tail, and recovers without a device reset;
8. manual backlog drain remains opt-in and does not preempt the live lane.

Build 107 also failed the no-touch post-DFU advertising/reconnect gate. Build
108 does not claim to repair that independent boot-time failure; it must be
measured again before any broader test or release recommendation.
