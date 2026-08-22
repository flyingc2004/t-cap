#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CAPX_DIR="${CAPX_DIR:-${ROOT}/cap-x}"
CAPX_PYTHON="${CAPX_PYTHON:-${CAPX_DIR}/.venv/bin/python}"
SOURCE_RUN="${SOURCE_RUN:-${ROOT}/capx-runs/lift_can_tactile_official_quick_rep1_20260811T171107Z}"
PHASE="${PHASE:-build}"  # build, validate, eval, all
GPU="${GPU:-4}"
MODEL="${MODEL:-${CAPX_MODEL:-qwen3.7-plus}}"
TEMPERATURE="${TEMPERATURE:-0.0}"
RECORD_VIDEO="${RECORD_VIDEO:-True}"
WORKERS="${WORKERS:-1}"
TRIAL_TIMEOUT_SECONDS="${TRIAL_TIMEOUT_SECONDS:-600}"
MAX_TRIAL_RETRIES="${MAX_TRIAL_RETRIES:-1}"
MAX_REGENERATIONS="${MAX_REGENERATIONS:-2}"
PROCESS_TIMEOUT_SECONDS="${PROCESS_TIMEOUT_SECONDS:-0}"
PROCESS_KILL_AFTER="${PROCESS_KILL_AFTER:-60s}"
RUN_ROOT="${RUN_ROOT:-${ROOT}/capx-runs/liftcan_tactile_code_memory_$(date -u +%Y%m%dT%H%M%SZ)}"
TRAIN_START="${TRAIN_START:-1}"
TRAIN_END="${TRAIN_END:-80}"
VALIDATION_START="${VALIDATION_START:-81}"
VALIDATION_END="${VALIDATION_END:-100}"
EVAL_START="${EVAL_START:-101}"
EVAL_REPEATS="${EVAL_REPEATS:-3}"
EVAL_BATCH="${EVAL_BATCH:-10}"
MEMORY_DIR="${MEMORY_DIR:-${CAPX_DIR}/.capx_tactile_code_memory/lift_can_v1}"
CANDIDATE_PATH="${CANDIDATE_PATH:-${MEMORY_DIR}/candidates.jsonl}"
BANK_PATH="${BANK_PATH:-${MEMORY_DIR}/bank.jsonl}"
MANIFEST_PATH="${MANIFEST_PATH:-${MEMORY_DIR}/validation_manifest.json}"
UNIVTAC_RUNNER="${UNIVTAC_RUNNER:-${ROOT}/capx_scripts/run_capx_univtac.sh}"

if [[ -f "${ROOT}/.capx_secrets.env" ]]; then
  # shellcheck disable=SC1090
  source "${ROOT}/.capx_secrets.env"
fi

mkdir -p "${RUN_ROOT}" "${MEMORY_DIR}"

echo "[stage1] phase=${PHASE}"
echo "[stage1] source_run=${SOURCE_RUN}"
echo "[stage1] run_root=${RUN_ROOT}"
echo "[stage1] candidate_path=${CANDIDATE_PATH}"
echo "[stage1] bank_path=${BANK_PATH}"
echo "[stage1] trial_timeout_seconds=${TRIAL_TIMEOUT_SECONDS}"
echo "[stage1] max_regenerations=${MAX_REGENERATIONS}"
echo "[stage1] process_timeout_seconds=${PROCESS_TIMEOUT_SECONDS} (0=auto)"

build_candidates() {
  PYTHONPATH="${CAPX_DIR}:${PYTHONPATH:-}" "${CAPX_PYTHON}" \
    "${CAPX_DIR}/scripts/compile_tactile_code_memory.py" \
    --source-run "${SOURCE_RUN}" \
    --train-start "${TRAIN_START}" \
    --train-end "${TRAIN_END}" \
    --validation-start "${VALIDATION_START}" \
    --validation-end "${VALIDATION_END}" \
    --candidate-output "${CANDIDATE_PATH}" \
    --bank-output "${BANK_PATH}" \
    --validation-manifest "${MANIFEST_PATH}"
}

promote_after_validation() {
  local validation_run="$1"
  PYTHONPATH="${CAPX_DIR}:${PYTHONPATH:-}" "${CAPX_PYTHON}" \
    "${CAPX_DIR}/scripts/compile_tactile_code_memory.py" \
    --source-run "${SOURCE_RUN}" \
    --train-start "${TRAIN_START}" \
    --train-end "${TRAIN_END}" \
    --validation-start "${VALIDATION_START}" \
    --validation-end "${VALIDATION_END}" \
    --validation-run "${validation_run}" \
    --candidate-output "${CANDIDATE_PATH}" \
    --bank-output "${BANK_PATH}" \
    --validation-manifest "${MANIFEST_PATH}"
}

make_resume_config() {
  local base_config="$1"
  local output_config="$2"
  local resume_idx="$3"
  PYTHONPATH="${CAPX_DIR}:${PYTHONPATH:-}" "${CAPX_PYTHON}" - "${base_config}" "${output_config}" "${resume_idx}" <<'PY'
import pathlib
import sys
import yaml

base = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
resume = int(sys.argv[3])
cfg = yaml.safe_load(base.read_text(encoding="utf-8"))
cfg["resume_idx"] = resume
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(yaml.safe_dump(cfg, sort_keys=False), encoding="utf-8")
PY
}

run_range() {
  local label="$1"
  local config_rel="$2"
  local start="$3"
  local end="$4"
  local out_dir="${RUN_ROOT}/${label}_${start}_${end}"
  local temp_cfg="${RUN_ROOT}/configs/${label}_${start}_${end}.yaml"
  local base_cfg="${CAPX_DIR}/${config_rel}"
  local num_trials=$((end - start + 1))
  local watchdog="${PROCESS_TIMEOUT_SECONDS}"
  if [[ "${watchdog}" == "0" ]]; then
    watchdog=$((num_trials * (TRIAL_TIMEOUT_SECONDS + 180) + 300))
  fi
  make_resume_config "${base_cfg}" "${temp_cfg}" "${start}"
  echo "[stage1] run label=${label} seeds=${start}-${end} output=${out_dir}"
  echo "[stage1] run watchdog=${watchdog}s"
  CUDA_VISIBLE_DEVICES="${GPU}" \
  CAPX_CONFIG_PATH="${temp_cfg}" \
  CAPX_TRIALS="${end}" \
  CAPX_WORKERS="${WORKERS}" \
  CAPX_RECORD_VIDEO="${RECORD_VIDEO}" \
  CAPX_MODEL="${MODEL}" \
  CAPX_TEMPERATURE="${TEMPERATURE}" \
  CAPX_OUTPUT_DIR="${out_dir}" \
  CAPX_PRESERVE_OUTPUT_DIR=1 \
  CAPX_TRIAL_TIMEOUT_SECONDS="${TRIAL_TIMEOUT_SECONDS}" \
  CAPX_MAX_TRIAL_RETRIES="${MAX_TRIAL_RETRIES}" \
  CAPX_MAX_REGENERATIONS="${MAX_REGENERATIONS}" \
  timeout --signal=INT --kill-after="${PROCESS_KILL_AFTER}" "${watchdog}s" \
    bash "${UNIVTAC_RUNNER}" quick
}

run_validation() {
  run_range \
    "validation_candidate_memory" \
    "env_configs/univtac/lift_can_tactile_minimal_memory_candidate.yaml" \
    "${VALIDATION_START}" \
    "${VALIDATION_END}"
  promote_after_validation "${RUN_ROOT}/validation_candidate_memory_${VALIDATION_START}_${VALIDATION_END}"
}

run_eval() {
  local rep
  local start
  local end
  local groups=(
    "handcrafted:env_configs/univtac/lift_can_tactile_official.yaml"
    "minimal:env_configs/univtac/lift_can_tactile_minimal.yaml"
    "initial_memory:env_configs/univtac/lift_can_tactile_minimal_memory_initial.yaml"
    "closed_loop_memory:env_configs/univtac/lift_can_tactile_minimal_memory_closed_loop.yaml"
  )
  for group in "${groups[@]}"; do
    local label="${group%%:*}"
    local config="${group#*:}"
    for rep in $(seq 1 "${EVAL_REPEATS}"); do
      start=$((EVAL_START + (rep - 1) * EVAL_BATCH))
      end=$((start + EVAL_BATCH - 1))
      run_range "${label}_rep${rep}" "${config}" "${start}" "${end}"
    done
  done
  PYTHONPATH="${CAPX_DIR}:${PYTHONPATH:-}" "${CAPX_PYTHON}" \
    "${CAPX_DIR}/scripts/summarize_tactile_code_memory_eval.py" \
    --run-root "${RUN_ROOT}"
}

case "${PHASE}" in
  build)
    build_candidates
    ;;
  validate)
    build_candidates
    run_validation
    ;;
  eval)
    run_eval
    ;;
  all)
    build_candidates
    run_validation
    run_eval
    ;;
  *)
    echo "Usage: PHASE=build|validate|eval|all bash ${BASH_SOURCE[0]}" >&2
    exit 2
    ;;
esac

echo "[stage1] done"
