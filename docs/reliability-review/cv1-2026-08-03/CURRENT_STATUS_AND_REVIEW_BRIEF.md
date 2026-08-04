# Current status and independent-review brief

Authoritative as of 2026-08-04 05:30 UTC. This file supersedes conflicting
build-106 and advertiser statements in the earlier chronology.

> Build update: the fixed candidate below was sealed and uploaded as build 107.
> See [BUILD107_QUALIFICATION.md](BUILD107_QUALIFICATION.md). It failed the
> no-touch postboot reconnect gate, so build 106 remains the last explicitly
> observed active/confirmed application image and the post-reset active image
> is not yet known.

## What changed after the packet was first drafted

The user manually selected a uniquely named OTA artifact from Android Downloads:

`Omi_CV1_Blackbox_3.0.30_build106_SHA0eec4835.zip`

Preflight on the phone established:

- ZIP SHA-256: `0eec4835d53b0667fee71f1f9f40105a508cd3eeab8f60942d7e5707cd4cd209`
- manifest version: `3.0.30+106`
- application image size: 264,884 bytes
- application image SHA-256: `2e634b0cd7ed4fc91c00f61dae1d89a47c17c680c1a14aa5cb4b61b870323f31`
- signed image header: `3.0.30+106`

DFU logs proved the intended application image was uploaded:

- application image SHA-1: `3b59b77334d4937f6e9b97fb6436559b9a6334f6`
- network image SHA-1: `82ff62eae7789dd1fd4147f59dfa9164f170706c`
- before reboot, MCUboot image 0 slot 1 reported `3.0.30.106` pending and
  permanent
- the device rebooted, reconnected, synchronized time, enabled the
  storage-authoritative lane, and advanced RingInfo with `dropped=0`

Postboot active/confirmed MCUmgr output was not captured before the Android app
was force-stopped. The boot, reconnect, and new ring movement strongly identify
the new application, but release qualification must still capture the explicit
postboot slot listing.

## Reproduced failure

After force-stopping `com.friend.ios.dev`, Android recorded the physical link
disconnect. A 30-second independent BLE name scan found no Omi advertisement.
The pendant returned after a hardware reset. This is a critical reconnect
failure, not a transcription or SD-backlog symptom.

## Root cause isolated in source

Commit `fb3718d10047bfd24b26f2fc7d9fc26671aa2a04` (merged from PR #10605
on 2026-07-29) added `button_service.c`. Its `button_notify()` called
`get_current_connection()`, whose documented contract returns a referenced
`bt_conn`, but never called `bt_conn_unref()`.

Every button event while connected therefore leaked a connection reference.
CV1 and the simulator use `CONFIG_BT_MAX_CONN=1`. On disconnect, Zephyr cannot
recycle the old connection slot while any leaked reference remains. The pinned
Zephyr 3.7/NCS 2.9 legacy advertiser needs a free connection object before it
can resume connectable advertising. A cold reboot clears the leaked object,
matching the physical recovery behavior.

This also explains the timing confusion: the regression arrived through the
latest-main rebase and was not part of the earlier storage-first work. Physical
button/reset use made it intermittent across prior test sequences.

## Why the build-106 advertiser supervisor was removed

The uncommitted build-106 supervisor repeatedly called `bt_le_adv_stop()` and
`bt_le_adv_start()` until a real connection occurred. It was based partly on a
physical build attribution later invalidated by the stale-ZIP incident.

Pinned Zephyr behavior matters: when no connection object is available,
`bt_le_adv_start_legacy()` may return success for persistent undirected
advertising without enabling the controller; it records state so
`bt_le_adv_resume()` can run after the connection object is finally recycled.
Repeated stop/start therefore cannot repair a leaked reference and adds radio
churn and battery cost. The supervisor and its policy-only tests were removed.

The candidate fix is deliberately small:

1. release the referenced connection in `button_notify()` on every path;
2. keep Zephyr's normal persistent-advertising lifecycle;
3. test the production button event followed by disconnect and a second real
   connection, rather than testing a synthetic retry policy.

## New behavioral regression test

The BabbleSim product test now:

1. boots an nRF5340 Omi peripheral with `CONFIG_BT_MAX_CONN=1`;
2. accepts client connection one;
3. emits the production `button_notify(1)` path while connected;
4. reads the button state and exercises settings GATT operations;
5. disconnects;
6. scans and establishes connection two without resetting the peripheral;
7. repeats the GATT contract and prints `OMI_BSIM_PASS`.

On the fixed source, connection two arrived about 109 ms after disconnect and
the complete test passed at simulated time 5.182 seconds. The missing unref
would retain the only connection slot and prevent the second connection.

## Current candidate versus installed device

- Installed physical device: verified build-106 upload and boot/reconnect
  evidence, but it still contains the button leak and speculative advertiser
  supervisor.
- Build-107 candidate: fixes the reference leak, removes the supervisor, adds
  the two-connection BabbleSim contract, and was uploaded from a uniquely
  named, hash-pinned OTA. It stayed off-air after DFU reset; active/confirmed
  postboot state is unverified.
- App preflight: accepts only the exact build-107 filename and verifies ZIP,
  manifest, image, and MCUboot-header identity before suspending BLE for DFU.
- Safe next physical action: flash build 107 through that gate, capture postboot
  active/confirmed slots, then repeat button event -> force-stop -> independent
  scan -> reconnect at least 25 times before resuming audio/backlog
  qualification.

## Independent reviewer mandate

Do not merely validate the explanation. Attempt to falsify it by reviewing:

- every `get_current_connection()` caller for balanced ownership;
- every `bt_conn_ref()`/`bt_conn_unref()` path across callbacks, work items,
  error returns, button events, GATT notifications, sync, shutdown, and DFU;
- whether the BabbleSim test would truly fail with the old production code;
- whether any other reference, pending notification, or host/controller state
  can reproduce the same off-air symptom;
- whether removing the supervisor reopens a distinct initial-boot failure;
- whether a bounded watchdog is justified only after proving an independent
  controller defect;
- whether Android/iOS ownership or force-stop behavior can mask a firmware
  failure;
- whether the broader storage-first diff violates audio durability, live
  priority, battery, or transcript assembly contracts.
