#!/usr/bin/env bash
set -euo pipefail

# Prepare real-world datasets used by the ALENEX artifact.
#
# Current supported datasets:
#   dblp
#   youtube
#   livejournal
#   orkut
#   twitter
#   friendster
#   usa-central
#   usa-full
#   libimseti
#   movielens
#   yahoo-song

usage() {
  cat <<'EOF'
Usage:
  ./artifact/scripts/prepare_real_datasets.sh <dataset> [options]

Datasets:
  dblp
  youtube
  livejournal
  orkut
  twitter
  friendster
  usa-central
  usa-full
  libimseti
  movielens
  yahoo-song

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
  ./artifact/scripts/prepare_real_datasets.sh livejournal
  ./artifact/scripts/prepare_real_datasets.sh orkut
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

DATASET="$1"
shift

case "${DATASET}" in
  dblp|youtube|livejournal|orkut|twitter|friendster|usa-central|usa-full|libimseti|movielens|yahoo-song)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unsupported dataset: ${DATASET}" >&2
    echo "Currently supported: dblp, youtube, livejournal, orkut, twitter, friendster, usa-central, usa-full, libimseti, movielens, yahoo-song" >&2
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
RATING_TRANSFORMER="${REPO_ROOT}/scripts/rating_weights_to_distances.py"

for binary in "${CONVERTER}" "${CLEANER}"; do
  if [[ ! -x "${binary}" ]]; then
    echo "ERROR: missing executable: ${binary}" >&2
    echo "Run ./artifact/build.sh first." >&2
    exit 2
  fi
done

if [[ ! -f "${RATING_TRANSFORMER}" ]]; then
  echo "ERROR: missing rating transformer: ${RATING_TRANSFORMER}" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required to download real-world datasets." >&2
  exit 2
fi

if ! command -v gzip >/dev/null 2>&1; then
  echo "ERROR: gzip is required to decompress SNAP datasets." >&2
  exit 2
fi

if ! command -v awk >/dev/null 2>&1; then
  echo "ERROR: awk is required to normalize DIMACS road-network files." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for rating-to-distance preprocessing." >&2
  exit 2
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "ERROR: tar is required to extract KONECT rating datasets." >&2
  exit 2
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "ERROR: unzip is required to extract MovieLens." >&2
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



validate_symmetric_weighted_graph() {
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

  if [[ "${header}" != "WeightedAdjacencyGraph" ]]; then
    echo "ERROR: expected WeightedAdjacencyGraph header, got: ${header}" >&2
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
    echo "  expected undirected edges:  ${expected_undirected_m}" >&2
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

prepare_livejournal() {
  prepare_snap_unweighted \
    "livejournal" \
    "LiveJournal" \
    "https://snap.stanford.edu/data/bigdata/communities/com-lj.ungraph.txt.gz" \
    "com-lj.ungraph.txt.gz" \
    "com-lj.adj" \
    "3997962" \
    "34681189"
}

prepare_orkut() {
  prepare_snap_unweighted \
    "orkut" \
    "Orkut" \
    "https://snap.stanford.edu/data/bigdata/communities/com-orkut.ungraph.txt.gz" \
    "com-orkut.ungraph.txt.gz" \
    "com-orkut.adj" \
    "3072441" \
    "117185083"
}

prepare_friendster() {
  prepare_snap_unweighted \
    "friendster" \
    "Friendster" \
    "https://snap.stanford.edu/data/bigdata/communities/com-friendster.ungraph.txt.gz" \
    "com-friendster.ungraph.txt.gz" \
    "com-friendster.adj" \
    "65608366" \
    "1806067135"
}

prepare_twitter() {
  echo "NOTE: SNAP twitter-2010 is a directed follower graph."
  echo "      The artifact symmetrizes it because the k-center implementation"
  echo "      operates on undirected graphs."
  echo "      The expected post-symmetrization count below should be checked"
  echo "      against the original experiment input before a full AE rebuild."
  echo

  prepare_snap_unweighted \
    "twitter" \
    "Twitter" \
    "https://snap.stanford.edu/data/twitter-2010.txt.gz" \
    "twitter-2010.txt.gz" \
    "twitter-2010.adj" \
    "41652230" \
    "1202513046"
}

prepare_dimacs_road() {
  local dataset_name="$1"
  local display_name="$2"
  local source_url="$3"
  local archive_name="$4"
  local raw_name="$5"
  local final_name="$6"
  local expected_n="$7"
  local expected_undirected_m="$8"

  local dataset_dir="${CACHE_DIR}/${dataset_name}"
  local tmp_dir="${dataset_dir}/tmp"

  local archive="${dataset_dir}/${archive_name}"
  local raw_gr="${tmp_dir}/${raw_name}"
  local normalized="${tmp_dir}/${dataset_name}.weighted.tsv"
  local converted="${tmp_dir}/${dataset_name}.preclean.adj"
  local cleaned="${tmp_dir}/${dataset_name}.clean.adj"

  local output_dir="${INPUT_DIR}/RoadNetworks_weighted"
  local final_graph="${output_dir}/${final_name}"

  mkdir -p "${dataset_dir}" "${tmp_dir}" "${output_dir}"

  echo "Real-data preparation: ${display_name}"
  echo "  source:       9th DIMACS Implementation Challenge"
  echo "  weights:      physical road distances"
  echo "  URL:          ${source_url}"
  echo "  final graph:  ${final_graph}"
  echo "  expected n:   ${expected_n}"
  echo "  expected m:   ${expected_undirected_m} undirected edges"
  echo

  if [[ "${FORCE}" -eq 0 && -s "${final_graph}" ]]; then
    echo "[existing] final graph already exists; validating it."
    if validate_symmetric_weighted_graph \
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

  rm -f "${raw_gr}" "${normalized}" "${converted}" "${cleaned}"

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
      echo "ERROR: road-network download produced an empty file." >&2
      exit 1
    fi

    mv -f "${partial_archive}" "${archive}"
  else
    echo "[download] using cached archive: ${archive}"
  fi

  echo
  echo "[decompress] ${archive}"
  gzip -dc "${archive}" > "${raw_gr}"

  if [[ ! -s "${raw_gr}" ]]; then
    echo "ERROR: decompressed DIMACS graph is empty." >&2
    exit 1
  fi

  echo
  echo "[normalize] DIMACS 'a U V W' arcs -> weighted edge list"
  # DIMACS node IDs are 1..n. Shift them to 0..n-1 for GBBS.
  # Keep every directed arc here; -s below interprets each as an undirected
  # pair, and clean-csr-graph subsequently collapses reciprocal/parallel arcs
  # while retaining the minimum weight for each undirected pair.
  awk '
    $1 == "a" {
      if ($2 < 1 || $3 < 1) {
        print "ERROR: invalid DIMACS endpoint on line " NR > "/dev/stderr";
        exit 3;
      }
      print ($2 - 1), ($3 - 1), $4;
    }
  ' "${raw_gr}" > "${normalized}"

  if [[ ! -s "${normalized}" ]]; then
    echo "ERROR: no DIMACS arc records were found." >&2
    exit 1
  fi

  echo
  echo "[convert] weighted edge list -> temporary symmetric GBBS graph"
  "${CONVERTER}" \
    -s \
    -w \
    -i "${normalized}" \
    -o "${converted}"

  if [[ ! -s "${converted}" ]]; then
    echo "ERROR: snap-converter produced an empty weighted graph." >&2
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
  validate_symmetric_weighted_graph \
    "${cleaned}" \
    "${expected_n}" \
    "${expected_undirected_m}"

  # Install only after exact validation succeeds.
  mv -f "${cleaned}" "${final_graph}"

  if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
    rm -f "${raw_gr}" "${normalized}" "${converted}"
    rmdir "${tmp_dir}" 2>/dev/null || true
  fi

  echo
  echo "${display_name} preparation complete."
  echo "  final graph: ${final_graph}"
  echo "  cached raw:  ${archive}"
}

prepare_usa_central() {
  prepare_dimacs_road \
    "usa-central" \
    "USA-central" \
    "https://www.diag.uniroma1.it/~challenge9/data/USA-road-d/USA-road-d.CTR.gr.gz" \
    "USA-road-d.CTR.gr.gz" \
    "USA-road-d.CTR.gr" \
    "USA-road-d.CTR.adj" \
    "14081816" \
    "16933413"
}

prepare_usa_full() {
  prepare_dimacs_road \
    "usa-full" \
    "USA-full" \
    "https://www.diag.uniroma1.it/~challenge9/data/USA-road-d/USA-road-d.USA.gr.gz" \
    "USA-road-d.USA.gr.gz" \
    "USA-road-d.USA.gr" \
    "USA-road-d.USA.adj" \
    "23947347" \
    "28854312"
}

download_cached() {
  local url="$1"
  local destination="$2"

  if [[ "${FORCE}" -eq 1 ]]; then
    rm -f "${destination}"
  fi

  if [[ -s "${destination}" ]]; then
    echo "[download] using cached archive: ${destination}"
    return 0
  fi

  echo "[download] ${url}"
  local partial="${destination}.part"
  rm -f "${partial}"

  curl \
    --fail \
    --location \
    --retry 3 \
    --retry-delay 2 \
    --output "${partial}" \
    "${url}"

  if [[ ! -s "${partial}" ]]; then
    echo "ERROR: download produced an empty file: ${url}" >&2
    exit 1
  fi

  mv -f "${partial}" "${destination}"
}

install_weighted_rating_graph() {
  local display_name="$1"
  local weighted_edge_list="$2"
  local converted="$3"
  local cleaned="$4"
  local final_graph="$5"
  local expected_n="$6"
  local expected_undirected_m="$7"

  echo
  echo "[convert] weighted edge list -> temporary symmetric GBBS graph"
  "${CONVERTER}" \
    -s \
    -w \
    -i "${weighted_edge_list}" \
    -o "${converted}"

  if [[ ! -s "${converted}" ]]; then
    echo "ERROR: snap-converter produced an empty weighted graph." >&2
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
  validate_symmetric_weighted_graph \
    "${cleaned}" \
    "${expected_n}" \
    "${expected_undirected_m}"

  mv -f "${cleaned}" "${final_graph}"

  echo
  echo "${display_name} preparation complete."
  echo "  final graph: ${final_graph}"
}

prepare_libimseti() {
  local dataset_dir="${CACHE_DIR}/libimseti"
  local tmp_dir="${dataset_dir}/tmp"
  local output_dir="${INPUT_DIR}/RatingNetworks_weighted"
  mkdir -p "${dataset_dir}" "${tmp_dir}" "${output_dir}"

  # Stable mirror of the KONECT-formatted libimseti archive. This archive
  # contains libimseti/out.libimseti, the exact raw format validated during
  # artifact preparation.
  local source_url="https://downloads.skewed.de/mirror/konect.cc/files/download.tsv.libimseti.tar.bz2"
  local archive="${dataset_dir}/download.tsv.libimseti.tar.bz2"
  local raw="${tmp_dir}/out.libimseti"
  local transformed="${tmp_dir}/libimseti.weighted.tsv"
  local converted="${tmp_dir}/libimseti.preclean.adj"
  local cleaned="${tmp_dir}/libimseti.clean.adj"
  local final_graph="${output_dir}/libimseti.adj"

  local expected_n=220970
  local expected_undirected_m=17233144

  echo "Real-data preparation: libimseti"
  echo "  source data:  libimseti ratings"
  echo "  archive URL:  ${source_url}"
  echo "  transform:    weight = 11 - rating"
  echo "  final graph:  ${final_graph}"
  echo "  expected n:   ${expected_n}"
  echo "  expected m:   ${expected_undirected_m} undirected edges"
  echo

  if [[ "${FORCE}" -eq 0 && -s "${final_graph}" ]]; then
    echo "[existing] final graph already exists; validating it."
    if validate_symmetric_weighted_graph \
        "${final_graph}" "${expected_n}" "${expected_undirected_m}"; then
      echo
      echo "libimseti is already prepared correctly."
      return 0
    fi
    echo "Existing graph failed validation; rebuilding it." >&2
  fi

  rm -f "${raw}" "${transformed}" "${converted}" "${cleaned}"
  download_cached "${source_url}" "${archive}"

  echo
  echo "[extract] ${archive}"
  tar -xOf "${archive}" libimseti/out.libimseti > "${raw}"

  if [[ ! -s "${raw}" ]]; then
    echo "ERROR: libimseti archive did not yield libimseti/out.libimseti." >&2
    exit 1
  fi

  echo
  echo "[transform] ratings -> distances"
  python3 "${RATING_TRANSFORMER}" \
    "${raw}" \
    "${transformed}" \
    --scale 1 \
    --max-scaled-rating 10 \
    --delimiter whitespace \
    --comment-prefix "%"

  install_weighted_rating_graph \
    "libimseti" \
    "${transformed}" \
    "${converted}" \
    "${cleaned}" \
    "${final_graph}" \
    "${expected_n}" \
    "${expected_undirected_m}"

  if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
    rm -f "${raw}" "${transformed}" "${converted}"
    rmdir "${tmp_dir}" 2>/dev/null || true
  fi
  echo "  cached raw:  ${archive}"
}

prepare_movielens() {
  local dataset_dir="${CACHE_DIR}/movielens"
  local tmp_dir="${dataset_dir}/tmp"
  local output_dir="${INPUT_DIR}/RatingNetworks_weighted"
  mkdir -p "${dataset_dir}" "${tmp_dir}" "${output_dir}"

  # Exact GroupLens MovieLens ml-latest snapshot used in the experiments.
  # Snapshot generated 2023-07-20 (33,832,162 ratings).
  # The archive is mirrored as a pinned GitHub release asset so the artifact
  # does not depend on whatever version GroupLens may serve as "ml-latest"
  # in the future.
  local source_url="https://github.com/graph-benchmarks1/parallel-k-center/releases/download/artifact-data-v1/ml-latest.zip"
  local expected_sha256="66a9e518c747d76b241d9a859b001a2619d3ed1672ceef599eb50daf73a7b4a3"
  local archive="${dataset_dir}/ml-latest.zip"
  local raw="${tmp_dir}/ratings.csv"
  local transformed="${tmp_dir}/movielens.transformed.tsv"
  local bipartite="${tmp_dir}/movielens.weighted.tsv"
  local converted="${tmp_dir}/movielens.preclean.adj"
  local cleaned="${tmp_dir}/movielens.clean.adj"
  local final_graph="${output_dir}/movielens.adj"

  local expected_n=414214
  local expected_undirected_m=33832162
  local user_namespace_size=330975

  echo "Real-data preparation: MovieLens"
  echo "  source:       GroupLens ml-latest, snapshot generated 2023-07-20"
  echo "  mirror:       pinned artifact release asset"
  echo "  URL:          ${source_url}"
  echo "  transform:    weight = 11 - 2 * rating"
  echo "  bipartite:    movie IDs shifted by ${user_namespace_size}"
  echo "  final graph:  ${final_graph}"
  echo "  expected n:   ${expected_n}"
  echo "  expected m:   ${expected_undirected_m} undirected edges"
  echo

  if [[ "${FORCE}" -eq 0 && -s "${final_graph}" ]]; then
    echo "[existing] final graph already exists; validating it."
    if validate_symmetric_weighted_graph \
        "${final_graph}" "${expected_n}" "${expected_undirected_m}"; then
      echo
      echo "MovieLens is already prepared correctly."
      return 0
    fi
    echo "Existing graph failed validation; rebuilding it." >&2
  fi

  rm -f "${raw}" "${transformed}" "${bipartite}" "${converted}" "${cleaned}"
  download_cached "${source_url}" "${archive}"
  
  echo
  echo "[verify] MovieLens archive SHA-256"
  actual_sha256="$(sha256sum "${archive}" | awk '{print $1}')"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "ERROR: MovieLens archive checksum mismatch." >&2
    echo "  expected: ${expected_sha256}" >&2
    echo "  actual:   ${actual_sha256}" >&2
    echo "  archive:  ${archive}" >&2
    exit 1
  fi
  echo "  SHA-256 OK: ${actual_sha256}"

  echo
  echo "[extract] ml-latest/ratings.csv"
  unzip -p "${archive}" ml-latest/ratings.csv > "${raw}"

  if [[ ! -s "${raw}" ]]; then
    echo "ERROR: MovieLens archive did not yield ml-latest/ratings.csv." >&2
    exit 1
  fi

  echo
  echo "[transform] ratings -> distances"
  python3 "${RATING_TRANSFORMER}" \
    "${raw}" \
    "${transformed}" \
    --scale 2 \
    --max-scaled-rating 10 \
    --delimiter comma \
    --header

  echo
  echo "[normalize] separate user/movie vertex namespaces"
  awk -v off="${user_namespace_size}" '
    {
      if ($1 < 1 || $1 > off) {
        print "ERROR: unexpected MovieLens user ID " $1 " on line " NR > "/dev/stderr";
        exit 3;
      }
      print $1, ($2 + off), $3;
    }
  ' "${transformed}" > "${bipartite}"

  install_weighted_rating_graph \
    "MovieLens" \
    "${bipartite}" \
    "${converted}" \
    "${cleaned}" \
    "${final_graph}" \
    "${expected_n}" \
    "${expected_undirected_m}"

  if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
    rm -f "${raw}" "${transformed}" "${bipartite}" "${converted}"
    rmdir "${tmp_dir}" 2>/dev/null || true
  fi
  echo "  cached raw:  ${archive}"
}

prepare_yahoo_song() {
  local dataset_dir="${CACHE_DIR}/yahoo-song"
  local tmp_dir="${dataset_dir}/tmp"
  local output_dir="${INPUT_DIR}/RatingNetworks_weighted"
  mkdir -p "${dataset_dir}" "${tmp_dir}" "${output_dir}"

  # Stable mirror of KONECT yahoo-song. The graph is bipartite:
  # 1,000,990 users and 624,961 songs.
  local source_url="https://downloads.skewed.de/mirror/konect.cc/files/download.tsv.yahoo-song.tar.bz2"
  local archive="${dataset_dir}/download.tsv.yahoo-song.tar.bz2"
  local raw="${tmp_dir}/out.yahoo-song"
  local transformed="${tmp_dir}/yahoo-song.transformed.tsv"
  local bipartite="${tmp_dir}/yahoo-song.weighted.tsv"
  local converted="${tmp_dir}/yahoo-song.preclean.adj"
  local cleaned="${tmp_dir}/yahoo-song.clean.adj"
  local final_graph="${output_dir}/yahoo-song.adj"

  local expected_n=1625951
  local expected_undirected_m=256804235
  local user_namespace_size=1000990

  echo "Real-data preparation: Yahoo! Song"
  echo "  source:       KONECT yahoo-song"
  echo "  URL:          ${source_url}"
  echo "  transform:    weight = 101 - rating"
  echo "  bipartite:    song IDs shifted by ${user_namespace_size}"
  echo "  final graph:  ${final_graph}"
  echo "  expected n:   ${expected_n}"
  echo "  expected m:   ${expected_undirected_m} undirected edges"
  echo
  echo "WARNING: This dataset is very large (~1.4 GB compressed)."
  echo

  if [[ "${FORCE}" -eq 0 && -s "${final_graph}" ]]; then
    echo "[existing] final graph already exists; validating it."
    if validate_symmetric_weighted_graph \
        "${final_graph}" "${expected_n}" "${expected_undirected_m}"; then
      echo
      echo "Yahoo! Song is already prepared correctly."
      return 0
    fi
    echo "Existing graph failed validation; rebuilding it." >&2
  fi

  rm -f "${raw}" "${transformed}" "${bipartite}" "${converted}" "${cleaned}"
  download_cached "${source_url}" "${archive}"

  echo
  echo "[extract] yahoo-song/out.yahoo-song"
  tar -xOf "${archive}" yahoo-song/out.yahoo-song > "${raw}"

  if [[ ! -s "${raw}" ]]; then
    echo "ERROR: Yahoo archive did not yield yahoo-song/out.yahoo-song." >&2
    exit 1
  fi

  echo
  echo "[transform] ratings -> distances"
  python3 "${RATING_TRANSFORMER}" \
    "${raw}" \
    "${transformed}" \
    --scale 1 \
    --max-scaled-rating 100 \
    --delimiter whitespace \
    --comment-prefix "%"

  echo
  echo "[normalize] separate user/song vertex namespaces"
  awk -v off="${user_namespace_size}" '
    {
      if ($1 < 1 || $1 > off) {
        print "ERROR: unexpected Yahoo user ID " $1 " on line " NR > "/dev/stderr";
        exit 3;
      }
      print $1, ($2 + off), $3;
    }
  ' "${transformed}" > "${bipartite}"

  install_weighted_rating_graph \
    "Yahoo! Song" \
    "${bipartite}" \
    "${converted}" \
    "${cleaned}" \
    "${final_graph}" \
    "${expected_n}" \
    "${expected_undirected_m}"

  if [[ "${KEEP_INTERMEDIATE}" -eq 0 ]]; then
    rm -f "${raw}" "${transformed}" "${bipartite}" "${converted}"
    rmdir "${tmp_dir}" 2>/dev/null || true
  fi
  echo "  cached raw:  ${archive}"
}

case "${DATASET}" in
  dblp)
    prepare_dblp
    ;;
  youtube)
    prepare_youtube
    ;;
  livejournal)
    prepare_livejournal
    ;;
  orkut)
    prepare_orkut
    ;;
  twitter)
    prepare_twitter
    ;;
  friendster)
    prepare_friendster
    ;;
  usa-central)
    prepare_usa_central
    ;;
  usa-full)
    prepare_usa_full
    ;;
  libimseti)
    prepare_libimseti
    ;;
  movielens)
    prepare_movielens
    ;;
  yahoo-song)
    prepare_yahoo_song
    ;;
esac

