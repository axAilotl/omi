# Artifacts and reproduction

## Repository state

- Primary experimental worktree: `/private/tmp/omi-cv1-blackbox`
- Branch: `codex/cv1-blackbox-diagnostics`
- Recorded HEAD before this packet: `ef4c9355b3`
- Upstream comparison: `origin/main`
- Draft PR under discussion: BasedHardware/omi #10654

The branch contains committed work plus an uncommitted diagnostic/recovery
delta. Run `git status --short` and capture `git diff --binary` before moving or
rebasing it. Do not mix this worktree with the smaller Android, iOS, firmware,
or backend PR worktrees listed by `git worktree list`.

## Installed Android baseline

- Package: `com.friend.ios.dev`
- Version: 1.0.543 (version code 992)
- Authentication: preserved
- Firebase/API: production Firebase project and canonical customer data plane
- Auto historical sync: expected off for baseline tests
- Pendant application image: `3.0.30+102`, active and confirmed at the last
  successful MCUmgr listing

At 23:26 after hardware reset, Android reconnected. The UI reported Listening,
the ring write cursor advanced through 1,878,575, 1,878,686, and 1,878,784, and
`dropped` remained zero.

At 23:31 a build-106 retry released the normal GATT owner. The updater selected
the correct image but could not attach because active build 102 stopped
advertising; it failed before upload with status 147. A hardware reset is
needed before either restoring the stable connection or attempting DFU again.

## Firmware artifacts

### Build 106 source artifact

Path:

```text
omi/firmware/v2.9.0/build/dfu_application.zip
```

Hashes:

```text
ZIP SHA-256
0eec4835d53b0667fee71f1f9f40105a508cd3eeab8f60942d7e5707cd4cd209

omi.signed.bin SHA-256
2e634b0cd7ed4fc91c00f61dae1d89a47c17c680c1a14aa5cb4b61b870323f31

omi.signed.bin SHA-1 (updater log identity)
3b59b77334d4937f6e9b97fb6436559b9a6334f6

ipc_radio.bin SHA-256
98a091b0213d334d8873b72e4494817e3552d950dc9d382153c7cd5d2d6b44fd

ipc_radio.bin SHA-1 (updater log identity)
82ff62eae7789dd1fd4147f59dfa9164f170706c
```

Manifest/header:

```text
version_MCUBOOT: 3.0.30+106
application size: 264884
signed-header version: 3.0.30 build 106
network image size: 175092
```

### Staging locations that caused the invalid run

The harness uses Flutter Documents:

```text
app_flutter/omi-cv1-3.0.30-blackbox.zip
```

Before correction this held build 102:

```text
ZIP SHA-256: d9472bafdbccb358c47f0b7880e34a01bea68f1bee4a6b688b5b1ec9dc3c2b69
application size: 264404
application SHA-1: 3f1ca5b91e568fe74f2d42f8ce3e78a9574b358f
application SHA-256: d0090e6c5f4af559a9768c91f29c73ed0ec73699a32cc1773e9d881ed7c648ed
signed-header version: 3.0.30 build 102
```

The correct build 106 was initially staged at the wrong path:

```text
files/omi-cv1-3.0.30-blackbox.zip
```

It has now been copied into Flutter Documents and verified on-phone with the
same build-106 ZIP hash above.

The file-picker cache also retains a build-100 ZIP with SHA-256
`1155711bb8cd12330df0af23eed54983fcb4b81969e3f6ee74898f4845259838`.
Never select artifacts by filename alone.

## Correct build procedure

Use the pinned container command in `TEST_METHODOLOGY.md`. After build:

```bash
shasum -a 256 omi/firmware/v2.9.0/build/dfu_application.zip
unzip -p omi/firmware/v2.9.0/build/dfu_application.zip manifest.json
```

Also inspect the MCUboot application header or run the repository's version
contract checks. The ZIP name is fixed across builds, so its contents and hash
must be checked every time.

## Correct authenticated Android build procedure

The repository's hermetic test bootstrap intentionally creates placeholder
development Firebase/env inputs. For a physical run, use:

```bash
cd app
./e2e/scripts/bootstrap_physical_dev_config.sh
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
bash scripts/verify_android_physical_test_auth_config.sh
flutter build apk --debug --flavor dev --target-platform android-arm64
```

The verifier must report the production Firebase project, canonical
`https://api.omi.me/` customer plane, and the dev package. Install with
`adb install -r` to retain authentication and user data. Do not clear or
uninstall the app during reliability testing.

## Correct iOS build procedure

Use `app/e2e/scripts/build_signed_ios_physical_dev.sh` and the documented
personal bundle/team. Update the same isolated bundle in place to preserve its
data/keychain. Rebuild after every shared Dart change; a previously signed app
is stale even if Swift did not change. Never replace the production Omi app.

## Internal DFU procedure

The internal route exists only when `OMI_BLACKBOX_HARNESS=true` and resolves a
fixed filename from `getApplicationDocumentsDirectory()`.

Before launching it:

1. copy the exact ZIP to the resolved Documents path;
2. hash the on-phone bytes;
3. parse on-phone manifest and signed header;
4. capture the current MCUmgr image list;
5. verify only the intended app owns the pendant; and
6. keep the charger/button hardware reset available because build 102 may stop
   advertising when the normal app releases GATT.

After updater success, re-read the image list and require application image 0
to be active/confirmed at the expected version. Then prove advertising, GATT,
ring movement, and live audio.

## Local evidence already referenced

- `/private/tmp/omi-blackbox-export-20260802.json`
- `/tmp/omi-acceptance-20260728.log`
- `/tmp/omi-acceptance-postfix-20260728.log`
- `/tmp/omi-ios-storage-first-recovery-20260729-live.log`
- `/tmp/omi-ios-storage-first-recoveryfix-reconnect-live-20260729.log`
- `/tmp/omi-ios-wals-after-reconnectfix-20260729.json`

These files may include private identifiers or speech. Preserve them locally;
publish only sanitized excerpts and hashes.
