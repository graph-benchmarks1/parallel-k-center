#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

[[ $# -eq 1 ]] || {
  echo "Usage: ./artifact/run.sh derive <experiment-id>" >&2
  exit 2
}

EXPERIMENT_ID="$1"
RESULTS_ROOT="${RESULTS_DIR:-${REPO_ROOT}/artifact-results/experiments/${EXPERIMENT_ID}}"
SUMMARY_DIR="${RESULTS_ROOT}/summary"
INPUT="${SUMMARY_DIR}/aggregated.tsv"
OUTPUT="${SUMMARY_DIR}/paper_results.tsv"

exec python3 "${REPO_ROOT}/artifact/scripts/derive_paper_results.py" \
  --input "${INPUT}" \
  --output "${OUTPUT}"
