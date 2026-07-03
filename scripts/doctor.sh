#!/usr/bin/env bash
# esp32-sentinel: doctor.sh
# Verifies the host-side path end to end. The flash path on real ESP32-S3 is
# out of scope for the doctor (it requires the board and the Xtensa toolchain);
# install.sh checks for that pre-flight.
#
# Checks performed:
#   1. Gateway service is reachable on its expected port.
#   2. The trained model file is present and the SHA256 matches the report.
#   3. The example flow (examples/dht22_laptop_gateway/run.sh) exits 0.
#
# Returns 0 only when all three pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATEWAY_PORT="${GATEWAY_PORT:-8090}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"

ok()   { printf '  [ok]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; }
hdr()  { printf '\n== %s ==\n' "$1"; }

RETVAL=0

hdr "1. Gateway reachability (/health)"
HEALTH=$(curl -sS --max-time 3 "${GATEWAY_URL}/health" 2>/dev/null || true)
if [[ -n "${HEALTH}" ]] && echo "${HEALTH}" | grep -q '"status":"ok"'; then
  ok "gateway responded: ${HEALTH}"
else
  fail "gateway not reachable at ${GATEWAY_URL}/health"
  echo "        start it with: bash uno-q/scripts/laptop_fallback.sh"
  RETVAL=1
fi

hdr "2. Trained model file"
MODEL_FILE="${REPO_ROOT}/models/char_lstm_709ff8a9.bin"
if [[ -f "${MODEL_FILE}" ]]; then
  ACTUAL=$(sha256sum "${MODEL_FILE}" | awk '{print $1}')
  EXPECTED="709ff8a921612f0d1a075ce586d3355c895b16a100d12d8f74bb3367cdf83c61"
  if [[ "${ACTUAL}" == "${EXPECTED}" ]]; then
    ok "model present + SHA256 verified"
  else
    fail "model present but SHA256 mismatch"
    fail "  expected: ${EXPECTED}"
    fail "  got:      ${ACTUAL}"
    RETVAL=1
  fi
else
  fail "model file missing at ${MODEL_FILE}"
  RETVAL=1
fi

hdr "3. Example flow (dht22_laptop_gateway)"
if bash "${REPO_ROOT}/examples/dht22_laptop_gateway/run.sh" >/dev/null 2>&1; then
  ok "example exited 0"
else
  fail "example did not exit 0 (run it directly for output)"
  RETVAL=1
fi

hdr "Summary"
if (( RETVAL == 0 )); then
  echo "All doctor checks passed."
else
  echo "Doctor found issues. Fix and re-run."
fi
exit "${RETVAL}"
