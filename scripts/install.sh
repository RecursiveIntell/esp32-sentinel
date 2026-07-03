#!/usr/bin/env bash
# esp32-sentinel: install.sh
# Idempotent pre-flight for the public repo. Verifies the four host-side deps the
# laptop-fallback path needs, and the two firmware-side deps the flash path needs.
# Prints the next step. Does NOT install the Xtensa toolchain (that takes 5+ minutes
# and is intentionally out of scope for the 1-2 hour tight cut).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ok()   { printf '  [ok]   %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }
miss() { printf '  [miss] %s\n' "$1"; }
hdr()  { printf '\n== %s ==\n' "$1"; }

NEEDS_FLASH=0
NEEDS_GATEWAY=0
NEEDS_MODEL=0

hdr "1. Rust (host: cargo)"
if command -v cargo >/dev/null 2>&1; then
  ok "cargo: $(cargo --version 2>/dev/null | head -1)"
else
  miss "cargo not found"
  warn "  install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  NEEDS_FLASH=1
fi

hdr "2. Rust (firmware: esp toolchain)"
if command -v cargo >/dev/null 2>&1 && cargo +esp --version >/dev/null 2>&1; then
  ok "cargo +esp available"
elif [[ -f "${HOME}/.rustup/toolchains/esp/bin/cargo" ]]; then
  ok "esp toolchain installed at ~/.rustup/toolchains/esp"
else
  miss "esp toolchain not installed (Xtensa target, only required for firmware build/flash)"
  warn "  install with:"
  warn "    rustup toolchain install esp --component rustfmt clippy"
  warn "  Then build with:  cargo +esp build --bin sentinel-wifi"
  NEEDS_FLASH=1
fi

hdr "3. Python (gateway service)"
if command -v python3 >/dev/null 2>&1; then
  ok "python3: $(python3 --version 2>&1 | head -1)"
else
  miss "python3 not found"
  warn "  install with: sudo dnf install python3 (Fedora) / sudo apt install python3 (Debian/Ubuntu)"
  NEEDS_GATEWAY=1
fi

hdr "4. Ollama (laptop fallback's heavy model)"
if command -v ollama >/dev/null 2>&1; then
  if curl -sS --max-time 2 "${OLLAMA_URL:-http://localhost:11434}/api/version" >/dev/null 2>&1; then
    ok "ollama running"
  else
    miss "ollama installed but not responding on http://localhost:11434"
    warn "  start with: ollama serve"
    NEEDS_GATEWAY=1
  fi
else
  miss "ollama not found"
  warn "  install from: https://ollama.com/download"
  warn "  then pull a small model:  ollama pull qwen2.5:0.5b"
  NEEDS_GATEWAY=1
fi

hdr "5. Trained model (char_lstm_709ff8a9.bin)"
MODEL_FILE="${REPO_ROOT}/models/char_lstm_709ff8a9.bin"
if [[ -f "${MODEL_FILE}" ]]; then
  ACTUAL=$(sha256sum "${MODEL_FILE}" | awk '{print $1}')
  EXPECTED="709ff8a921612f0d1a075ce586d3355c895b16a100d12d8f74bb3367cdf83c61"
  if [[ "${ACTUAL}" == "${EXPECTED}" ]]; then
    ok "model SHA256 matches the 2026-07-03 report"
  else
    miss "model present but SHA256 mismatch"
    warn "  expected: ${EXPECTED}"
    warn "  got:      ${ACTUAL}"
    NEEDS_MODEL=1
  fi
else
  miss "model file missing at ${MODEL_FILE}"
  NEEDS_MODEL=1
fi

hdr "Summary"
if (( NEEDS_FLASH == 0 && NEEDS_GATEWAY == 0 && NEEDS_MODEL == 0 )); then
  echo "All pre-flight checks passed."
  echo
  echo "Next steps:"
  echo "  - laptop fallback (no ESP32 needed):"
  echo "      bash examples/dht22_laptop_gateway/run.sh"
  echo "  - flash firmware to ESP32-S3:"
  echo "      cd esp32-s3 && cargo +esp build --release --bin sentinel-wifi"
  echo "      espflash flash --chip esp32s3 target/xtensa-esp32s3-none-elf/release/sentinel-wifi"
else
  echo "Some checks failed. Address the [warn] lines above, then re-run install.sh."
  exit 1
fi
