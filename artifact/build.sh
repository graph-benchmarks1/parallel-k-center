#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${REPO_ROOT}/artifact/bin"

mkdir -p "${BIN_DIR}"
cd "${REPO_ROOT}"

echo "Building artifact executables and utilities..."

bazel build -c opt \
  //benchmarks/Clustering/K-Center/Gonzalez:Gonzalez_main \
  //benchmarks/Clustering/K-Center/Gonzalez:ApproximateGonzalez_main \
  //benchmarks/Clustering/K-Center/AbboudMISr:AbboudMISr_main \
  //benchmarks/Clustering/K-Center/ThorupSimple:ThorupSimple_main \
  //utils:simple_er_generator \
  //utils:snap_converter

echo "Copying binaries to ${BIN_DIR}..."

install -m 0755 \
  bazel-bin/benchmarks/Clustering/K-Center/Gonzalez/Gonzalez_main \
  "${BIN_DIR}/gonzalez"

install -m 0755 \
  bazel-bin/benchmarks/Clustering/K-Center/Gonzalez/ApproximateGonzalez_main \
  "${BIN_DIR}/approximategonzalez"

install -m 0755 \
  bazel-bin/benchmarks/Clustering/K-Center/AbboudMISr/AbboudMISr_main \
  "${BIN_DIR}/abboud"

install -m 0755 \
  bazel-bin/benchmarks/Clustering/K-Center/ThorupSimple/ThorupSimple_main \
  "${BIN_DIR}/thorupsimple"

install -m 0755 \
  bazel-bin/utils/simple_er_generator \
  "${BIN_DIR}/simple-er-generator"

install -m 0755 \
  bazel-bin/utils/snap_converter \
  "${BIN_DIR}/snap-converter"

echo
echo "Build complete. Installed binaries:"
find "${BIN_DIR}" -maxdepth 1 -type f -printf '  %f\n' | sort
