#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-help}"
[[ $# -gt 0 ]] && shift || true

case "${MODE}" in
  build)
    exec "${REPO_ROOT}/artifact/build.sh" "$@"
    ;;
  smoke)
    # A reviewer-facing smoke test should be a single command. Rebuild first so
    # the test always exercises the current source tree rather than stale bins.
    "${REPO_ROOT}/artifact/build.sh"
    exec "${REPO_ROOT}/artifact/run_smoke_test.sh" "$@"
    ;;
  smoke-no-build)
    exec "${REPO_ROOT}/artifact/run_smoke_test.sh" "$@"
    ;;
  help|-h|--help)
    cat <<'USAGE'
Usage:
  ./artifact/run.sh build           Build the four paper algorithms and utilities.
  ./artifact/run.sh smoke           Build, then run the complete smoke test.
  ./artifact/run.sh smoke-no-build  Run the smoke test using existing artifact/bin binaries.
USAGE
    ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    echo "Run './artifact/run.sh help' for usage." >&2
    exit 2
    ;;
esac

