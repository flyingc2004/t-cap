#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CAPX_ENV_AUTO_ACTIVATE=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

die() {
  echo "[repair-capx] ERROR: $*" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

[[ -d "${CAPX_DIR}/.git" ]] || die "Repository not found: ${CAPX_DIR}"
[[ -f "${CAPX_DIR}/pyproject.toml" ]] || die "Missing pyproject.toml under ${CAPX_DIR}"
[[ -d "${CAPX_DIR}/capx/third_party/robosuite/.git" ]] || die "Missing robosuite submodule. Rerun setup_capx.sh first."
[[ -d "${CAPX_DIR}/capx/third_party/contact_graspnet_pytorch/.git" ]] || die "Missing contact_graspnet_pytorch submodule. Rerun setup_capx.sh first."
[[ -d "${CAPX_DIR}/capx/third_party/sam3/.git" ]] || die "Missing sam3 submodule. Rerun setup_capx.sh first."

require_command uv
require_command nvidia-smi

echo "[repair-capx] CAPX_DIR=${CAPX_DIR}"
echo "[repair-capx] UV_CACHE_DIR=${UV_CACHE_DIR}"
echo "[repair-capx] UV_PYTHON_INSTALL_DIR=${UV_PYTHON_INSTALL_DIR}"
echo "[repair-capx] Installing/reusing Python 3.10..."
uv python install 3.10

cd "${CAPX_DIR}"
if [[ ! -x "${CAPX_DIR}/.venv/bin/python" ]]; then
  echo "[repair-capx] Creating ${CAPX_DIR}/.venv..."
  uv venv -p 3.10
else
  existing_version="$("${CAPX_DIR}/.venv/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  [[ "${existing_version}" == "3.10" ]] || die "Existing .venv uses Python ${existing_version}; Python 3.10 is required."
  echo "[repair-capx] Reusing the existing Python 3.10 virtual environment."
fi

echo "[repair-capx] Synchronizing dependencies..."
uv sync --extra robosuite --extra contactgraspnet

echo "[repair-capx] Import smoke test..."
"${CAPX_DIR}/.venv/bin/python" - <<'PY'
import importlib
import sys

print(f"[repair-capx] python={sys.version.split()[0]}")
for module_name in ("capx", "mujoco", "robosuite", "OpenGL.EGL", "torch", "contact_graspnet_pytorch"):
    module = importlib.import_module(module_name)
    print(f"[repair-capx] import {module_name}: ok ({getattr(module, '__version__', 'unknown')})")
PY

echo "[repair-capx] Environment repair completed."
