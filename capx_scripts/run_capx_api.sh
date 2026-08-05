#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

die() {
  echo "[capx-api] ERROR: $*" >&2
  exit 2
}

port_details() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp "sport = :${port}" 2>/dev/null || ss -H -ltn "sport = :${port}" 2>/dev/null || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
  fi
}

[[ -x "${CAPX_DIR}/.venv/bin/python" ]] || die "CaP-X is not installed. Run setup_capx.sh first."
[[ -f "${CAPX_DIR}/capx/serving/openrouter_server.py" ]] || die "OpenRouter proxy script not found in ${CAPX_DIR}."

existing_listener="$(port_details "${CAPX_PROXY_PORT}")"
if [[ -n "${existing_listener}" ]]; then
  echo "[capx-api] Port ${CAPX_PROXY_PORT} is already in use:" >&2
  printf '%s\n' "${existing_listener}" >&2
  echo "[capx-api] Reuse that proxy or choose another port with CAPX_PROXY_PORT." >&2
  exit 98
fi

SECRET_DIR="${CAPX_SECRET_DIR:-/dev/shm/${USER:-$(id -un)}/capx-secrets}"
KEY_FILE="${SECRET_DIR}/openrouter.key"
mkdir -p "${SECRET_DIR}"
chmod 700 "${SECRET_DIR}"
umask 077

cleanup() {
  rm -f "${KEY_FILE}"
  unset _openrouter_key OPENROUTER_API_KEY
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  _openrouter_key="${OPENROUTER_API_KEY}"
else
  [[ -t 0 ]] || die "No terminal is available for secure token input. Set OPENROUTER_API_KEY for this process."
  read -r -s -p "OpenRouter API key (input hidden): " _openrouter_key
  echo
fi

[[ -n "${_openrouter_key}" ]] || die "The OpenRouter API key is empty."
printf '%s\n' "${_openrouter_key}" > "${KEY_FILE}"
chmod 600 "${KEY_FILE}"
unset _openrouter_key OPENROUTER_API_KEY

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "${CAPX_RUN_ROOT}"
LOG_FILE="${CAPX_RUN_ROOT}/openrouter_proxy_${timestamp}.log"
LOCAL_PROXY_SERVER_URL="http://${CAPX_PROXY_HOST}:${CAPX_PROXY_PORT}/chat/completions"

cd "${CAPX_DIR}"
echo "[capx-api] CAPX_DIR=${CAPX_DIR}"
echo "[capx-api] endpoint=${LOCAL_PROXY_SERVER_URL}"
echo "[capx-api] log=${LOG_FILE}"
echo "[capx-api] The key is temporary and will be deleted when this process exits."

set +e
uv run --no-sync --active capx/serving/openrouter_server.py \
  --key-file "${KEY_FILE}" \
  --port "${CAPX_PROXY_PORT}" 2>&1 | tee "${LOG_FILE}"
status="${PIPESTATUS[0]}"
set -e

exit "${status}"
