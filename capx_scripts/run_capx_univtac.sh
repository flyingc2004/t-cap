#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONDA_SH="${CONDA_SH:-/mnt/sdc/ljz/miniforge3/etc/profile.d/conda.sh}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-UniVTAC}"
UNIVTAC_ROOT="${UNIVTAC_ROOT:-/mnt/sdc/ljz/UniVTAC}"
export CAPX_ENV_AUTO_ACTIVATE=0
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

CONFIG_PATH="${CAPX_CONFIG_PATH:-env_configs/univtac/grasp_classify_tactile_preplace.yaml}"
if [[ "${CONFIG_PATH}" = /* ]]; then
  CONFIG_FILE="${CONFIG_PATH}"
else
  CONFIG_FILE="${CAPX_DIR}/${CONFIG_PATH}"
fi
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[capx-univtac] ERROR: config not found: ${CONFIG_FILE}" >&2
  exit 2
fi

export PYTHONPATH="${CAPX_DIR}:${PYTHONPATH:-}"
export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
export HEADLESS="${HEADLESS:-1}"
export LIVESTREAM="${LIVESTREAM:-0}"
export UNIVTAC_DEVICE="${UNIVTAC_DEVICE:-cuda:0}"
export MUJOCO_GL="${MUJOCO_GL:-egl}"
export OMNI_KIT_ACCEPT_EULA="${OMNI_KIT_ACCEPT_EULA:-YES}"

echo "[capx-univtac] config=${CONFIG_FILE}"
echo "[capx-univtac] univtac_root=${UNIVTAC_ROOT}"
echo "[capx-univtac] mode=${MODE}, trials=${TRIALS}"
echo "[capx-univtac] cuda_visible_devices=${CUDA_VISIBLE_DEVICES:-}, univtac_device=${UNIVTAC_DEVICE}"

if [[ -f "${CONDA_SH}" ]]; then
  # shellcheck disable=SC1090
  set +u
  source "${CONDA_SH}"
  conda activate "${CONDA_ENV_NAME}"
  set -u
fi

export CUDA_HOME="${CUDA_HOME:-${CONDA_PREFIX:-/mnt/sdc/ljz/miniforge3/envs/${CONDA_ENV_NAME}}}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib:${LD_LIBRARY_PATH:-}"
export HOME="${UNIVTAC_HOME:-${UNIVTAC_ROOT}/.home}"
export XDG_CACHE_HOME="${UNIVTAC_XDG_CACHE_HOME:-${UNIVTAC_ROOT}/.cache}"
export XDG_DATA_HOME="${UNIVTAC_XDG_DATA_HOME:-${UNIVTAC_ROOT}/.local/share}"
export XDG_CONFIG_HOME="${UNIVTAC_XDG_CONFIG_HOME:-${UNIVTAC_ROOT}/.config}"
mkdir -p "${HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}"
echo "[capx-univtac] cuda_home=${CUDA_HOME}, home=${HOME}"

cd "${UNIVTAC_ROOT}"

python "${CAPX_DIR}/capx/envs/launch_univtac.py" \
  --config-path "${CONFIG_FILE}" \
  --total-trials "${TRIALS}" \
  --num-workers "${CAPX_WORKERS:-1}" \
  --record-video "${CAPX_RECORD_VIDEO:-False}" \
  --output-dir "${CAPX_OUTPUT_DIR:-${CAPX_RUN_ROOT}/univtac_grasp_classify_tactile}" \
  --model "${CAPX_MODEL:-gpt-4o}" \
  --server-url "${CAPX_SERVER_URL:-http://127.0.0.1:8110/chat/completions}" \
  --max-tokens "${CAPX_MAX_TOKENS:-4096}" \
  --temperature "${CAPX_TEMPERATURE:-1.0}" \
  --univtac-device "${UNIVTAC_DEVICE}" \
  "${EXTRA_ARGS[@]}"
