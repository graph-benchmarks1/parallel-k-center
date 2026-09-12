#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

[[ $# -eq 1 ]] || {
  echo "Usage: ./artifact/run.sh plot <experiment-id>" >&2
  exit 2
}

EXPERIMENT_ID="$1"
RESULTS_ROOT="${RESULTS_DIR:-${REPO_ROOT}/artifact-results/experiments/${EXPERIMENT_ID}}"
SUMMARY_DIR="${RESULTS_ROOT}/summary"
OUTPUT_DIR="${SUMMARY_DIR}/figures"

case "${EXPERIMENT_ID}" in
  p1_delta|p4_thorup_rpp)
    INPUT="${SUMMARY_DIR}/aggregated.tsv"
    exec python3 "${REPO_ROOT}/artifact/scripts/plot_parameter_studies.py" \
      --experiment-id "${EXPERIMENT_ID}" \
      --input "${INPUT}" \
      --output-dir "${OUTPUT_DIR}"
    ;;
  p2_approx_epsilon_synthetic|p3_approx_epsilon_real)
    INPUT="${SUMMARY_DIR}/paper_results.tsv"
    exec python3 "${REPO_ROOT}/artifact/scripts/plot_parameter_studies.py" \
      --experiment-id "${EXPERIMENT_ID}" \
      --input "${INPUT}" \
      --output-dir "${OUTPUT_DIR}"
    ;;
  p5_parallel_small_synthetic|\
  p6_parallel_large_synthetic|\
  p7_parallel_social|\
  p8_parallel_road)
    INPUT="${SUMMARY_DIR}/aggregated.tsv"
    exec python3 "${REPO_ROOT}/artifact/scripts/plot_parallel_scaling.py" \
      --experiment-id "${EXPERIMENT_ID}" \
      --input "${INPUT}" \
      --output-dir "${OUTPUT_DIR}"
    ;;
  p9_full_sweep_small_synthetic|\
  p10_full_sweep_large_synthetic|\
  p11_full_sweep_social|\
  p12_full_sweep_roads|\
  p13_full_sweep_ratings)
    INPUT="${SUMMARY_DIR}/paper_results.tsv"
    exec python3 "${REPO_ROOT}/artifact/scripts/plot_full_sweep.py" \
      --experiment-id "${EXPERIMENT_ID}" \
      --input "${INPUT}" \
      --output-dir "${OUTPUT_DIR}"
    ;;
  *)
    echo "ERROR: plotting is not yet implemented for ${EXPERIMENT_ID}" >&2
    exit 2
    ;;
esac
