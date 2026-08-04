#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE_BUNDLE_ID="com.omi.reliability.alexsmacbookpro"
TEAM_ID="6DV84DW2BA"
SIGNING_IDENTITY="Apple Development: Raul Vega (MS392Y9HC6)"
PROFILE_SOURCE="${OMI_IOS_PROFILE_SOURCE:-${HOME}/Downloads/omi-ios-personal-8c1321a908-20260725/OmiDev-personal-profile-signed.app/embedded.mobileprovision}"
BUILD_MODE="${OMI_IOS_BUILD_MODE:-profile}"

fail() {
  echo "signed-ios-dev build: $*" >&2
  exit 1
}

[[ -f "$PROFILE_SOURCE" ]] || fail "missing provisioning profile source: $PROFILE_SOURCE"
security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY" || fail "missing signing identity: $SIGNING_IDENTITY"
[[ "$BUILD_MODE" == "debug" || "$BUILD_MODE" == "profile" ]] ||
  fail "OMI_IOS_BUILD_MODE must be debug or profile, got: $BUILD_MODE"

"${APP_DIR}/e2e/scripts/bootstrap_physical_dev_config.sh"

# CocoaPods writes its local tool version into the tracked lockfile even when
# dependency resolution is unchanged. A physical test build must be
# repeatable and must not manufacture source changes, so restore the exact
# pre-build lockfile on every exit path.
POD_LOCK="${APP_DIR}/ios/Podfile.lock"
POD_LOCK_BACKUP="$(mktemp /private/tmp/omi-podfile-lock.XXXXXX)"
cp "$POD_LOCK" "$POD_LOCK_BACKUP"
restore_pod_lock() {
  mv "$POD_LOCK_BACKUP" "$POD_LOCK"
}
trap restore_pod_lock EXIT

cd "$APP_DIR"
flutter build ios "--${BUILD_MODE}" --no-codesign --flavor dev -t lib/main.dart --dart-define OMI_BLACKBOX_HARNESS=true

UNSIGNED_APP="${APP_DIR}/build/ios/iphoneos/Runner.app"
[[ -d "$UNSIGNED_APP" ]] || fail "Flutter did not produce $UNSIGNED_APP"

ARTIFACT_ROOT="$(mktemp -d /private/tmp/omi-ios-blackbox.XXXXXX)"
SIGNED_APP="${ARTIFACT_ROOT}/OmiBlackbox.app"
mkdir "$SIGNED_APP"
rsync -a --exclude _CodeSignature --exclude embedded.mobileprovision --exclude PlugIns --exclude Watch \
  "${UNSIGNED_APP}/" "${SIGNED_APP}/"

plutil -replace CFBundleIdentifier -string "$DEVICE_BUNDLE_ID" "${SIGNED_APP}/Info.plist"
cp "$PROFILE_SOURCE" "${SIGNED_APP}/embedded.mobileprovision"

[[ "$(plutil -extract PROJECT_ID raw "${SIGNED_APP}/GoogleService-Info.plist" 2>/dev/null || true)" == "based-hardware" ]] ||
  fail "built app does not contain canonical based-hardware Firebase configuration"

while IFS= read -r framework; do
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$framework"
done < <(find "${SIGNED_APP}/Frameworks" -maxdepth 2 -type d -name '*.framework' | sort)

while IFS= read -r dylib; do
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$dylib"
done < <(find "${SIGNED_APP}/Frameworks" -type f -name '*.dylib' | sort)

codesign --force \
  --sign "$SIGNING_IDENTITY" \
  --timestamp=none \
  --entitlements "${APP_DIR}/e2e/ios_personal_debug.entitlements" \
  "$SIGNED_APP"

codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"

actual_bundle="$(plutil -extract CFBundleIdentifier raw "${SIGNED_APP}/Info.plist")"
[[ "$actual_bundle" == "$DEVICE_BUNDLE_ID" ]] || fail "unexpected bundle id: $actual_bundle"
codesign -d --entitlements :- "$SIGNED_APP" 2>/dev/null | grep -Fq "${TEAM_ID}.${DEVICE_BUNDLE_ID}" ||
  fail "signed app has the wrong application identifier"
[[ ! -e "${SIGNED_APP}/PlugIns" && ! -e "${SIGNED_APP}/Watch" ]] || fail "companion payload was not stripped"

echo "$SIGNED_APP"
