#!/usr/bin/env bash
set -euo pipefail

ADB_SERIAL="${OMI_ANDROID_SERIAL:-R5CY70NZW5X}"
SOURCE_PACKAGE="com.friend.ios.dev"
TARGET_PACKAGE="com.friend.ios.dev.blackbox"

fail() {
  echo "android test identity clone: $*" >&2
  exit 1
}

adb -s "$ADB_SERIAL" shell run-as "$SOURCE_PACKAGE" id >/dev/null 2>&1 || fail "source dev app is not debuggable"
adb -s "$ADB_SERIAL" shell run-as "$TARGET_PACKAGE" id >/dev/null 2>&1 || fail "black-box app is not installed"

for permission in \
  android.permission.BLUETOOTH_CONNECT \
  android.permission.BLUETOOTH_SCAN \
  android.permission.POST_NOTIFICATIONS \
  android.permission.RECORD_AUDIO \
  android.permission.ACCESS_FINE_LOCATION; do
  adb -s "$ADB_SERIAL" shell pm grant "$TARGET_PACKAGE" "$permission"
done

adb -s "$ADB_SERIAL" shell am force-stop "$SOURCE_PACKAGE"
adb -s "$ADB_SERIAL" shell am force-stop "$TARGET_PACKAGE"

firebase_store="$(
  adb -s "$ADB_SERIAL" exec-out run-as "$SOURCE_PACKAGE" find shared_prefs -maxdepth 1 -type f |
    tr -d '\r' |
    grep 'com.google.firebase.auth.api.Store.' |
    head -1
)"
[[ -n "$firebase_store" ]] || fail "Firebase auth state was not found"

adb -s "$ADB_SERIAL" exec-out run-as "$SOURCE_PACKAGE" \
  tar -cf - shared_prefs/FlutterSharedPreferences.xml "$firebase_store" |
  adb -s "$ADB_SERIAL" exec-in run-as "$TARGET_PACKAGE" tar -xf -

# The test app inherits identity and pairing only. It must not begin an implicit
# backlog drain or believe a drain from the source process is still active.
adb -s "$ADB_SERIAL" shell \
  "run-as $TARGET_PACKAGE sed -i 's#<boolean name=\"flutter.autoSyncOfflineRecordings\" value=\"true\" />#<boolean name=\"flutter.autoSyncOfflineRecordings\" value=\"false\" />#' shared_prefs/FlutterSharedPreferences.xml"
adb -s "$ADB_SERIAL" shell \
  "run-as $TARGET_PACKAGE sed -i 's#<boolean name=\"flutter.pendantDraining\" value=\"true\" />#<boolean name=\"flutter.pendantDraining\" value=\"false\" />#' shared_prefs/FlutterSharedPreferences.xml"

echo "android test identity clone: auth and pairing copied without recordings; automatic backlog sync forced off"
