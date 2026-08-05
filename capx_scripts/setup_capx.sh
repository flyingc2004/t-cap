#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CAPX_ENV_AUTO_ACTIVATE=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

CAPX_REPO_URL="${CAPX_REPO_URL:-https://github.com/capgym/cap-x.git}"
CAPX_GIT_RETRIES="${CAPX_GIT_RETRIES:-3}"
CAPX_GIT_DEPTH="${CAPX_GIT_DEPTH:-1}"
CAPX_REQUIRED_SUBMODULES=(
  capx/third_party/robosuite
  capx/third_party/sam3
  capx/third_party/contact_graspnet_pytorch
)

die() {
  echo "[setup-capx] ERROR: $*" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

is_git_worktree() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

retry() {
  local max_attempts="$1"
  shift
  local attempt=1

  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= max_attempts )); then
      return 1
    fi
    echo "[setup-capx] Network operation failed (attempt ${attempt}/${max_attempts}); retrying..." >&2
    sleep "$((attempt * 5))"
    ((attempt += 1))
  done
}

clone_repo_once() {
  rm -rf -- "${clone_tmp}"
  git -c http.version=HTTP/1.1 \
    -c http.lowSpeedLimit=0 \
    clone \
    --depth "${CAPX_GIT_DEPTH}" \
    --single-branch \
    --no-recurse-submodules \
    "${CAPX_REPO_URL}" \
    "${clone_tmp}"
}

update_submodules() {
  git -C "${CAPX_DIR}" submodule sync --recursive -- "${CAPX_REQUIRED_SUBMODULES[@]}" || return 1
  git -C "${CAPX_DIR}" \
    -c http.version=HTTP/1.1 \
    -c http.lowSpeedLimit=0 \
    submodule update \
    --init \
    --recursive \
    --depth "${CAPX_GIT_DEPTH}" \
    --jobs 1 \
    -- "${CAPX_REQUIRED_SUBMODULES[@]}"
}

required_submodules_ready() {
  local relative_path=""
  local full_path=""
  local expected_commit=""
  local actual_commit=""
  local worktree_root=""

  for relative_path in "${CAPX_REQUIRED_SUBMODULES[@]}"; do
    full_path="${CAPX_DIR}/${relative_path}"
    expected_commit="$(git -C "${CAPX_DIR}" ls-tree HEAD "${relative_path}" | awk '{print $3}')"
    worktree_root="$(git -C "${full_path}" rev-parse --show-toplevel 2>/dev/null || true)"
    actual_commit="$(git -C "${full_path}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -z "${expected_commit}" || "${worktree_root}" != "${full_path}" || "${actual_commit}" != "${expected_commit}" ]]; then
      return 1
    fi
  done
  return 0
}

has_library() {
  local library="$1"
  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig -p 2>/dev/null | grep -Fq "${library}"
  elif [[ -x /sbin/ldconfig ]]; then
    /sbin/ldconfig -p 2>/dev/null | grep -Fq "${library}"
  else
    find /usr/lib /lib -name "${library}" -print -quit 2>/dev/null | grep -q .
  fi
}

echo "[setup-capx] Checking host prerequisites..."
require_command git
require_command uv
require_command nvidia-smi

git --version
uv --version

if ! nvidia-smi -L; then
  die "nvidia-smi cannot access the NVIDIA driver in this shell."
fi

missing_libraries=()
has_library libGL.so.1 || missing_libraries+=(libGL.so.1)
has_library libEGL.so.1 || missing_libraries+=(libEGL.so.1)
if (( ${#missing_libraries[@]} > 0 )); then
  printf '[setup-capx] Missing system libraries: %s\n' "${missing_libraries[*]}" >&2
  echo "[setup-capx] Ask the administrator to install Ubuntu packages: libgl1 libegl1" >&2
  echo "[setup-capx] This script will not invoke sudo." >&2
  exit 2
fi

echo "[setup-capx] TABERO_ROOT=${TABERO_ROOT}"
echo "[setup-capx] CAPX_DIR=${CAPX_DIR}"
echo "[setup-capx] CAPX_CACHE_ROOT=${CAPX_CACHE_ROOT}"
echo "[setup-capx] Git download policy: HTTP/1.1, depth=${CAPX_GIT_DEPTH}, retries=${CAPX_GIT_RETRIES}, submodule jobs=1"
echo "[setup-capx] Required submodules: ${CAPX_REQUIRED_SUBMODULES[*]}"

if [[ ! -e "${CAPX_DIR}" ]]; then
  clone_tmp="${CAPX_DIR}.clone-partial.${BASHPID}"
  trap 'rm -rf -- "${clone_tmp:-}"' EXIT
  echo "[setup-capx] Shallow-cloning ${CAPX_REPO_URL}..."
  retry "${CAPX_GIT_RETRIES}" clone_repo_once || die "Git clone failed after ${CAPX_GIT_RETRIES} attempts."
  mv -- "${clone_tmp}" "${CAPX_DIR}"
  trap - EXIT

  echo "[setup-capx] Downloading the required Cube Stack submodules serially..."
  retry "${CAPX_GIT_RETRIES}" update_submodules || die "Submodule download failed after ${CAPX_GIT_RETRIES} attempts. Rerun this script to resume."
elif is_git_worktree "${CAPX_DIR}"; then
  echo "[setup-capx] Existing repository found; it will not be pulled or reset."
  if ! required_submodules_ready; then
    echo "[setup-capx] Initializing the required Cube Stack submodules serially..."
    retry "${CAPX_GIT_RETRIES}" update_submodules || die "Submodule download failed after ${CAPX_GIT_RETRIES} attempts. Rerun this script to resume."
  fi
else
  die "${CAPX_DIR} exists but is not a Git repository. Move it or set CAPX_DIR."
fi

required_submodules_ready || die "One or more required Cube Stack submodules are incomplete. Fix network access and rerun this script."

cd "${CAPX_DIR}"
echo "[setup-capx] Repository commit: $(git rev-parse HEAD)"

echo "[setup-capx] Installing the user-local Python 3.10 runtime..."
uv python install 3.10

if [[ ! -x "${CAPX_DIR}/.venv/bin/python" ]]; then
  echo "[setup-capx] Creating ${CAPX_DIR}/.venv..."
  uv venv -p 3.10
else
  existing_version="$("${CAPX_DIR}/.venv/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  [[ "${existing_version}" == "3.10" ]] || die "Existing .venv uses Python ${existing_version}; Python 3.10 is required."
  echo "[setup-capx] Reusing the existing Python 3.10 virtual environment."
fi

# shellcheck disable=SC1091
source "${CAPX_DIR}/.venv/bin/activate"
hash -r

echo "[setup-capx] Installing the base package, Robosuite extra, and ContactGraspNet extra..."
uv sync --extra robosuite --extra contactgraspnet

echo
echo "[setup-capx] Installation completed. No service was started."
echo "[setup-capx] Next command:"
echo "  bash ${SCRIPT_DIR}/check_capx.sh"
