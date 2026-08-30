#!/usr/bin/env bash

# Shared environment for the local CaP-X reproduction. Source this file from
# the other scripts so caches never fall back to the nearly full root disk.

CAPX_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export TABERO_ROOT="${TABERO_ROOT:-$(cd -- "${CAPX_SCRIPTS_DIR}/.." && pwd)}"
export CAPX_DIR="${CAPX_DIR:-${TABERO_ROOT}/cap-x}"
export CAPX_CACHE_ROOT="${CAPX_CACHE_ROOT:-${TABERO_ROOT}/cap-x-cache}"
export CAPX_RUN_ROOT="${CAPX_RUN_ROOT:-${TABERO_ROOT}/capx-runs}"

export CAPX_SECRET_ENV="${CAPX_SECRET_ENV:-${TABERO_ROOT}/.capx_secrets.env}"
if [[ -f "${CAPX_SECRET_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${CAPX_SECRET_ENV}"
fi

export UV_CACHE_DIR="${UV_CACHE_DIR:-${CAPX_CACHE_ROOT}/uv}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-${CAPX_CACHE_ROOT}/python}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${CAPX_CACHE_ROOT}/pip}"
export HF_HOME="${HF_HOME:-${CAPX_CACHE_ROOT}/hf}"
export TORCH_HOME="${TORCH_HOME:-${CAPX_CACHE_ROOT}/torch}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${CAPX_CACHE_ROOT}/xdg}"
export MODELSCOPE_CACHE="${MODELSCOPE_CACHE:-${CAPX_CACHE_ROOT}/modelscope}"
export CAPX_SAM3_DIR="${CAPX_SAM3_DIR:-${MODELSCOPE_CACHE}/facebook/sam3}"
export CAPX_SAM3_CHECKPOINT="${CAPX_SAM3_CHECKPOINT:-${CAPX_SAM3_DIR}/sam3.pt}"
export TMPDIR="${TMPDIR:-/dev/shm/${USER:-$(id -un)}/capx-tmp}"

if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
  export CAPX_GPU="${CUDA_VISIBLE_DEVICES%%,*}"
else
  export CAPX_GPU="${CAPX_GPU:-7}"
  export CUDA_VISIBLE_DEVICES="${CAPX_GPU}"
fi
export MUJOCO_EGL_DEVICE_ID="${MUJOCO_EGL_DEVICE_ID:-0}"
export MUJOCO_GL="${MUJOCO_GL:-egl}"
export PYOPENGL_PLATFORM="${PYOPENGL_PLATFORM:-egl}"
export HF_HUB_DISABLE_TELEMETRY="${HF_HUB_DISABLE_TELEMETRY:-1}"
export CAPX_HF_ENDPOINT="${CAPX_HF_ENDPOINT:-https://hf-mirror.com}"
export HF_ENDPOINT="${HF_ENDPOINT:-${CAPX_HF_ENDPOINT}}"

export CAPX_MODEL="${CAPX_MODEL:-gpt-4o}"
export CAPX_PROXY_HOST="${CAPX_PROXY_HOST:-127.0.0.1}"
export CAPX_PROXY_PORT="${CAPX_PROXY_PORT:-8110}"
export CAPX_API_BASE_URL="${CAPX_API_BASE_URL:-https://api.xty.app/v1}"
export CAPX_SERVER_URL="${CAPX_SERVER_URL:-${CAPX_API_BASE_URL%/}/chat/completions}"

# Keep CaP-X's local API traffic away from an SSH-forwarded internet proxy.
_capx_no_proxy="${NO_PROXY:-${no_proxy:-}}"
for _capx_local_host in 127.0.0.1 localhost; do
  if [[ ",${_capx_no_proxy}," != *",${_capx_local_host},"* ]]; then
    _capx_no_proxy="${_capx_no_proxy:+${_capx_no_proxy},}${_capx_local_host}"
  fi
done
export NO_PROXY="${_capx_no_proxy}"
export no_proxy="${_capx_no_proxy}"
unset _capx_no_proxy _capx_local_host

mkdir -p \
  "${UV_CACHE_DIR}" \
  "${UV_PYTHON_INSTALL_DIR}" \
  "${PIP_CACHE_DIR}" \
  "${HF_HOME}" \
  "${TORCH_HOME}" \
  "${XDG_CACHE_HOME}" \
  "${MODELSCOPE_CACHE}" \
  "${TMPDIR}" \
  "${CAPX_RUN_ROOT}"

if [[ "${CAPX_ENV_AUTO_ACTIVATE:-1}" == "1" && -f "${CAPX_DIR}/.venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "${CAPX_DIR}/.venv/bin/activate"
fi
