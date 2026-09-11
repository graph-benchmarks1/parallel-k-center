#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${REPO_ROOT}/artifact/bin"
CONFIG="${REPO_ROOT}/artifact/configs/smoke.env"
CHECK_OUTPUT="${REPO_ROOT}/artifact/scripts/check_output.sh"
RESULTS_DIR="${REPO_ROOT}/artifact-results/smoke"
DATA_DIR="${REPO_ROOT}/artifact/data/smoke"

[[ -r "${CONFIG}" ]] || { echo "Missing smoke configuration: ${CONFIG}" >&2; exit 2; }
[[ -x "${CHECK_OUTPUT}" ]] || { echo "Missing output checker: ${CHECK_OUTPUT}" >&2; exit 2; }
# shellcheck disable=SC1090
source "${CONFIG}"

required_binaries=(
  gonzalez
  approximategonzalez
  abboud
  thorupsimple
  simple-er-generator
  snap-converter
)

for binary in "${required_binaries[@]}"; do
  if [[ ! -x "${BIN_DIR}/${binary}" ]]; then
    echo "Missing binary: ${BIN_DIR}/${binary}" >&2
    echo "Run ./artifact/build.sh first (or ./artifact/run.sh smoke to build automatically)." >&2
    exit 2
  fi
done

# Smoke tests must never accidentally validate stale output from an earlier run.
rm -rf "${RESULTS_DIR}" "${DATA_DIR}"
mkdir -p "${RESULTS_DIR}/raw" "${DATA_DIR}"

UNWEIGHTED_EDGES="${DATA_DIR}/er_unweighted.edges"
WEIGHTED_EDGES="${DATA_DIR}/er_weighted.edges"
UNWEIGHTED_GRAPH="${DATA_DIR}/er_unweighted.adj"
WEIGHTED_GRAPH="${DATA_DIR}/er_weighted.adj"

echo "Generating deterministic smoke-test graph..."

"${BIN_DIR}/simple-er-generator" \
  "${SMOKE_N}" \
  "${SMOKE_M_UNDIRECTED}" \
  "${SMOKE_GRAPH_SEED}" \
  "${SMOKE_MAX_WEIGHT}" \
  "${UNWEIGHTED_EDGES}" \
  "${WEIGHTED_EDGES}"

echo "Converting unweighted edge list to GBBS format..."
"${BIN_DIR}/snap-converter" -s -i "${UNWEIGHTED_EDGES}" -o "${UNWEIGHTED_GRAPH}"

echo "Converting weighted edge list to GBBS format..."
"${BIN_DIR}/snap-converter" -s -w -i "${WEIGHTED_EDGES}" -o "${WEIGHTED_GRAPH}"

run_and_check() {
  local name="$1"
  local mode="$2"
  local graph_type="$3"
  local graph_file="$4"
  shift 4

  local log_file="${RESULTS_DIR}/raw/${name}_${graph_type}_${mode}.log"
  local mode_args=()

  if [[ "${mode}" == "singlecore" ]]; then
    mode_args=(-sc)
  fi

  echo
  echo "Running ${name} (${graph_type}, ${mode})..."

  # PIPESTATUS preserves the algorithm's exit status even though output is
  # simultaneously written to the terminal and the log via tee.
  set +e
  PARLAY_NUM_THREADS="${SMOKE_THREADS}" \
    "$@" "${mode_args[@]}" "${graph_file}" 2>&1 | tee "${log_file}"
  local algorithm_status=${PIPESTATUS[0]}
  set -e

  if [[ ${algorithm_status} -ne 0 ]]; then
    echo "Algorithm ${name} failed with exit code ${algorithm_status}. See ${log_file}." >&2
    exit "${algorithm_status}"
  fi

  "${CHECK_OUTPUT}" \
    "${log_file}" \
    "${name}" \
    "${mode}" \
    "${graph_type}" \
    "${SMOKE_THREADS}"
}

run_suite_for_graph() {
  local graph_type="$1"
  local graph_file="$2"

  for mode in parallel singlecore; do
    run_and_check \
      gonzalez "${mode}" "${graph_type}" "${graph_file}" \
      "${BIN_DIR}/gonzalez" \
      -s -rounds "${SMOKE_ROUNDS}" -k "${SMOKE_K}" \
      -delta "${SMOKE_DELTA}" -nb "${SMOKE_NUM_BUCKETS}" \
      -seed "${SMOKE_ALGO_SEED}"

    run_and_check \
      approximategonzalez "${mode}" "${graph_type}" "${graph_file}" \
      "${BIN_DIR}/approximategonzalez" \
      -s -rounds "${SMOKE_ROUNDS}" -k "${SMOKE_K}" \
      -epsilon "${SMOKE_EPSILON}" -delta "${SMOKE_DELTA}" \
      -nb "${SMOKE_NUM_BUCKETS}" -seed "${SMOKE_ALGO_SEED}"

    run_and_check \
      abboud "${mode}" "${graph_type}" "${graph_file}" \
      "${BIN_DIR}/abboud" \
      -s -rounds "${SMOKE_ROUNDS}" -k "${SMOKE_K}" \
      -delta "${SMOKE_DELTA}" -nb "${SMOKE_NUM_BUCKETS}" \
      -seed "${SMOKE_ALGO_SEED}"

    run_and_check \
      thorupsimple "${mode}" "${graph_type}" "${graph_file}" \
      "${BIN_DIR}/thorupsimple" \
      -s -rounds "${SMOKE_ROUNDS}" -k "${SMOKE_K}" \
      -delta "${SMOKE_DELTA}" -nb 128 -shrink 2 -lambda 1 \
      -rpp "${SMOKE_RPP}" -seed "${SMOKE_ALGO_SEED}"
  done
}

# Both files are generated intentionally: this verifies the format dispatcher
# and the algorithm implementations on both input types used by the artifact.
run_suite_for_graph unweighted "${UNWEIGHTED_GRAPH}"
run_suite_for_graph weighted "${WEIGHTED_GRAPH}"

echo
echo "Smoke test passed for all four algorithms."
echo "Verified graph types: unweighted, weighted"
echo "Verified execution modes: parallel (${SMOKE_THREADS} threads), single-core"
echo "Results written to: ${RESULTS_DIR}"

