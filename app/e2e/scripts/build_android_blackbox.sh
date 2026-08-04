#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOCAL_DEBUG_KEYSTORE="${OMI_ANDROID_BLACKBOX_KEYSTORE:-${HOME}/.android/debug.keystore}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME

fail() {
  echo "android black-box build: $*" >&2
  exit 1
}

[[ -f "$LOCAL_DEBUG_KEYSTORE" ]] || fail "missing existing test-app signer: $LOCAL_DEBUG_KEYSTORE"
[[ -x "$JAVA_HOME/bin/keytool" ]] || fail "missing Java 21 toolchain at $JAVA_HOME"

"${APP_DIR}/e2e/scripts/bootstrap_physical_dev_config.sh" >&2

# The normal physical-device preflight deliberately selects the repository's
# shared dev key. This side-by-side black-box package predates that convention
# on the maintainer phone, so preserve its authenticated install by allowing
# Gradle to select the workstation's existing Android debug key for this build
# only. Restore key.properties even if Flutter or Gradle fails.
KEY_PROPERTIES="${APP_DIR}/android/key.properties"
KEY_BACKUP_DIR="$(mktemp -d /private/tmp/omi-blackbox-key.XXXXXX)"
mv "$KEY_PROPERTIES" "$KEY_BACKUP_DIR/key.properties"
restore_key_properties() {
  if [[ -f "$KEY_BACKUP_DIR/key.properties" ]]; then
    mv "$KEY_BACKUP_DIR/key.properties" "$KEY_PROPERTIES"
  fi
  rmdir "$KEY_BACKUP_DIR" 2>/dev/null || true
}
trap restore_key_properties EXIT

cd "$APP_DIR"
flutter build apk \
  --debug \
  --flavor dev \
  --target-platform android-arm64 \
  -t lib/main.dart \
  --android-project-arg=omiBlackboxPackage=true \
  --dart-define=OMI_BLACKBOX_HARNESS=true >&2

APK="${APP_DIR}/build/app/outputs/flutter-apk/app-dev-debug.apk"
[[ -f "$APK" ]] || fail "Flutter did not produce $APK"

APKSIGNER="$(find /opt/homebrew/share/android-commandlinetools/build-tools -name apksigner -type f 2>/dev/null | sort -V | tail -1)"
[[ -x "$APKSIGNER" ]] || fail "apksigner was not found"

expected="$("$JAVA_HOME"/bin/keytool -list -v -keystore "$LOCAL_DEBUG_KEYSTORE" -storepass android -alias androiddebugkey 2>/dev/null |
  awk -F'SHA256: ' '/SHA256:/ {print tolower($2); exit}' | tr -d ':[:space:]')"
actual="$($APKSIGNER verify --print-certs "$APK" |
  awk -F': ' '/certificate SHA-256 digest:/ {print tolower($2); exit}' | tr -d '[:space:]')"
[[ -n "$expected" && "$actual" == "$expected" ]] ||
  fail "APK signer does not match the existing side-by-side black-box app"

echo "$APK"
