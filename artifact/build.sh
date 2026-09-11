#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${REPO_ROOT}/artifact/bin"

if ! command -v bazel >/dev/null 2>&1; then
  echo "Error: bazel is required but was not found in PATH." >&2
  echo "The repository expects Bazel $(cat "${REPO_ROOT}/.bazelversion" 2>/dev/null || echo 'as specified by .bazelversion')." >&2
  exit 2
fi

cd "${REPO_ROOT}"

EXPECTED_BAZEL_VERSION="$(cat .bazelversion 2>/dev/null || true)"
ACTUAL_BAZEL_VERSION="$(bazel --version 2>/dev/null | awk '{print $2}' || true)"
if [[ -n "${EXPECTED_BAZEL_VERSION}" && -n "${ACTUAL_BAZEL_VERSION}" && \
      "${EXPECTED_BAZEL_VERSION}" != "${ACTUAL_BAZEL_VERSION}" ]]; then
  echo "Warning: repository requests Bazel ${EXPECTED_BAZEL_VERSION}, but PATH provides ${ACTUAL_BAZEL_VERSION}." >&2
fi

# Recreate the install directory so stale binaries from an older source tree
# can never survive a failed or partial rebuild.
rm -rf "${BIN_DIR}"
mkdir -p "${BIN_DIR}"

echo "Building artifact executables and utilities..."

bazel build -c opt \
  //benchmarks/Clustering/K-Center/Gonzalez:Gonzalez_main \
  //benchmarks/Clustering/K-Center/Gonzalez:ApproximateGonzalez_main \
  //benchmarks/Clustering/K-Center/AbboudMISr:AbboudMISr_main \
  //benchmarks/Clustering/K-Center/ThorupSimple:ThorupSimple_main \
  //utils:simple_er_generator \
  //utils:snap_converter \
  //utils:clean_csr_graph

install_binary() {
  local source="$1"
  local target="$2"

  [[ -x "${source}" ]] || {
    echo "Error: expected Bazel output is missing or not executable: ${source}" >&2
    exit 1
  }
  install -m 0755 "${source}" "${BIN_DIR}/${target}"
}

echo "Copying binaries to ${BIN_DIR}..."

install_binary bazel-bin/benchmarks/Clustering/K-Center/Gonzalez/Gonzalez_main gonzalez
install_binary bazel-bin/benchmarks/Clustering/K-Center/Gonzalez/ApproximateGonzalez_main approximategonzalez
install_binary bazel-bin/benchmarks/Clustering/K-Center/AbboudMISr/AbboudMISr_main abboud
install_binary bazel-bin/benchmarks/Clustering/K-Center/ThorupSimple/ThorupSimple_main thorupsimple
install_binary bazel-bin/utils/simple_er_generator simple-er-generator
install_binary bazel-bin/utils/snap_converter snap-converter
install_binary bazel-bin/utils/clean_csr_graph clean-csr-graph

echo
echo "Build complete. Installed binaries:"
find "${BIN_DIR}" -maxdepth 1 -type f -printf '  %f\n' | sort

