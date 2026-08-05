#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

die() {
  echo "[check-capx] ERROR: $*" >&2
  exit 2
}

is_git_worktree() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

show_port() {
  local port="$1"
  local output=""

  if command -v ss >/dev/null 2>&1; then
    output="$(ss -H -ltnp "sport = :${port}" 2>/dev/null || true)"
    [[ -n "${output}" ]] || output="$(ss -H -ltn "sport = :${port}" 2>/dev/null || true)"
  elif command -v lsof >/dev/null 2>&1; then
    output="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  fi

  if [[ -n "${output}" ]]; then
    echo "[check-capx] Port ${port}: IN USE"
    printf '%s\n' "${output}" | sed 's/^/  /'
  else
    echo "[check-capx] Port ${port}: free"
  fi
}

is_git_worktree "${CAPX_DIR}" || die "Repository not found: ${CAPX_DIR}"
[[ -x "${CAPX_DIR}/.venv/bin/python" ]] || die "Virtual environment not found. Run setup_capx.sh first."
[[ -f "${CAPX_DIR}/capx/envs/launch.py" ]] || die "Missing CaP-X launcher under ${CAPX_DIR}."
[[ -f "${CAPX_DIR}/env_configs/cube_stack/franka_robosuite_cube_stack.yaml" ]] || die "Missing Cube Stack config."

echo "[check-capx] CAPX_DIR=${CAPX_DIR}"
echo "[check-capx] commit=$(git -C "${CAPX_DIR}" rev-parse HEAD)"
echo "[check-capx] CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
echo "[check-capx] MUJOCO_GL=${MUJOCO_GL}"
echo "[check-capx] Python=$("${CAPX_DIR}/.venv/bin/python" --version 2>&1)"

if ! nvidia-smi -L; then
  die "nvidia-smi cannot access the NVIDIA driver in this shell."
fi

cd "${CAPX_DIR}"
if ! "${CAPX_DIR}/.venv/bin/python" - <<'PY'
import importlib
import sys

if sys.version_info[:2] != (3, 10):
    raise RuntimeError(f"CaP-X requires Python 3.10, got {sys.version.split()[0]}")

for module_name in ("capx", "mujoco", "robosuite", "OpenGL.EGL", "torch", "contact_graspnet_pytorch"):
    module = importlib.import_module(module_name)
    version = getattr(module, "__version__", "unknown")
    print(f"[check-capx] import {module_name}: ok (version={version})")

import torch

print(f"[check-capx] torch.cuda.is_available={torch.cuda.is_available()}")
print(f"[check-capx] torch.cuda.device_count={torch.cuda.device_count()}")
if not torch.cuda.is_available():
    raise RuntimeError("PyTorch cannot access CUDA in this shell")
print(f"[check-capx] visible GPU 0={torch.cuda.get_device_name(0)}")
PY
then
  echo "[check-capx] Dependency import failed. Repair with:" >&2
  echo "  bash ${SCRIPT_DIR}/repair_capx_env.sh" >&2
  exit 2
fi

echo "[check-capx] Port status (nothing will be stopped):"
for port in "${CAPX_PROXY_PORT}" 8114 8115 8116; do
  show_port "${port}"
done

echo "[check-capx] Disk usage:"
df -h "${TABERO_ROOT}" "${TMPDIR}" | awk 'NR == 1 || !seen[$1]++'

echo "[check-capx] All static checks passed."
