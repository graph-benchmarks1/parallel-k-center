#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${REPO_ROOT}/artifact/bin"
CONFIG="${REPO_ROOT}/artifact/configs/smoke.env"
RESULTS_DIR="${REPO_ROOT}/artifact-results/smoke"
DATA_DIR="${REPO_ROOT}/artifact/data/smoke"

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
    echo "Run ./artifact/build.sh first." >&2
    exit 2
  fi
done

mkdir -p "${RESULTS_DIR}/raw"
mkdir -p "${DATA_DIR}"

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

"${BIN_DIR}/snap-converter" \
  -s \
  -i "${UNWEIGHTED_EDGES}" \
  -o "${UNWEIGHTED_GRAPH}"

echo "Converting weighted edge list to GBBS format..."

"${BIN_DIR}/snap-converter" \
  -s \
  -w \
  -i "${WEIGHTED_EDGES}" \
  -o "${WEIGHTED_GRAPH}"

run_and_check() {
  local name="$1"
  local mode="$2"
  shift 2

  local log_file="${RESULTS_DIR}/raw/${name}_${mode}.log"
  local mode_args=()

  if [[ "${mode}" == "singlecore" ]]; then
    mode_args=(-sc)
  fi

  echo
  echo "Running ${name} (${mode})..."

  PARLAY_NUM_THREADS="${SMOKE_THREADS}" \
  "$@" \
    "${mode_args[@]}" \
    "${WEIGHTED_GRAPH}" \
    | tee "${log_file}"

  if [[ "${mode}" == "singlecore" ]]; then
    grep -q '^### SSSP Mode: single-core$' "${log_file}"
    grep -q '^### Threads: 1$' "${log_file}"
  else
    grep -q '^### SSSP Mode: parallel$' "${log_file}"
    grep -q "^### Threads: ${SMOKE_THREADS}$" "${log_file}"
  fi

  grep -q '^### Application:' "${log_file}"
  grep -q '^### Graph Type: weighted$' "${log_file}"
  grep -q '^### n:' "${log_file}"
  grep -q '^### m:' "${log_file}"
  grep -q '^num_centers =' "${log_file}"
  grep -q '^max_dist_to_centers =' "${log_file}"
  grep -q '^unreachable_vertices =' "${log_file}"
  grep -q '^### Running Time:' "${log_file}"
}

for mode in parallel singlecore; do
  run_and_check \
    gonzalez \
    "${mode}" \
    "${BIN_DIR}/gonzalez" \
    -s \
    -rounds "${SMOKE_ROUNDS}" \
    -k "${SMOKE_K}" \
    -delta "${SMOKE_DELTA}" \
    -nb "${SMOKE_NUM_BUCKETS}" \
    -seed "${SMOKE_ALGO_SEED}"

  run_and_check \
    approximategonzalez \
    "${mode}" \
    "${BIN_DIR}/approximategonzalez" \
    -s \
    -rounds "${SMOKE_ROUNDS}" \
    -k "${SMOKE_K}" \
    -epsilon "${SMOKE_EPSILON}" \
    -delta "${SMOKE_DELTA}" \
    -nb "${SMOKE_NUM_BUCKETS}" \
    -seed "${SMOKE_ALGO_SEED}"

  run_and_check \
    abboud \
    "${mode}" \
    "${BIN_DIR}/abboud" \
    -s \
    -rounds "${SMOKE_ROUNDS}" \
    -k "${SMOKE_K}" \
    -delta "${SMOKE_DELTA}" \
    -nb "${SMOKE_NUM_BUCKETS}" \
    -seed "${SMOKE_ALGO_SEED}"

  run_and_check \
    thorupsimple \
    "${mode}" \
    "${BIN_DIR}/thorupsimple" \
    -s \
    -rounds "${SMOKE_ROUNDS}" \
    -k "${SMOKE_K}" \
    -delta "${SMOKE_DELTA}" \
    -nb 128 \
    -shrink 2 \
    -lambda 1 \
    -rpp "${SMOKE_RPP}" \
    -seed "${SMOKE_ALGO_SEED}"
done

for mode in parallel singlecore; do
  grep -q '^### Final radius (r\*):' \
    "${RESULTS_DIR}/raw/abboud_${mode}.log"

  grep -q '^feasible = true$' \
    "${RESULTS_DIR}/raw/thorupsimple_${mode}.log"

  grep -q '^radius =' \
    "${RESULTS_DIR}/raw/thorupsimple_${mode}.log"

  grep -q '^rounds =' \
    "${RESULTS_DIR}/raw/thorupsimple_${mode}.log"

  grep -q '^phases =' \
    "${RESULTS_DIR}/raw/thorupsimple_${mode}.log"
done

echo
echo "Smoke test passed for all algorithms."
echo "Generated graph: ${WEIGHTED_GRAPH}"
echo "Results written to: ${RESULTS_DIR}"
