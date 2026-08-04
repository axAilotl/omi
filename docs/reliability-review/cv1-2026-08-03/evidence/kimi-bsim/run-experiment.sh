#!/usr/bin/env bash
# Adversarial-review BabbleSim experiment.
# Variant A: exact working-tree source (button_notify unref fix present) -> expect OMI_BSIM_PASS
# Variant B: same tree with the fix reverted (old production button_notify) -> expect FAIL/timeout
set -uo pipefail

SRC=/mnt/ai/omi-cv1-adversarial-review-2026-08-03/source/omi/firmware
IMG='ghcr.io/zephyrproject-rtos/ci:v0.26.13@sha256:b0ac6334d1926cd0971a0a444f7adc6dd020e88ee3ce865aa070b6475a3ac4eb'
BASE=/tmp/kimi-bsim
LOG=$BASE/experiment.log
: > "$LOG"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "pulling $IMG"
docker pull "$IMG" >>"$LOG" 2>&1 || { log "PULL FAILED"; exit 1; }
log "pull done"

# --- Variant A: fixed (verbatim working tree) ---
mkdir -p "$BASE/fixed"
rm -rf "$BASE/fixed/firmware"
cp -a "$SRC" "$BASE/fixed/firmware"
log "variant A: starting run-bsim (fixed source)"
docker run --rm \
  -v "$BASE/fixed/firmware:/omi/firmware" \
  -e CMAKE_PREFIX_PATH=/opt/toolchains \
  "$IMG" \
  bash /omi/firmware/scripts/ci/run-bsim.sh >"$BASE/fixed-run.log" 2>&1
RC_A=$?
log "variant A exit code: $RC_A"
grep -E "OMI_BSIM" "$BASE/fixed-run.log" | tee -a "$LOG" || true

# --- Variant B: leaky (revert the unref, reusing the NCS workspace) ---
rm -rf "$BASE/leaky"
cp -a "$BASE/fixed" "$BASE/leaky"
python3 - <<'EOF'
import re
p = "/tmp/kimi-bsim/leaky/firmware/bsim/../omi/src/lib/core/button_service.c"
p = "/tmp/kimi-bsim/leaky/firmware/omi/src/lib/core/button_service.c"
s = open(p).read()
old = """        (void) bt_gatt_notify(conn, &button_service.attrs[1], &final_button_state, sizeof(final_button_state));
        bt_conn_unref(conn);"""
new = """        (void) bt_gatt_notify(conn, &button_service.attrs[1], &final_button_state, sizeof(final_button_state));"""
assert old in s, "expected fixed button_notify not found"
open(p, "w").write(s.replace(old, new))
print("reverted bt_conn_unref in leaky copy")
EOF
log "variant B: starting run-bsim (old leaky button_notify)"
docker run --rm \
  -v "$BASE/leaky/firmware:/omi/firmware" \
  -e CMAKE_PREFIX_PATH=/opt/toolchains \
  "$IMG" \
  bash /omi/firmware/scripts/ci/run-bsim.sh >"$BASE/leaky-run.log" 2>&1
RC_B=$?
log "variant B exit code: $RC_B"
grep -E "OMI_BSIM" "$BASE/leaky-run.log" | tee -a "$LOG" || log "variant B: no OMI_BSIM_* line (timeout/hang path)"

log "DONE A=$RC_A B=$RC_B"
