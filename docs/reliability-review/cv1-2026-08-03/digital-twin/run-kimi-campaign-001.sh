#!/usr/bin/env bash
set -uo pipefail

lab_root="${1:-/mnt/ai/omi-cv1-digital-twin-2026-08-04}"
source_root="${lab_root}/source"
evidence_root="${lab_root}/evidence/campaign-001"
prompt_path="${source_root}/docs/reliability-review/cv1-2026-08-03/digital-twin/KIMI_CAMPAIGN_001_PROMPT.md"
kimi_bin="${KIMI_BIN:-/home/vega/.kimi-code/bin/kimi}"

mkdir -p "${evidence_root}"
cd "${source_root}" || exit 72

prompt="$(<"${prompt_path}")"
"${kimi_bin}" --output-format stream-json --prompt "${prompt}"
exit_code=$?
printf '%s\n' "${exit_code}" >"${evidence_root}/KIMI_EXIT_CODE"
exit "${exit_code}"
