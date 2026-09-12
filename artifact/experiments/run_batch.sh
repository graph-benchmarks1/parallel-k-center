#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATCH_DIR="${SCRIPT_DIR}/batches"

usage() {
  cat <<'USAGE'
Usage:
  ./artifact/experiments/run_batch.sh <batch> [--dry-run]

Available:
  parameter_choices    Run P1-P4 (Appendix A.6.1-A.6.3)
  parallel_scaling     Run Figures A.5, A.6, 7.1, and 7.2
  full_sweep_synthetic  Run Figures A.7-A.10
  full_sweep_real       Run full real-world sweeps
USAGE
}

[[ $# -ge 1 ]] || { usage; exit 2; }
BATCH="$1"
shift

BATCH_FILE="${BATCH_DIR}/${BATCH}.txt"
[[ -r "${BATCH_FILE}" ]] || {
  echo "Unknown batch: ${BATCH}" >&2
  usage >&2
  exit 2
}

while IFS= read -r experiment; do
  [[ -n "${experiment}" ]] || continue
  [[ "${experiment}" == \#* ]] && continue
  "${SCRIPT_DIR}/run_experiment.sh" "${experiment}" "$@"
done < "${BATCH_FILE}"
