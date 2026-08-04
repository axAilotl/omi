# Validation status

## Passing automated evidence

### Host-native durability and policy suite

Command:

```sh
build_dir=$(mktemp -d /tmp/omi-audio-storage-packer-tests.XXXXXX)
cmake -S omi/firmware/omi/tests/audio_storage_packer -B "$build_dir"
cmake --build "$build_dir"
ctest --test-dir "$build_dir" --output-on-failure
```

Result on macOS: 2/2 tests passed (`audio_storage_packer_tests` and
`blackbox_trace_tests`).

### BabbleSim connection-reference regression

Build environment: pinned `ghcr.io/zephyrproject-rtos/ci:v0.26.13` container,
NCS 2.9.0/Zephyr 3.7.99, x86_64 emulation on Apple Silicon.

The initial runner exposed two pre-existing simulator integration defects:

- Apple Silicon cannot build the 32-bit BabbleSim host components natively;
- `omi/firmware/bsim/CMakeLists.txt` omitted production sources now required by
  `transport.c` (`ring_transfer_integrity.c` and `audio_storage_packer.c`).

After running the x86_64 image and adding those production sources, both the
nRF5340 peripheral and nRF52 client compiled. The simulated radio run printed:

```text
OMI_BSIM_BUTTON_NOTIFIED
Transport disconnected
Transport connected
OMI_BSIM_PASS
```

First disconnect occurred at simulated time 2.621814 seconds; the second
connection occurred at 2.730632 seconds. The second GATT contract completed and
the client printed PASS at 5.182120 seconds.

The client now bounds each connection attempt at 15 seconds and reports an
explicit failure. An isolated control build with the production unref removed
printed `OMI_BSIM_FAIL reconnect -11` at 17.621827 seconds, exited nonzero, and
never printed PASS. This proves the test distinguishes the repaired ownership
boundary from the leak instead of merely proving a happy-path reconnect.

### Build 107 artifact and app preflight

Build 107 passed the complete pinned NCS 2.9 sysbuild and was sealed as
`Omi_CV1_Blackbox_OTA_3.0.30_build107_SHA052faa45.zip`, SHA-256
`052faa4556c104b467ae60f38e7b76264bc7eb12ba3d3eebfb75eb971dffc4ef`.
Its manifest and signed application header both report `3.0.30+107`.

The app's build-specific verifier tests passed for the valid package, tampered
same-name package, wrong filename, and wrong identity metadata. The provider
suite also passed the explicit exact-device DFU lease when the debounced
connected-device state was still null. The production verifier tool accepted
the sealed OTA, and the app analyzer ratchet passed.

## Evidence still required before another device claim

- Postboot MCUboot image-state listing proving the new app image active and
  confirmed.
- Black-box export after the old build-106 failure, if still available.
- At least 25 physical cycles containing a connected button event, app
  force-stop or Bluetooth toggle, independent advertising observation, exact
  device reconnect, moving RingInfo, and a unique audible marker.
- Android and iOS parity on the same final firmware artifact.
- Live-preview continuity and explicit-only historical backlog drain.
- Long offline capture, manual recovery, exact source coverage, one canonical
  logical conversation, and no one-second job explosion.
- Matched battery A/B runs.
- JTAG/RTT/coredump and deterministic fault injection when the Tag-Connect cable
  becomes available.

## Review caveat

The current working tree is a broad experimental stack. A green reconnect test
does not qualify transcript correctness, multi-client exactly-once behavior,
backend canonical replacement, iOS restoration, desktop parity, or battery.
Those remain separate contracts and must not be inferred from BLE success.
