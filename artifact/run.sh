#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-help}"
shift || true

case "${MODE}" in
  smoke)
    exec "${REPO_ROOT}/artifact/run_smoke_test.sh" "$@"
    ;;
  help|-h|--help)
    cat <<'EOF'
Usage:
  ./artifact/run.sh smoke
EOF
    ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    echo "Run './artifact/run.sh help' for usage." >&2
    exit 2
    ;;
esac
