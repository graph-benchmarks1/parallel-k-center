#!/usr/bin/env bash
set -euo pipefail

# Prepare real-world datasets used by the ALENEX artifact.
#
# Current supported datasets:
#   dblp
#   youtube
#
# The script is intentionally dataset-oriented so additional sources can be
# added incrementally and tested independently.
#
# Common pipeline for edge-list datasets:
#
#   download raw archive
#       -> decompress/extract
#       -> source-specific normalization if needed
#       -> snap-converter
#       -> clean-csr-graph
#       -> validate expected post-cleanup statistics
#       -> install into inputs/
#
# DBLP source:
#   https://snap.stanford.edu/data/com-DBLP.html
# Raw graph:
#   https://snap.stanford.edu/data/bigdata/communities/com-dblp.ungraph.txt.gz
#
# Expected post-cleanup graph:
#   n = 317080
#   undirected m = 1049866
#   GBBS symmetric adjacency entries = 2099732

usage() {
  cat <<'EOF'
Usage:
  ./artifact/scripts/prepare_real_datasets.sh dblp [options]
  ./artifact/scripts/prepare_real_datasets.sh youtube [options]

Options:
  --force             Redownload/reprocess even if the final graph exists.
  --keep-intermediate Keep decompressed and pre-cleanup intermediate files.
  --input-dir PATH    Override repository-root inputs/ directory.
  --cache-dir PATH    Override artifact/data/real-data-cache/.
  --clean-memory-mb N Memory budget passed to clean-csr-graph (default: 512).
  --clean-shards N    Shard count passed to clean-csr-graph (default: 128).
  -h, --help          Show this help.

Examples:
  ./artifact/scripts/prepare_real_datasets.sh dblp
  ./artifact/scripts/prepare_real_datasets.sh youtube
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

DATASET="$1"
shift

case "${DATASET}" in
  dblp|youtube)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unsupported dataset: ${DATASET}" >&2
    echo "Currently supported: dblp, youtube" >&2
    exit 2
    ;;
esac

FORCE=0
KEEP_INTERMEDIATE=0
INPUT_DIR_OVERRIDE=""
CACHE_DIR_OVERRIDE=""
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
    --cache-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --cache-dir requires a path." >&2; exit 2; }
      CACHE_DIR_OVERRIDE="$2"
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
else
  INPUT_DIR="${REPO_ROOT}/inputs"
fi

if [[ -n "${CACHE_DIR_OVERRIDE}" ]]; then
  CACHE_DIR="$(realpath -m "${CACHE_DIR_OVERRIDE}")"
else
  CACHE_DIR="${REPO_ROOT}/artifact/data/real-data-cache"
fi

CONVERTER="${BIN_DIR}/snap-converter"
CLEANER="${BIN_DIR}/clean-csr-graph"

for binary in "${CONVERTER}" "${CLEANER}"; do
  if [[ ! -x "${binary}" ]]; then
    echo "ERROR: missing executable: ${binary}" >&2
    echo "Run ./artifact/build.sh first." >&2
    exit 2
  fi
done

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required to download real-world datasets." >&2
  exit 2
fi

if ! command -v gzip >/dev/null 2>&1; then
  echo "ERROR: gzip is required to decompress SNAP datasets." >&2
  exit 2
fi

mkdir -p "${CACHE_DIR}"

validate_symmetric_unweighted_graph() {
  local graph="$1"
  local expected_n="$2"
  local expected_undirected_m="$3"

  if [[ ! -s "${graph}" ]]; then
    echo "ERROR: expected graph does not exist or is empty: ${graph}" >&2
    return 1
  fi

  local header
  local actual_n
  local actual_directed_m
  local expected_directed_m=$((2 * expected_undirected_m))

  header="$(sed -n '1p' "${graph}")"
  actual_n="$(sed -n '2p' "${graph}")"
  actual_directed_m="$(sed -n '3p' "${graph}")"

  if [[ "${header}" != "AdjacencyGraph" ]]; then
    echo "ERROR: expected AdjacencyGraph header, got: ${header}" >&2
    return 1
  fi

  if [[ "${actual_n}" != "${expected_n}" ]]; then
    echo "ERROR: vertex-count mismatch." >&2
    echo "  expected: ${expected_n}" >&2
    echo "  actual:   ${actual_n}" >&2
    return 1
  fi

  if [[ "${actual_directed_m}" != "${expected_directed_m}" ]]; then
    echo "ERROR: edge-count mismatch." >&2
    echo "  expected undirected edges: ${expected_undirected_m}" >&2
    echo "  expected adjacency entries: ${expected_directed_m}" >&2
    echo "  actual adjacency entries:   ${actual_directed_m}" >&2
    return 1
  fi

  echo
  echo "[validate] PASS"
  echo "  header:             ${header}"
  echo "  vertices:           ${actual_n}"
  echo "  undirected edges:   ${expected_undirected_m}"
  echo "  adjacency entries:  ${actual_directed_m}"
}


prepare_snap_unweighted() {
  local dataset_name="$1"
  local display_name="$2"
  local source_url="$3"
  local archive_name="$4"
  local final_name="$5"
  local expected_n="$6"
  local expected_undirected_m="$7"

  local dataset_dir="${CACHE_DIR}/${dataset_name}"
  local tmp_dir="${dataset_dir}/tmp"

  local archive="${dataset_dir}/${archive_name}"
  local edge_list="${tmp_dir}/${archive_name%.gz}"
  local converted="${tmp_dir}/${dataset_name}.preclean.adj"
  local cleaned="${tmp_dir}/${dataset_name}.clean.adj"

  local output_dir="${INPUT_DIR}/Snap_unweighted"
  local final_graph="${output_dir}/${final_name}"

  mkdir -p "${dataset_dir}" "${tmp_dir}" "${output_dir}"

  echo "Real-data preparation: ${display_name}"
  echo "  source:       SNAP"
  echo "  URL:          ${source_url}"
  echo "  final graph:  ${final_graph}"
  echo "  expected n:   ${expected_n}"
  echo "  expected m:   ${expected_undirected_m} undirected edges"
  echo

  if [[ "${FORCE}" -eq 0 && -s "${final_graph}" ]]; then
    echo "[existing] final graph already exists; validating it."
    if validate_symmetric_unweighted_graph \
        "${final_graph}" \
        "${expected_n}" \
        "${expected_undirected_m}"; then
      echo
      echo "${display_name} is already prepared correctly."
      return 0
    fi

    echo
    echo "Existing graph failed validation; rebuilding it." >&2
  fi

  if [[ "${FORCE}" -eq 1 ]]; then
    rm -f "${archive}"
  fi

  rm -f "${edge_list}" "${converted}" "${cleaned}"

  if [[ ! -s "${archive}" ]]; then
    echo "[download] ${source_url}"
    local partial_archive="${archive}.part"
    rm -f "${partial_archive}"

    curl \
      --fail \
      --location \
      --retry 3 \
      --retry-delay 2 \
      --output "${partial_archive}" \
      "${source_url}"

    if [[ ! -s "${partial_archive}" ]]; then
      echo "ERROR: download produced an empty file." >&2
      exit 1
    fi

    mv -f "${partial_archive}" "${archive}"
  else
    echo "[download] using cached archive: ${archive}"
  fi

  echo
  echo "[decompress] ${archive}"
  gzip -dc "${archive}" > "${edge_list}"

  if [[ ! -s "${edge_list}" ]]; then
    echo "ERROR: decompressed edge list is empty." >&2
    exit 1
  fi

  echo
  echo "[convert] SNAP edge list -> temporary symmetric GBBS graph"
  "${CONVERTER}" \
    -s \
    -i "${edge_list}" \
    -o "${converted}"

  if [[ ! -s "${converted}" ]]; then
    echo "ERROR: snap-converter produced an empty graph." >&2
    exit 1
  fi

  echo
  echo "[clean] common graph cleanup"
  "${CLEANER}" \
    "${converted}" \
    "${cleaned}" \
    --memory-mb "${CLEAN_MEMORY_MB}" \
    --shards "${CLEAN_SHARDS}"

  echo
  validate_symmetric_unweighted_graph \
    "${cleaned}" \
    "${expected_n}" \
    "${expected_undirected_m}"

  mv -f "${cleaned}" "${final_graph}"

  if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
    rm -f "${edge_list}" "${converted}"
    rmdir "${tmp_dir}" 2>/dev/null || true
  fi

  echo
  echo "${display_name} preparation complete."
  echo "  final graph: ${final_graph}"
  echo "  cached raw:  ${archive}"
}

prepare_dblp() {
  prepare_snap_unweighted \
    "dblp" \
    "DBLP" \
    "https://snap.stanford.edu/data/bigdata/communities/com-dblp.ungraph.txt.gz" \
    "com-dblp.ungraph.txt.gz" \
    "com-dblp.adj" \
    "317080" \
    "1049866"
}

prepare_youtube() {
  prepare_snap_unweighted \
    "youtube" \
    "YouTube" \
    "https://snap.stanford.edu/data/bigdata/communities/com-youtube.ungraph.txt.gz" \
    "com-youtube.ungraph.txt.gz" \
    "com-youtube.adj" \
    "1134890" \
    "2987624"
}

case "${DATASET}" in
  dblp)
    prepare_dblp
    ;;
  youtube)
    prepare_youtube
    ;;
esac

