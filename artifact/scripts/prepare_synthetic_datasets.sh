#!/usr/bin/env bash
set -euo pipefail

# Prepare the synthetic Erdős-Rényi datasets used in the paper.
#
# Official output layout:
#
# inputs/
# ├── Snap_unweighted/
# │   ├── ER_small/
# │   │   ├── er_n100000_d2_seed0.adj
# │   │   └── ...
# │   └── ER_large/
# │       ├── er_n10000000_d2_seed0.adj
# │       └── ...
# └── Snap_weighted/
#     ├── ER_small/
#     │   ├── er_n100000_d2_seed0_w.adj
#     │   └── ...
#     └── ER_large/
#         ├── er_n10000000_d2_seed0_w.adj
#         └── ...
#
# Pipeline:
#   simple-er-generator
#       -> raw edge lists
#       -> snap-converter
#       -> temporary GBBS graph
#       -> clean-csr-graph
#       -> final experiment-ready .adj graph
#
# Profiles:
#
#   test
#       One tiny pair (weighted + unweighted), n=1000, d=2, seed=0.
#       By default this goes to artifact/data/synthetic-prep-test/ rather
#       than inputs/, so it does not pollute the official dataset tree.
#
#   light_synthetic
#       All 120 small graphs:
#       n=100,000; d in {2,4,8,16,32,64}; seeds 0..9;
#       weighted + unweighted.
#
#   full_synthetic
#       light_synthetic plus all 12 large graphs:
#       n=10,000,000; d in {2,4,8,16,32,64}; seed 0;
#       weighted + unweighted.
#
# The nominal n and m=n*d are GENERATION parameters. After common cleanup,
# final n may be smaller because isolated vertices are removed. The generator
# itself creates distinct non-self-loop undirected edges, so final undirected
# edge count is normally unchanged by cleanup.

usage() {
  cat <<'EOF'
Usage:
  ./artifact/scripts/prepare_synthetic_datasets.sh test [options]
  ./artifact/scripts/prepare_synthetic_datasets.sh light_synthetic [options]
  ./artifact/scripts/prepare_synthetic_datasets.sh full_synthetic [options]

Aliases:
  small = light_synthetic
  full  = full_synthetic

Options:
  --force             Regenerate outputs even if final .adj files already exist.
  --keep-intermediate Keep raw .edges and pre-cleanup .adj files.
  --input-dir PATH    Override the output root.
                      For official profiles the default is <repo>/inputs.
                      For test the default is
                      <repo>/artifact/data/synthetic-prep-test.
  --clean-memory-mb N Memory budget passed to clean-csr-graph (default: 512).
  --clean-shards N    Shard count passed to clean-csr-graph (default: 128).
  -h, --help          Show this help.

Examples:
  ./artifact/scripts/prepare_synthetic_datasets.sh test
  ./artifact/scripts/prepare_synthetic_datasets.sh light_synthetic
  ./artifact/scripts/prepare_synthetic_datasets.sh full_synthetic
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

PROFILE="$1"
shift

case "${PROFILE}" in
  test)
    ;;
  light_synthetic|small)
    PROFILE="light_synthetic"
    ;;
  full_synthetic|full)
    PROFILE="full_synthetic"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown profile: ${PROFILE}" >&2
    usage >&2
    exit 2
    ;;
esac

FORCE=0
KEEP_INTERMEDIATE=0
INPUT_DIR_OVERRIDE=""
CLEAN_MEMORY_MB=512
CLEAN_SHARDS=128

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --keep-intermediate)
      KEEP_INTERMEDIATE=1
      shift
      ;;
    --input-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --input-dir requires a path." >&2; exit 2; }
      INPUT_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --clean-memory-mb)
      [[ $# -ge 2 ]] || { echo "ERROR: --clean-memory-mb requires a value." >&2; exit 2; }
      CLEAN_MEMORY_MB="$2"
      shift 2
      ;;
    --clean-shards)
      [[ $# -ge 2 ]] || { echo "ERROR: --clean-shards requires a value." >&2; exit 2; }
      CLEAN_SHARDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_DIR="${REPO_ROOT}/artifact/bin"

if [[ -n "${INPUT_DIR_OVERRIDE}" ]]; then
  INPUT_DIR="$(realpath -m "${INPUT_DIR_OVERRIDE}")"
elif [[ "${PROFILE}" == "test" ]]; then
  INPUT_DIR="${REPO_ROOT}/artifact/data/synthetic-prep-test"
else
  INPUT_DIR="${REPO_ROOT}/inputs"
fi

GENERATOR="${BIN_DIR}/simple-er-generator"
CONVERTER="${BIN_DIR}/snap-converter"
CLEANER="${BIN_DIR}/clean-csr-graph"

for binary in "${GENERATOR}" "${CONVERTER}" "${CLEANER}"; do
  if [[ ! -x "${binary}" ]]; then
    echo "ERROR: missing executable: ${binary}" >&2
    echo "Run ./artifact/build.sh first." >&2
    exit 2
  fi
done

# Fixed official paper parameters.
SMALL_N=100000
LARGE_N=10000000
MAX_WEIGHT=10000
DENSITIES=(2 4 8 16 32 64)
SMALL_SEEDS=(0 1 2 3 4 5 6 7 8 9)
LARGE_SEEDS=(0)

# Tiny end-to-end validation profile.
TEST_N=1000
TEST_DENSITIES=(2)
TEST_SEEDS=(0)

UNWEIGHTED_SMALL_DIR="${INPUT_DIR}/Snap_unweighted/ER_small"
UNWEIGHTED_LARGE_DIR="${INPUT_DIR}/Snap_unweighted/ER_large"
WEIGHTED_SMALL_DIR="${INPUT_DIR}/Snap_weighted/ER_small"
WEIGHTED_LARGE_DIR="${INPUT_DIR}/Snap_weighted/ER_large"

mkdir -p \
  "${UNWEIGHTED_SMALL_DIR}" \
  "${UNWEIGHTED_LARGE_DIR}" \
  "${WEIGHTED_SMALL_DIR}" \
  "${WEIGHTED_LARGE_DIR}"

TMP_DIR="${INPUT_DIR}/.synthetic-preparation-tmp"
mkdir -p "${TMP_DIR}"

CURRENT_FILES=()

cleanup_current_files() {
  if [[ "${KEEP_INTERMEDIATE}" -eq 0 && ${#CURRENT_FILES[@]} -gt 0 ]]; then
    rm -f "${CURRENT_FILES[@]}"
  fi
}

trap cleanup_current_files EXIT INT TERM

generated_pairs=0
skipped_pairs=0

prepare_pair() {
  local size_label="$1"
  local n="$2"
  local density="$3"
  local seed="$4"
  local unweighted_dir="$5"
  local weighted_dir="$6"

  local m_undirected=$((n * density))
  local base="er_n${n}_d${density}_seed${seed}"

  local final_unweighted="${unweighted_dir}/${base}.adj"
  local final_weighted="${weighted_dir}/${base}_w.adj"

  if [[ "${FORCE}" -eq 0 &&
        -s "${final_unweighted}" &&
        -s "${final_weighted}" ]]; then
    echo "[skip] ${size_label}: n=${n} d=${density} seed=${seed}"
    ((skipped_pairs += 1))
    return
  fi

  local raw_unweighted="${TMP_DIR}/${base}.edges"
  local raw_weighted="${TMP_DIR}/${base}_w.edges"
  local converted_unweighted="${TMP_DIR}/${base}.preclean.adj"
  local converted_weighted="${TMP_DIR}/${base}_w.preclean.adj"
  local cleaned_unweighted="${TMP_DIR}/${base}.clean.adj"
  local cleaned_weighted="${TMP_DIR}/${base}_w.clean.adj"

  CURRENT_FILES=(
    "${raw_unweighted}"
    "${raw_weighted}"
    "${converted_unweighted}"
    "${converted_weighted}"
    "${cleaned_unweighted}"
    "${cleaned_weighted}"
  )

  rm -f "${CURRENT_FILES[@]}"

  echo
  echo "============================================================"
  echo "[generate] ${size_label}: n=${n} d=${density} seed=${seed}"
  echo "  nominal undirected edges: ${m_undirected}"
  echo "  final unweighted:         ${final_unweighted}"
  echo "  final weighted:           ${final_weighted}"
  echo "============================================================"

  "${GENERATOR}" \
    "${n}" \
    "${m_undirected}" \
    "${seed}" \
    "${MAX_WEIGHT}" \
    "${raw_unweighted}" \
    "${raw_weighted}"

  echo
  echo "[convert] unweighted edge list -> temporary GBBS graph"
  "${CONVERTER}" \
    -s \
    -i "${raw_unweighted}" \
    -o "${converted_unweighted}"

  echo
  echo "[convert] weighted edge list -> temporary GBBS graph"
  "${CONVERTER}" \
    -s \
    -w \
    -i "${raw_weighted}" \
    -o "${converted_weighted}"

  echo
  echo "[clean] unweighted graph"
  "${CLEANER}" \
    "${converted_unweighted}" \
    "${cleaned_unweighted}" \
    --memory-mb "${CLEAN_MEMORY_MB}" \
    --shards "${CLEAN_SHARDS}"

  echo
  echo "[clean] weighted graph"
  "${CLEANER}" \
    "${converted_weighted}" \
    "${cleaned_weighted}" \
    --memory-mb "${CLEAN_MEMORY_MB}" \
    --shards "${CLEAN_SHARDS}"

  if [[ ! -s "${cleaned_unweighted}" || ! -s "${cleaned_weighted}" ]]; then
    echo "ERROR: cleaner produced an empty output for ${base}." >&2
    exit 1
  fi

  # Final files appear in inputs/ only after the entire pipeline succeeds.
  mv -f "${cleaned_unweighted}" "${final_unweighted}"
  mv -f "${cleaned_weighted}" "${final_weighted}"

  if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
    rm -f \
      "${raw_unweighted}" \
      "${raw_weighted}" \
      "${converted_unweighted}" \
      "${converted_weighted}"
  fi

  CURRENT_FILES=()
  ((generated_pairs += 1))

  echo
  echo "[done] ${base}"
}

echo "Synthetic dataset preparation"
echo "  profile:          ${PROFILE}"
echo "  output root:      ${INPUT_DIR}"
echo "  max weight:       ${MAX_WEIGHT}"
echo "  cleaner memory:   ${CLEAN_MEMORY_MB} MB"
echo "  cleaner shards:   ${CLEAN_SHARDS}"
echo

if [[ "${PROFILE}" == "test" ]]; then
  echo "Running tiny end-to-end test profile..."
  for density in "${TEST_DENSITIES[@]}"; do
    for seed in "${TEST_SEEDS[@]}"; do
      prepare_pair \
        "test" \
        "${TEST_N}" \
        "${density}" \
        "${seed}" \
        "${UNWEIGHTED_SMALL_DIR}" \
        "${WEIGHTED_SMALL_DIR}"
    done
  done

elif [[ "${PROFILE}" == "light_synthetic" ]]; then
  echo "Preparing all small synthetic graphs..."
  for density in "${DENSITIES[@]}"; do
    for seed in "${SMALL_SEEDS[@]}"; do
      prepare_pair \
        "small" \
        "${SMALL_N}" \
        "${density}" \
        "${seed}" \
        "${UNWEIGHTED_SMALL_DIR}" \
        "${WEIGHTED_SMALL_DIR}"
    done
  done

elif [[ "${PROFILE}" == "full_synthetic" ]]; then
  echo "Preparing all small synthetic graphs..."
  for density in "${DENSITIES[@]}"; do
    for seed in "${SMALL_SEEDS[@]}"; do
      prepare_pair \
        "small" \
        "${SMALL_N}" \
        "${density}" \
        "${seed}" \
        "${UNWEIGHTED_SMALL_DIR}" \
        "${WEIGHTED_SMALL_DIR}"
    done
  done

  echo
  echo "Preparing all large synthetic graphs..."
  for density in "${DENSITIES[@]}"; do
    for seed in "${LARGE_SEEDS[@]}"; do
      prepare_pair \
        "large" \
        "${LARGE_N}" \
        "${density}" \
        "${seed}" \
        "${UNWEIGHTED_LARGE_DIR}" \
        "${WEIGHTED_LARGE_DIR}"
    done
  done
fi

if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
  rmdir "${TMP_DIR}" 2>/dev/null || true
fi

echo
echo "Synthetic dataset preparation complete."
echo "  generated topology pairs: ${generated_pairs}"
echo "  skipped topology pairs:   ${skipped_pairs}"

case "${PROFILE}" in
  test)
    echo "  expected final graphs:     2"
    ;;
  light_synthetic)
    echo "  expected final graphs:     120"
    ;;
  full_synthetic)
    echo "  expected final graphs:     132"
    ;;
esac

echo
echo "Final output root:"
echo "  ${INPUT_DIR}"

