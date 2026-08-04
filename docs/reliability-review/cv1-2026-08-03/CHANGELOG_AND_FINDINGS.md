# Changelog and findings

## Work chronology

### 1. BLE reliability baseline (2026-07-25)

Firmware work added durable app acknowledgement before discard, honored the
phone's negotiated connection interval, retained audio through BLE/SD faults,
synchronized dual-core OTA versions, increased controller capacity, and made
offline recovery fail closed. Android work serialized GATT operations, bound
callbacks/completions to a connection session, added reconnect/backoff behavior,
and preserved exact-device ownership through DFU.

The key architectural shift was from fire-and-forget notification reliability
to durable source-range reliability: the pendant retains audio until a complete
range is stored on the phone and acknowledged.

### 2. Storage-first line (2026-07-26 through 2026-07-28)

Firmware 3.0.29 made the SD ring authoritative, added silence gating before
durable capture, retained capture identity across reconnect, bounded storage
readiness recovery, and preserved capture while awake.

Shared Flutter work separated the live head, recent repair, and historical
backlog lanes; made backlog reads transactional; assembled physical WALs into
conversation-bound canonical audio; preserved live preview identity across
reconnect; compacted overlaps; bounded startup recovery; and stopped charging
from automatically granting deep-drain authority.

Android physical acceptance proved exact-device reconnect, current-conversation
recovery, zero dropped ring records, one logical canonical file, and no
automatic old-history drain while Auto Sync was off. A production WebSocket 503
demonstrated useful failure separation: the pendant/phone durability path
continued while live transcription was unavailable.

### 3. iOS parity and restoration (2026-07-29 through 2026-07-30)

iOS revalidated already-connected CoreBluetooth peripherals after process
restart, republished readiness, and released unapproved OS-restored ownership
when background mode was not enabled. Shared app policy remained the owner of
conversation assembly and backlog scheduling.

Physical iOS evidence proved contiguous source coverage and one canonical audio
artifact across a process-down interval. It also exposed the backend timeline
bug: recovered audio survived, but the final conversation retained the later
live-session origin and reported the wrong duration.

### 4. Product contract and truthful UI (2026-07-31)

`INV-CAPTURE-1` documented that the silence timeout, not transport lifecycle,
owns conversation boundaries. The app added reconnect-state UI, logical Sync
rows with playback, and reproducible production-Firebase/customer-plane
preflights for physical dev builds.

### 5. Black-box diagnostics (2026-08-01 through 2026-08-03)

Firmware added sampled trace events, cumulative counters, storage/ring health,
link parameters, and bounded diagnostic export. The app added authenticated
internal DFU/export routes and preserved storage-first capture through
reconnects. Diagnostic log writes were serialized after concurrent append/
rotation corrupted the evidence log.

Build 102 exposed two failures that a simple Connected/Listening check missed:

- 743 consecutive PDM `-EAGAIN` reads left the UI healthy while the ring write
  cursor was frozen.
- A bounded read timed out after delivering 72 of 75 records because it tried
  to drain a producer queue that live capture continuously replenished.

Source fixes now restart PDM idempotently and latch an immutable durable read
snapshot. Additional source work added a button-release fence, a 30-second
emergency reboot, and an advertising supervisor. Those later builds have not
yet been physically qualified.

## Firmware build ledger

| Build | Intended delta | Evidence status |
|---|---|---|
| 3.0.30+100 | Initial diagnostic artifact retained on phone. | Artifact identified; not used as current qualification. |
| 3.0.30+101 | Black-box trace/counter run. | **Physical proof:** 12-hour export, final 15 ms/MTU 498/2M/DLE 251 link, zero reported storage/frame/mic/sync errors in that run. |
| 3.0.30+102 | Reconnect/capture diagnostic baseline. | **Physical proof:** active and confirmed by MCUmgr on 2026-08-03; currently the last known bootable app core. Reproduced PDM false-ready and off-air-after-disconnect. |
| 3.0.30+103 | Mic recovery, immutable bounded-read work, advertiser recovery iteration. | **Source present; physical identity not proven.** |
| 3.0.30+104 | Adds recovery for initial advertising failure after app-core wake. | **Source present; physical identity not proven.** |
| 3.0.30+105 | Adds shutdown release fence and emergency cold reboot. | **Source present; prior physical attribution invalidated/insufficient.** |
| 3.0.30+106 | Atomic delayed advertiser supervisor with 2/4/8/16/30-second refresh cadence. | **Source present; not installed.** Correct artifact passed staging preflight, but the first real attempt failed before upload because active build 102 went off-air when GATT was released. |
| 3.0.30+109 | Durable-prefix transfer candidate. | **Physical failure:** flashed and booted, but 15 INFO/READ attempts still flushed the live producer tail and produced 15 sync errors during continuous capture. |
| 3.0.30+110 | INFO and latched READ use only the already-durable SD snapshot. | **Physical iPhone durability pass:** 27,375/27,375 frames stored, zero drops/rejections/mic/link/sync errors, 132 READ/DONE pairs, and 2,553,000 bytes moved across process death/reconnect. Final conversation ownership still failed above the firmware boundary: the offline interval remained durable, local, and unbound. |

## Corrected DFU finding

At 23:16, the updater logged application image 0 as 264,404 bytes with SHA-1
`3f1ca5b91e568fe74f2d42f8ce3e78a9574b358f`. That exactly matches the build-102
ZIP in Flutter Documents. MCUmgr then reported active/confirmed
`3.0.30.102`. The correct build-106 ZIP had been copied to the app's native
`files` directory, but the harness calls `getApplicationDocumentsDirectory()`
and therefore read `app_flutter/omi-cv1-3.0.30-blackbox.zip`.

This explains why image 0 was skipped and only image 1 appeared pending. It was
not proof that the multi-image updater arbitrarily ignored the application
core; identical image 0 was already active.

At 23:31, after copying the correct ZIP into Flutter Documents, the updater
logged the expected application image 0 size (264,884) and SHA-1
`3b59b77334d4937f6e9b97fb6436559b9a6334f6`. The transfer did not start:
build 102 stopped advertising after the app released its ordinary GATT owner,
MCUmgr exhausted connection attempts with status 147, and the harness reported
failure. The pendant therefore remained on build 102. A hardware reset and a
fresh attempt are still required.

## What is proven versus merely implemented

### Proven on physical hardware

- SD ring sequence identity and zero-drop observations across selected
  Android/iOS outage tests.
- Exact-device Android reconnect and iOS process restoration in the recorded
  3.0.29/101/102 test fixtures.
- One canonical phone-side audio artifact containing before/offline/after
  markers in order.
- Explicit deep-backlog authority when Auto Sync is off.
- Hardware charger/button reset restores a powered but off-air CV1 without
  storage erase.
- Build-102 PDM false-ready and advertiser-off-air failures.

### Implemented and automatically tested, but not physically qualified

- Build-106 advertiser supervisor.
- Build-105 shutdown release fence/emergency reboot.
- Build-103/104 microphone and bounded-read recovery on the exact claimed
  application image.
- Full Android/iOS behavioral parity under radio toggle, background, lock,
  manual backlog, and DFU on the same final firmware.

### Not proven end to end

- Atomic replacement of live fragments with canonical recovered audio on the
  production backend.
- Exactly-once behavior when two phones download the same retained pendant
  range.
- Controlled overnight battery improvement/regression.
- Fault behavior under injected SD, PDM, controller, and power failures via
  JTAG.
- Desktop parity.

## 2026-08-04 build-110 iPhone evidence

The internal iOS harness verified the unique artifact identity before DFU and
flashed `3.0.30+110` (ZIP SHA-256
`8ad0dad061fe637b922d5ed6667a4ac0713ebbe9539fa03ab0744b45e0dcabec`).
Live preview worked before and after a true custom-app process death. The
pendant trace ended with a healthy SD card, 15 ms / MTU 498 / DLE 251 / 2M PHY,
27,375 stored audio frames, zero dropped frames, zero microphone errors, zero
link-setup errors, and zero sync errors. Build 110 therefore closes the
firmware-side continuous-capture/READ readiness failure seen in build 109.

The application correctness gate did not pass. Ring source coverage remained
continuous over the offline marker, but the recovered app-down interval stayed
as unbound local `miss` WALs and the post-reconnect owner compacted only its
later live range. The bytes are recoverable and raw fragments were not uploaded
independently, but process death still split the logical conversation. This
confirms that storage durability and timeline ownership are separate contracts;
the firmware candidate can pass while the product release remains blocked on
app/backend ownership and atomic canonical replacement.
