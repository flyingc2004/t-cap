#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/capx_env.sh"

die() {
  echo "[tactile-ab10] ERROR: $*" >&2
  exit 2
}

TACTILE_CONFIG="${CAPX_AB_TACTILE_CONFIG:-env_configs/cube_stack/franka_robosuite_cube_stack_tactile.yaml}"
TRIALS="${CAPX_AB_TRIALS:-10}"
WORKERS="${CAPX_AB_WORKERS:-5}"
TEMPERATURE="${CAPX_AB_TEMPERATURE:-0.0}"
RECORD_VIDEO="${CAPX_AB_RECORD_VIDEO:-True}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
AB_RUN_DIR="${CAPX_AB_RUN_DIR:-${CAPX_RUN_ROOT}/cube_stack_ab10_${timestamp}}"
DEFAULT_MEMORY_FILE="${CAPX_DIR}/.capx_tactile_strategies.jsonl"
TACTILE_CONFIG="${TACTILE_CONFIG/#\~/$HOME}"
if [[ "${TACTILE_CONFIG}" = /* ]]; then
  TACTILE_CONFIG_FILE="${TACTILE_CONFIG}"
else
  TACTILE_CONFIG_FILE="${CAPX_DIR}/${TACTILE_CONFIG}"
fi

[[ -f "${TACTILE_CONFIG_FILE}" ]] || die "Tactile config not found: ${TACTILE_CONFIG_FILE}"
[[ "${TRIALS}" =~ ^[1-9][0-9]*$ ]] || die "CAPX_AB_TRIALS must be a positive integer."
[[ "${WORKERS}" =~ ^[1-9][0-9]*$ ]] || die "CAPX_AB_WORKERS must be a positive integer."

NO_MEMORY_CONFIG="${AB_RUN_DIR}/franka_robosuite_cube_stack_tactile_no_memory.yaml"
MEMORY_CONFIG="${AB_RUN_DIR}/franka_robosuite_cube_stack_tactile_memory.yaml"
MEMORY_SNAPSHOT="${AB_RUN_DIR}/ab_memory_snapshot.jsonl"
MEMORY_WORK_FILE="${AB_RUN_DIR}/ab_memory_work.jsonl"
NO_MEMORY_RUN="${AB_RUN_DIR}/no_memory"
MEMORY_RUN="${AB_RUN_DIR}/memory"

mkdir -p "${AB_RUN_DIR}"

"${CAPX_DIR}/.venv/bin/python" - \
  "${TACTILE_CONFIG_FILE}" \
  "${NO_MEMORY_CONFIG}" \
  "${MEMORY_CONFIG}" \
  "${MEMORY_SNAPSHOT}" \
  "${MEMORY_WORK_FILE}" \
  "${DEFAULT_MEMORY_FILE}" <<'PY'
import shutil
import sys
from pathlib import Path

import yaml

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
memory_dst = Path(sys.argv[3])
snapshot = Path(sys.argv[4])
memory_work = Path(sys.argv[5])
default_memory = Path(sys.argv[6])

cfg = yaml.safe_load(src.read_text(encoding="utf-8"))
prompt = cfg["env"]["cfg"].get("prompt", "")
remove_lines = {
    "- Prefer learned tactile strategy memory when it suggests retry or placement adjustments.",
    "- Historical reward/success/task completion in tactile strategy memory is not a runtime observation.",
}
cfg["env"]["cfg"]["prompt"] = "\n".join(
    line for line in prompt.splitlines() if line.strip() not in remove_lines
).rstrip() + "\n"
cfg["tactile_strategy_memory"] = False
cfg["tactile_strategy_memory_path"] = str(snapshot)
cfg["tactile_strategy_top_k"] = 0
dst.write_text(yaml.safe_dump(cfg, sort_keys=False), encoding="utf-8")

snapshot.parent.mkdir(parents=True, exist_ok=True)
if default_memory.exists():
    shutil.copyfile(default_memory, snapshot)
else:
    snapshot.write_text("", encoding="utf-8")

memory_work.write_text(snapshot.read_text(encoding="utf-8"), encoding="utf-8")
memory_cfg = yaml.safe_load(src.read_text(encoding="utf-8"))
memory_cfg["tactile_strategy_memory"] = True
memory_cfg["tactile_strategy_memory_read_path"] = str(snapshot)
memory_cfg["tactile_strategy_memory_path"] = str(memory_work)
memory_cfg["tactile_strategy_top_k"] = int(memory_cfg.get("tactile_strategy_top_k", 3))
memory_dst.write_text(yaml.safe_dump(memory_cfg, sort_keys=False), encoding="utf-8")
PY

echo "[tactile-ab10] AB run dir: ${AB_RUN_DIR}"
echo "[tactile-ab10] no-memory yaml: ${NO_MEMORY_CONFIG}"
echo "[tactile-ab10] memory yaml: ${MEMORY_CONFIG}"
echo "[tactile-ab10] memory snapshot: ${MEMORY_SNAPSHOT}"
echo "[tactile-ab10] memory work file: ${MEMORY_WORK_FILE}"
echo "[tactile-ab10] baseline output: ${NO_MEMORY_RUN}"
echo "[tactile-ab10] memory output: ${MEMORY_RUN}"
echo "[tactile-ab10] trials=${TRIALS}, workers=${WORKERS}, temperature=${TEMPERATURE}, record_video=${RECORD_VIDEO}"

run_group() {
  local label="$1"
  local config_path="$2"
  local run_dir="$3"
  echo "[tactile-ab10] Running ${label}: ${run_dir}"
  (
    cd "${TABERO_ROOT}"
    CAPX_CONFIG_PATH="${config_path}" \
    CAPX_RECORD_VIDEO="${RECORD_VIDEO}" \
    CAPX_TRIALS="${TRIALS}" \
    CAPX_WORKERS="${WORKERS}" \
    CAPX_TEMPERATURE="${TEMPERATURE}" \
    CAPX_RUN_DIR="${run_dir}" \
    bash capx_scripts/run_capx_cube_stack.sh quick
  )
}

run_group "no-memory baseline" "${NO_MEMORY_CONFIG}" "${NO_MEMORY_RUN}"
run_group "memory" "${MEMORY_CONFIG}" "${MEMORY_RUN}"

"${CAPX_DIR}/.venv/bin/python" - \
  "${AB_RUN_DIR}" \
  "${NO_MEMORY_RUN}" \
  "${MEMORY_RUN}" \
  "${MEMORY_SNAPSHOT}" \
  "${MEMORY_WORK_FILE}" \
  "${DEFAULT_MEMORY_FILE}" <<'PY'
import csv
import json
import re
import sys
from pathlib import Path

ab_dir = Path(sys.argv[1])
runs = {
    "no_memory": Path(sys.argv[2]),
    "memory": Path(sys.argv[3]),
}
memory_snapshot = Path(sys.argv[4])
memory_work = Path(sys.argv[5])
default_memory = Path(sys.argv[6])
patterns = [
    "get_tactile_summary",
    "is_contacting",
    "is_slipping",
    "is_grasp_stable",
    "retrieve_tactile_strategies",
    "retry_pos",
    "z_approach",
]


def parse_summary(log_path: Path) -> dict:
    text = log_path.read_text(encoding="utf-8", errors="ignore") if log_path.exists() else ""
    match = re.search(
        r"Code generation success rate / Average reward / Task completed:\s*\n"
        r"([0-9.]+)/([0-9.]+)/([0-9]+)",
        text,
    )
    if not match:
        return {"success_rate": None, "average_reward": None, "task_completed": None}
    return {
        "success_rate": float(match.group(1)),
        "average_reward": float(match.group(2)),
        "task_completed": int(match.group(3)),
    }


def count_memory_lines(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for line in path.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip())


def collect_code_metrics(label: str, run_dir: Path) -> tuple[list[dict], dict]:
    rows = []
    aggregate = {pattern: 0 for pattern in patterns}
    aggregate.update({"trial_count": 0, "code_files": 0})
    for code_path in sorted(run_dir.rglob("code.py")):
        text = code_path.read_text(encoding="utf-8", errors="ignore")
        trial_match = re.search(r"trial_(\d+)_", str(code_path))
        row = {
            "group": label,
            "trial": int(trial_match.group(1)) if trial_match else "",
            "code_path": str(code_path),
        }
        for pattern in patterns:
            count = text.count(pattern)
            row[pattern] = count
            aggregate[pattern] += count
        row["has_tactile_retry"] = int(
            ("if " in text)
            and ("retry" in text.lower())
            and any(token in text for token in ["is_contacting", "is_slipping", "is_grasp_stable", "get_tactile_summary"])
        )
        aggregate["trial_count"] += 1
        aggregate["code_files"] += 1
        rows.append(row)
    return rows, aggregate


all_rows = []
snapshot_records = count_memory_lines(memory_snapshot)
work_final_records = count_memory_lines(memory_work)
default_records_after_ab = count_memory_lines(default_memory)
summary = {
    "ab_run_dir": str(ab_dir),
    "memory_snapshot": str(memory_snapshot),
    "memory_snapshot_initial_records": snapshot_records,
    "memory_work_file": str(memory_work),
    "memory_work_final_records": work_final_records,
    "memory_work_added_records": max(0, work_final_records - snapshot_records),
    "default_memory_file": str(default_memory),
    "default_memory_records_after_ab": default_records_after_ab,
    "default_memory_unchanged_by_ab": default_records_after_ab == snapshot_records,
    "groups": {},
}

for label, run_dir in runs.items():
    rows, aggregate = collect_code_metrics(label, run_dir)
    all_rows.extend(rows)
    log_path = run_dir / "evaluation.log"
    log_text = log_path.read_text(encoding="utf-8", errors="ignore") if log_path.exists() else ""
    summary["groups"][label] = {
        "run_dir": str(run_dir),
        "evaluation_log": str(log_path),
        "summary": parse_summary(log_path),
        "code_metrics": aggregate,
        "prompt_injection_count": log_text.count("[tactile-memory] Injected"),
        "strategy_save_count": log_text.count("[tactile-memory] Saved"),
        "timeline_count": len(list(run_dir.rglob("tactile_timeline.json"))),
        "overlay_video_count": len(list(run_dir.rglob("video_tactile_overlay.mp4"))),
    }

csv_path = ab_dir / "ab_code_metrics.csv"
with csv_path.open("w", newline="", encoding="utf-8") as file:
    fieldnames = ["group", "trial", "code_path", *patterns, "has_tactile_retry"]
    writer = csv.DictWriter(file, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(all_rows)

summary_path = ab_dir / "ab_summary.json"
summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

print("[tactile-ab10] Summary:", summary_path)
print("[tactile-ab10] Code metrics:", csv_path)
print(
    f"[tactile-ab10] memory records: "
    f"snapshot={summary['memory_snapshot_initial_records']} "
    f"work_final={summary['memory_work_final_records']} "
    f"work_added={summary['memory_work_added_records']} "
    f"default_after_ab={summary['default_memory_records_after_ab']} "
    f"default_unchanged={summary['default_memory_unchanged_by_ab']}"
)
for label in ("no_memory", "memory"):
    group = summary["groups"][label]
    print(
        f"[tactile-ab10] {label}: "
        f"{group['summary']} "
        f"prompt_injections={group['prompt_injection_count']} "
        f"strategy_saves={group['strategy_save_count']} "
        f"overlays={group['overlay_video_count']}"
    )
PY

echo "[tactile-ab10] Done: ${AB_RUN_DIR}"
