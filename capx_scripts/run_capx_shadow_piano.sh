#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export CAPX_ENV_AUTO_ACTIVATE=0
export CAPX_CACHE_ROOT="${CAPX_CACHE_ROOT:-/mnt/data/ljz/opentacbench/capx-cache}"
export CAPX_RUN_ROOT="${CAPX_RUN_ROOT:-/mnt/data/ljz/opentacbench/capx-runs}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

MODE="${1:-smoke}"
case "${MODE}" in
  smoke) TRIALS="${CAPX_TRIALS:-1}" ;;
  quick) TRIALS="${CAPX_TRIALS:-10}" ;;
  *) echo "Usage: bash ${BASH_SOURCE[0]} {smoke|quick}" >&2; exit 2 ;;
esac
shift || true
EXTRA_ARGS=("$@")

UNIVTAC_ROOT="${UNIVTAC_ROOT:-$(cd "${SCRIPT_DIR}/../../OpenTacBench" && pwd)}"
CONDA_SH="${CONDA_SH:-/mnt/a/ljz/miniconda/etc/profile.d/conda.sh}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-/mnt/data/ljz/opentacbench/conda-envs/UniVTAC}"
CONFIG_PATH="${CAPX_CONFIG_PATH:-env_configs/opentac/play_piano_shadow_digit_smoke.yaml}"
if [[ "${CONFIG_PATH}" = /* ]]; then CONFIG_FILE="${CONFIG_PATH}"; else CONFIG_FILE="${CAPX_DIR}/${CONFIG_PATH}"; fi
[[ -f "${CONFIG_FILE}" ]] || { echo "[capx-shadow] config missing: ${CONFIG_FILE}" >&2; exit 2; }
[[ -f "${UNIVTAC_ROOT}/env/tasks/arm_shadow_piano.py" ]] || { echo "[capx-shadow] OpenTacBench Shadow task missing: ${UNIVTAC_ROOT}" >&2; exit 2; }
[[ -x "${UNIVTAC_ROOT}/.cache/piano_tactile/digit/venv/bin/python" ]] || { echo "[capx-shadow] DIGIT renderer is not installed" >&2; exit 2; }

export PYTHONPATH="${CAPX_DIR}:${UNIVTAC_ROOT}:${PYTHONPATH:-}"
export PYTHONUNBUFFERED=1 HEADLESS=1 LIVESTREAM=0 OMNI_KIT_ACCEPT_EULA=YES
export HOME="${UNIVTAC_HOME:-/mnt/data/ljz/opentacbench/kit-home}"
export XDG_CACHE_HOME="${UNIVTAC_XDG_CACHE_HOME:-/mnt/data/ljz/opentacbench/kit-cache}"
export XDG_DATA_HOME="${UNIVTAC_XDG_DATA_HOME:-/mnt/data/ljz/opentacbench/kit-data}"
export XDG_CONFIG_HOME="${UNIVTAC_XDG_CONFIG_HOME:-/mnt/data/ljz/opentacbench/kit-config}"
mkdir -p "${HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}"

set +u
# shellcheck disable=SC1090
source "${CONDA_SH}"
conda activate "${CONDA_ENV_NAME}"
set -u
export CUDA_HOME="${CUDA_HOME:-${CONDA_PREFIX}}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib:${LD_LIBRARY_PATH:-}"
echo "[capx-shadow] config=${CONFIG_FILE} root=${UNIVTAC_ROOT} trials=${TRIALS} gpu=${CUDA_VISIBLE_DEVICES:-unset}"
cd "${UNIVTAC_ROOT}"
exec python "${CAPX_DIR}/capx/envs/launch_opentac_shadow.py" \
  --config-path "${CONFIG_FILE}" --total-trials "${TRIALS}" --num-workers "${CAPX_WORKERS:-1}" \
  --record-video "${CAPX_RECORD_VIDEO:-True}" \
  --output-dir "${CAPX_OUTPUT_DIR:-${CAPX_RUN_ROOT}/opentac_shadow_piano}" \
  --model "${CAPX_MODEL:-gpt-4o}" --server-url "${CAPX_SERVER_URL:-http://127.0.0.1:8110/chat/completions}" \
  --max-tokens "${CAPX_MAX_TOKENS:-8192}" --temperature "${CAPX_TEMPERATURE:-1.0}" \
  --reasoning-effort "${CAPX_REASONING_EFFORT:-medium}" \
  --univtac-device "${UNIVTAC_DEVICE:-cuda:0}" "${EXTRA_ARGS[@]}"
