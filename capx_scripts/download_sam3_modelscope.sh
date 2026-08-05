#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

die() {
  echo "[sam3-modelscope] ERROR: $*" >&2
  exit 2
}

CAPX_MODELSCOPE_BIN="${CAPX_MODELSCOPE_BIN:-modelscope}"
command -v "${CAPX_MODELSCOPE_BIN}" >/dev/null 2>&1 || die "Missing command: ${CAPX_MODELSCOPE_BIN}. Activate the environment that provides modelscope, or set CAPX_MODELSCOPE_BIN=/path/to/modelscope."

mkdir -p "${CAPX_SAM3_DIR}"

echo "[sam3-modelscope] Downloading facebook/sam3 into ${CAPX_SAM3_DIR}"
"${CAPX_MODELSCOPE_BIN}" download \
  --model facebook/sam3 \
  --local_dir "${CAPX_SAM3_DIR}"

[[ -f "${CAPX_SAM3_CHECKPOINT}" ]] || die "Expected checkpoint not found: ${CAPX_SAM3_CHECKPOINT}"

echo "[sam3-modelscope] SAM3 checkpoint ready: ${CAPX_SAM3_CHECKPOINT}"
