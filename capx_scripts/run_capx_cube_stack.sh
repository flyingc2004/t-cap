#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

die() {
  echo "[capx-eval] ERROR: $*" >&2
  exit 2
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

port_details() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp "sport = :${port}" 2>/dev/null || ss -H -ltn "sport = :${port}" 2>/dev/null || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
  fi
}

check_tcp_endpoint() {
  "${CAPX_DIR}/.venv/bin/python" - "$1" "$2" <<'PY'
import socket
import sys

host, port = sys.argv[1], int(sys.argv[2])
try:
    with socket.create_connection((host, port), timeout=2.0):
        pass
except OSError as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(1)
PY
}

MODE="${1:-smoke}"
case "${MODE}" in
  smoke)
    default_trials=1
    default_workers=1
    default_record_video=False
    ;;
  quick)
    default_trials=10
    default_workers=5
    default_record_video=True
    ;;
  *)
    echo "Usage: bash ${BASH_SOURCE[0]} {smoke|quick}" >&2
    exit 2
    ;;
esac

TRIALS="${CAPX_TRIALS:-${default_trials}}"
WORKERS="${CAPX_WORKERS:-${default_workers}}"
RECORD_VIDEO="${CAPX_RECORD_VIDEO:-${default_record_video}}"
TEMPERATURE="${CAPX_TEMPERATURE:-1.0}"
CONFIG_PATH="${CAPX_CONFIG_PATH:-env_configs/cube_stack/franka_robosuite_cube_stack.yaml}"

is_positive_integer "${TRIALS}" || die "CAPX_TRIALS must be a positive integer."
is_positive_integer "${WORKERS}" || die "CAPX_WORKERS must be a positive integer."
case "${RECORD_VIDEO,,}" in
  true|1|yes) RECORD_VIDEO=True ;;
  false|0|no) RECORD_VIDEO=False ;;
  *) die "CAPX_RECORD_VIDEO must be True or False." ;;
esac

[[ -x "${CAPX_DIR}/.venv/bin/python" ]] || die "CaP-X is not installed. Run setup_capx.sh first."
[[ -f "${CAPX_DIR}/capx/envs/launch.py" ]] || die "CaP-X launcher not found."
[[ -f "${CAPX_DIR}/${CONFIG_PATH}" ]] || die "Config not found: ${CAPX_DIR}/${CONFIG_PATH}"

if ! check_tcp_endpoint "${CAPX_PROXY_HOST}" "${CAPX_PROXY_PORT}"; then
  die "The API proxy is not reachable at ${CAPX_PROXY_HOST}:${CAPX_PROXY_PORT}. Start run_capx_api.sh first."
fi

echo "[capx-eval] Perception port preflight:"
for port in 8114 8115 8116; do
  listener="$(port_details "${port}")"
  if [[ -n "${listener}" ]]; then
    echo "[capx-eval] WARNING: port ${port} is already in use; CaP-X may reuse that service."
    printf '%s\n' "${listener}" | sed 's/^/  /'
  else
    echo "[capx-eval] Port ${port}: free (CaP-X will auto-launch the service)."
  fi
done

if [[ -z "${HF_TOKEN:-}" ]]; then
  echo "[capx-eval] SAM3 requires gated Hugging Face access."
  if [[ -t 0 ]]; then
    read -r -s -p "Hugging Face token (hidden; Enter only if weights are already cached): " _hf_token
    echo
    if [[ -n "${_hf_token}" ]]; then
      export HF_TOKEN="${_hf_token}"
    fi
    unset _hf_token
  else
    echo "[capx-eval] WARNING: HF_TOKEN is unset and no terminal is available for prompting." >&2
  fi
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${CAPX_RUN_DIR:-${CAPX_RUN_ROOT}/cube_stack_${MODE}_${timestamp}}"
OUTPUT_DIR="${CAPX_OUTPUT_DIR:-${RUN_DIR}/outputs}"
LOG_FILE="${RUN_DIR}/evaluation.log"
mkdir -p "${RUN_DIR}" "${OUTPUT_DIR}"

commit="$(git -C "${CAPX_DIR}" rev-parse HEAD)"
cat > "${RUN_DIR}/run_config.txt" <<EOF
mode=${MODE}
capx_commit=${commit}
config_path=${CONFIG_PATH}
model=${CAPX_MODEL}
server_url=${CAPX_SERVER_URL}
temperature=${TEMPERATURE}
trials=${TRIALS}
workers=${WORKERS}
record_video=${RECORD_VIDEO}
capx_gpu=${CAPX_GPU}
cuda_visible_devices=${CUDA_VISIBLE_DEVICES}
output_dir=${OUTPUT_DIR}
hf_token_present=$([[ -n "${HF_TOKEN:-}" ]] && echo yes || echo no)
EOF

command=(
  uv run --no-sync --active capx/envs/launch.py
  --config-path "${CONFIG_PATH}"
  --model "${CAPX_MODEL}"
  --server-url "${CAPX_SERVER_URL}"
  --temperature "${TEMPERATURE}"
  --total-trials "${TRIALS}"
  --num-workers "${WORKERS}"
  --record-video "${RECORD_VIDEO}"
  --output-dir "${OUTPUT_DIR}"
)

cd "${CAPX_DIR}"
echo "[capx-eval] mode=${MODE}"
echo "[capx-eval] model=${CAPX_MODEL}"
echo "[capx-eval] trials=${TRIALS}, workers=${WORKERS}, record_video=${RECORD_VIDEO}"
echo "[capx-eval] CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
echo "[capx-eval] output=${OUTPUT_DIR}"
echo "[capx-eval] log=${LOG_FILE}"
printf '[capx-eval] command:'
printf ' %q' "${command[@]}"
printf '\n'

set +e
"${command[@]}" 2>&1 | tee "${LOG_FILE}"
status="${PIPESTATUS[0]}"
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "[capx-eval] Completed successfully. Results: ${RUN_DIR}"
else
  echo "[capx-eval] Failed with exit code ${status}. See ${LOG_FILE}" >&2
fi

unset HF_TOKEN
exit "${status}"

