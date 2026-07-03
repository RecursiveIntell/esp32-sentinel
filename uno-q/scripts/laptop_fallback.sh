#!/usr/bin/env bash
# esp32-sentinel: laptop_fallback.sh
# Runs the gateway service on a regular laptop with Ollama (when no UNO Q is available).
# This is the "tier 1 on a laptop" path: same HTTP /api/sensor_ai contract, different host.
#
# Usage:
#   bash uno-q/scripts/laptop_fallback.sh                 # foreground, default port 8090
#   OLLAMA_MODEL=llama3.2:1b PORT=8091 bash uno-q/scripts/laptop_fallback.sh
#
# Requires: python3 with stdlib only (no extra deps for the gateway itself).
# Talks to: Ollama at http://localhost:11434 (override with OLLAMA_URL).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
PORT="${PORT:-8090}"
HOST="${HOST:-127.0.0.1}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:0.5b}"

# Allow sensor_ai_gateway.py to read these from the environment.
export OLLAMA_URL OLLAMA_MODEL

if [[ ! -f "${SERVER_DIR}/sensor_ai_gateway.py" ]]; then
  echo "laptop_fallback.sh: cannot find sensor_ai_gateway.py at ${SERVER_DIR}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "laptop_fallback.sh: python3 is required" >&2
  exit 1
fi

# Ollama is optional at start time; the gateway will surface a 502 if it's missing
# when a /api/sensor_ai call lands. We probe so the user gets a clear warning up front.
if ! curl -sS --max-time 2 "${OLLAMA_URL}/api/version" >/dev/null 2>&1; then
  echo "laptop_fallback.sh: WARN — Ollama not reachable at ${OLLAMA_URL}" >&2
  echo "                          the gateway will start, but /api/sensor_ai will 502" >&2
  echo "                          start Ollama with: ollama serve" >&2
fi

echo "laptop_fallback: starting sensor_ai_gateway on ${HOST}:${PORT}"
echo "  Ollama URL:    ${OLLAMA_URL}"
echo "  Ollama model:  ${OLLAMA_MODEL}"
echo "  Server dir:    ${SERVER_DIR}"

exec python3 "${SERVER_DIR}/sensor_ai_gateway.py" \
  --host "${HOST}" --port "${PORT}"
