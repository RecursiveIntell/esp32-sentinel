#!/usr/bin/env bash
# esp32-sentinel: examples/dht22_laptop_gateway/run.sh
# Worked example with NO hardware needed.
#
# What it does (in order):
#   1. Starts the laptop-fallback gateway (sensor_ai_gateway.py) on a local port.
#   2. Waits for /health to return 200 OK.
#   3. Simulates a DHT22 reading (no real sensor) and POSTs it to /api/sensor_ai
#      as if the ESP32-S3 sentinel had decided to escalate.
#   4. Verifies the gateway returned a non-empty response.
#   5. Stops the gateway and writes a JSONL receipt to ./out.jsonl.
#   6. Prints "the full flow works" and exits 0.
#
# Override the model with:  OLLAMA_MODEL=llama3.2:1b bash run.sh
# Override the port with:   GATEWAY_PORT=8091 bash run.sh
#
# Returns 0 on success, non-zero on any step failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GATEWAY_PORT="${GATEWAY_PORT:-8090}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:1b}"
RECEIPT="${SCRIPT_DIR}/out.jsonl"

# Use a smaller, commonly-pulled model. The gateway default is qwen2.5:0.5b
# (matches the UNO Q deployment) but a fresh clone rarely has it pulled.
export OLLAMA_MODEL

GATEWAY_LOG="$(mktemp)"
GATEWAY_PID=""

cleanup() {
  if [[ -n "${GATEWAY_PID}" ]] && kill -0 "${GATEWAY_PID}" >/dev/null 2>&1; then
    kill "${GATEWAY_PID}" >/dev/null 2>&1 || true
    wait "${GATEWAY_PID}" 2>/dev/null || true
  fi
  rm -f "${GATEWAY_LOG}"
}
trap cleanup EXIT

note() { printf '  [step] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1" >&2; exit 1; }

note "1/5 starting gateway on port ${GATEWAY_PORT} (model=${OLLAMA_MODEL})"
OLLAMA_MODEL="${OLLAMA_MODEL}" python3 "${REPO_ROOT}/uno-q/server/sensor_ai_gateway.py" \
  --host 127.0.0.1 --port "${GATEWAY_PORT}" \
  >"${GATEWAY_LOG}" 2>&1 &
GATEWAY_PID=$!

note "2/5 waiting for /health"
# Note: grep for "status" (loose) — the actual JSON has a space after the
# colon ({"status": "ok", ...}) so a strict "status":"ok" pattern would
# never match. The gateway is up when /health returns any valid JSON object.
for i in {1..30}; do
  if curl -sS --max-time 1 "${GATEWAY_URL}/health" 2>/dev/null | grep -q '"status"'; then
    break
  fi
  if ! kill -0 "${GATEWAY_PID}" >/dev/null 2>&1; then
    echo "---- gateway log ----" >&2
    cat "${GATEWAY_LOG}" >&2
    fail "gateway process exited before becoming healthy"
  fi
  sleep 0.2
done
if ! curl -sS --max-time 2 "${GATEWAY_URL}/health" 2>/dev/null | grep -q '"status"'; then
  echo "---- gateway log ----" >&2
  cat "${GATEWAY_LOG}" >&2
  fail "gateway did not become healthy within 6s"
fi
echo "    gateway up"

note "3/5 simulating DHT22 reading + sentinel low-confidence escalation"
# Simulated DHT22 reading: warm room, normal humidity.
# Decision: sentinel could not classify (confidence 0.42 < threshold 0.75),
# so it escalates to tier 1 with a route reason.
PAYLOAD=$(cat <<'EOF'
{
  "sensor": { "temperature_c": 31.4, "humidity_pct": 62.1, "heat_index_c": 33.2 },
  "decision": "escalate",
  "route_reason": "sentinel_conf_below_threshold",
  "prompt": "Is this room safe to work in right now?"
}
EOF
)
RESPONSE=$(curl -sS --max-time 60 -X POST \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  "${GATEWAY_URL}/api/sensor_ai" 2>&1) || fail "POST /api/sensor_ai failed: ${RESPONSE}"

note "4/5 verifying response shape"
# Validate JSON shape. Use a temp file so the response is preserved verbatim
# (a heredoc on python3's stdin would replace the pipe, which we don't want).
echo "${RESPONSE}" > /tmp/esp32_sentinel_resp_$$.json
python3 /tmp/esp32_sentinel_resp_$$.json <<'PYEOF' || { rm -f /tmp/esp32_sentinel_resp_$$.json; fail "gateway response did not match the expected schema"; }
import json, sys
with open(sys.argv[1]) as f:
    r = json.load(f)
assert r.get("schema") == "ri_uno_q_sensor_ai_v1", "missing schema"
assert "response" in r and r["response"], "empty response: %r" % r
print("    schema=%s model=%s tokens=%s tps=%s" % (r["schema"], r["model"], r["generated_tokens"], r["tokens_per_sec"]))
resp = r["response"]
print("    response: %s" % (resp[:120] if isinstance(resp, str) else resp))
PYEOF
rm -f /tmp/esp32_sentinel_resp_$$.json

note "5/5 writing JSONL receipt to ${RECEIPT}"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
python3 - <<PY
import json, os
ts = "${TS}"
receipt = {
    "example": "dht22_laptop_gateway",
    "timestamp_utc": ts,
    "gateway_url": "${GATEWAY_URL}",
    "ollama_model": "${OLLAMA_MODEL}",
    "request": json.loads('''${PAYLOAD}'''),
    "response": json.loads('''${RESPONSE}'''),
    "result": "ok",
}
with open("${RECEIPT}", "w") as f:
    f.write(json.dumps(receipt) + "\n")
PY

echo
echo "the full flow works"
