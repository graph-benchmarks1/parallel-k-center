#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

[[ $# -ge 1 ]] || {
  echo "Usage: ./artifact/run.sh aggregate <experiment-id> [--hierarchical auto|none|graph-seed]" >&2
  exit 2
}

EXPERIMENT_ID="$1"
shift

RESULTS_ROOT="${RESULTS_DIR:-${REPO_ROOT}/artifact-results/experiments/${EXPERIMENT_ID}}"
INPUT="${RESULTS_ROOT}/runs.tsv"
OUTPUT_DIR="${RESULTS_ROOT}/summary"

exec python3 "${REPO_ROOT}/artifact/scripts/aggregate_results.py" \
  --input "${INPUT}" \
  --output-dir "${OUTPUT_DIR}" \
  "$@"
