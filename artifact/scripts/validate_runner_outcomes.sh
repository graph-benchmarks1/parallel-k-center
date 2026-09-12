#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PREP="${REPO_ROOT}/artifact/scripts/prepare_synthetic_datasets.sh"
SOURCE_GRAPH="${REPO_ROOT}/artifact/data/synthetic-prep-test/Snap_unweighted/ER_small/er_n1000_d2_seed0.adj"
VALIDATION_DIR="${REPO_ROOT}/inputs/_ae_validation"
VALIDATION_GRAPH="${VALIDATION_DIR}/er_n1000_d2_seed0.adj"
INVALID_GRAPH="${VALIDATION_DIR}/invalid.adj"

TIMEOUT_RESULTS="${REPO_ROOT}/artifact-results/validation/timeout"
FAIL_RESULTS="${REPO_ROOT}/artifact-results/validation/fail"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

[[ -x "${REPO_ROOT}/artifact/bin/gonzalez" ]] \
  || die "missing artifact/bin/gonzalez; run ./artifact/build.sh first"
[[ -x "${PREP}" ]] \
  || die "missing synthetic preparation script: ${PREP}"

echo "== Preparing validation inputs =="
if [[ ! -f "${SOURCE_GRAPH}" ]]; then
  "${PREP}" test
else
  echo "Using existing ${SOURCE_GRAPH}"
fi
[[ -f "${SOURCE_GRAPH}" ]] || die "validation graph was not produced"

mkdir -p "${VALIDATION_DIR}"
ln -sfn "${SOURCE_GRAPH}" "${VALIDATION_GRAPH}"

# A file that exists (so the runner accepts the path) but is intentionally not
# valid GBBS adjacency data. This should make the application itself exit
# nonzero, exercising FAIL rather than the runner's missing-file guard.
printf 'this is intentionally not a GBBS graph\n' > "${INVALID_GRAPH}"

cleanup() {
  rm -f "${VALIDATION_GRAPH}" "${INVALID_GRAPH}"
  rmdir "${VALIDATION_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

rm -rf "${TIMEOUT_RESULTS}" "${FAIL_RESULTS}"

echo
echo "== Forcing a TIMEOUT =="
RESULTS_DIR="${TIMEOUT_RESULTS}" \
  "${REPO_ROOT}/artifact/run.sh" experiment validation_timeout

echo
echo "== Forcing a non-timeout FAIL =="
RESULTS_DIR="${FAIL_RESULTS}" \
  "${REPO_ROOT}/artifact/run.sh" experiment validation_fail

echo
echo "== Validating recorded outcome statuses =="
python3 - "${TIMEOUT_RESULTS}/runs.tsv" "${FAIL_RESULTS}/runs.tsv" <<'PY'
import csv
import sys
from pathlib import Path

timeout_tsv = Path(sys.argv[1])
fail_tsv = Path(sys.argv[2])

def read_one(path: Path):
    if not path.is_file():
        raise SystemExit(f"ERROR: missing TSV: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if len(rows) != 1:
        raise SystemExit(f"ERROR: expected exactly 1 row in {path}, found {len(rows)}")
    return rows[0]

timeout_row = read_one(timeout_tsv)
fail_row = read_one(fail_tsv)

checks = [
    ("TIMEOUT", timeout_row, "validation_timeout"),
    ("FAIL", fail_row, "validation_fail"),
]

for expected_status, row, expected_id in checks:
    if row.get("experiment_id") != expected_id:
        raise SystemExit(
            f"ERROR [{expected_status}]: experiment_id mismatch: "
            f"{row.get('experiment_id')!r}"
        )
    if row.get("status") != expected_status:
        raise SystemExit(
            f"ERROR [{expected_status}]: expected status={expected_status}, "
            f"got {row.get('status')!r}"
        )
    if row.get("algorithm") != "gonzalez":
        raise SystemExit(
            f"ERROR [{expected_status}]: expected algorithm=gonzalez, "
            f"got {row.get('algorithm')!r}"
        )
    if row.get("repetition") != "1" or row.get("seed") != "42":
        raise SystemExit(
            f"ERROR [{expected_status}]: repetition/seed mismatch: "
            f"{row.get('repetition')!r}/{row.get('seed')!r}"
        )

    log = Path(row.get("log", ""))
    if not log.is_file():
        raise SystemExit(f"ERROR [{expected_status}]: raw log missing: {log}")

    print(
        f"PASS [{expected_status}]: status recorded correctly; "
        f"log={log}"
    )

# A failed or timed-out run must never be mistaken for a successful measurement.
for label, row in (("TIMEOUT", timeout_row), ("FAIL", fail_row)):
    if row.get("status") == "OK":
        raise SystemExit(f"ERROR [{label}]: run was incorrectly recorded as OK")

print()
print("PASS: timeout is represented explicitly as TIMEOUT")
print("PASS: nonzero application exit is represented explicitly as FAIL")
print("PASS: both outcome rows retain their raw-log paths")
print("PASS: runner completed the experiment wrapper instead of aborting the batch")
PY

echo
echo "Outcome validation PASSED."
echo "Timeout results: ${TIMEOUT_RESULTS}"
echo "Fail results:    ${FAIL_RESULTS}"
