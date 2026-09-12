#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PREP="${REPO_ROOT}/artifact/scripts/prepare_synthetic_datasets.sh"
SOURCE_GRAPH="${REPO_ROOT}/artifact/data/synthetic-prep-test/Snap_unweighted/ER_small/er_n1000_d2_seed0.adj"
VALIDATION_DIR="${REPO_ROOT}/inputs/_ae_validation"
VALIDATION_GRAPH="${VALIDATION_DIR}/er_n1000_d2_seed0.adj"
RESULTS_DIR="${REPO_ROOT}/artifact-results/validation/runner-parser"
SUMMARY="${RESULTS_DIR}/runs.tsv"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

for binary in gonzalez approximategonzalez abboud thorupsimple; do
  [[ -x "${REPO_ROOT}/artifact/bin/${binary}" ]] \
    || die "missing artifact/bin/${binary}; run ./artifact/build.sh first"
done
[[ -x "${PREP}" ]] \
  || die "missing synthetic preparation script: ${PREP}"

echo "== Preparing tiny validation graph =="
if [[ ! -f "${SOURCE_GRAPH}" ]]; then
  "${PREP}" test
else
  echo "Using existing ${SOURCE_GRAPH}"
fi
[[ -f "${SOURCE_GRAPH}" ]] || die "validation graph was not produced"

mkdir -p "${VALIDATION_DIR}"
ln -sfn "${SOURCE_GRAPH}" "${VALIDATION_GRAPH}"

cleanup() {
  rm -f "${VALIDATION_GRAPH}"
  rmdir "${VALIDATION_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

rm -rf "${RESULTS_DIR}"

echo
echo "== Executing all four algorithms through the generic experiment runner =="
RESULTS_DIR="${RESULTS_DIR}" \
  "${REPO_ROOT}/artifact/run.sh" experiment validation_runner_parser

[[ -f "${SUMMARY}" ]] || die "runner did not produce ${SUMMARY}"

echo
echo "== Cross-checking every TSV row against its raw log =="
python3 - "${SUMMARY}" <<'PY'
import csv
import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

summary = Path(sys.argv[1])
with summary.open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f, delimiter="\t"))

expected_algorithms = {
    "gonzalez",
    "approximategonzalez",
    "abboud",
    "thorupsimple",
}

if len(rows) != 4:
    raise SystemExit(f"ERROR: expected exactly 4 TSV rows, found {len(rows)}")

seen = {row.get("algorithm", "") for row in rows}
if seen != expected_algorithms:
    raise SystemExit(
        f"ERROR: algorithm set mismatch: expected {sorted(expected_algorithms)}, got {sorted(seen)}"
    )

def last_match(text, pattern, label, required=True):
    vals = re.findall(pattern, text, flags=re.MULTILINE)
    if not vals:
        if required:
            raise SystemExit(f"ERROR: could not find {label} in raw log")
        return ""
    return vals[-1].strip()

def numeric_equal(a, b):
    try:
        return Decimal(a) == Decimal(b)
    except InvalidOperation:
        return a == b

for row in rows:
    algo = row["algorithm"]

    common_expected = {
        "experiment_id": "validation_runner_parser",
        "graph": "_ae_validation/er_n1000_d2_seed0.adj",
        "graph_type": "unweighted",
        "k": "10",
        "mode": "parallel",
        "threads": "4",
        "repetition": "1",
        "seed": "42",
        "status": "OK",
    }
    for key, expected in common_expected.items():
        actual = row.get(key, "")
        if actual != expected:
            raise SystemExit(
                f"ERROR [{algo}]: TSV {key} mismatch: expected {expected!r}, got {actual!r}"
            )

    if algo == "approximategonzalez" and row.get("epsilon") != "0.001":
        raise SystemExit(
            f"ERROR [approximategonzalez]: expected epsilon=0.001, got {row.get('epsilon')!r}"
        )
    if algo == "thorupsimple":
        if row.get("rpp_token") != "4" or row.get("rpp_value") != "4":
            raise SystemExit(
                "ERROR [thorupsimple]: expected rpp_token=rpp_value=4, got "
                f"{row.get('rpp_token')!r}/{row.get('rpp_value')!r}"
            )

    for key in (
        "runtime_s",
        "num_centers",
        "max_dist_to_centers",
        "unreachable_vertices",
        "log",
    ):
        if not row.get(key, ""):
            raise SystemExit(f"ERROR [{algo}]: TSV field {key!r} is empty")

    log_path = Path(row["log"])
    if not log_path.is_file():
        raise SystemExit(f"ERROR [{algo}]: raw log does not exist: {log_path}")

    text = log_path.read_text(encoding="utf-8", errors="replace")

    raw = {
        "runtime_s": last_match(
            text,
            r"^[ \t]*### Running Time:[ \t]*([0-9.eE+-]+)[ \t]*$",
            "### Running Time",
        ),
        "num_centers": last_match(
            text,
            r"^[ \t]*num_centers[ \t]*=[ \t]*(.+?)[ \t]*$",
            "num_centers",
        ),
        "max_dist_to_centers": last_match(
            text,
            r"^[ \t]*max_dist_to_centers[ \t]*=[ \t]*(.+?)[ \t]*$",
            "max_dist_to_centers",
        ),
        "unreachable_vertices": last_match(
            text,
            r"^[ \t]*unreachable_vertices[ \t]*=[ \t]*(.+?)[ \t]*$",
            "unreachable_vertices",
        ),
    }

    for key, raw_value in raw.items():
        tsv_value = row[key]
        if not numeric_equal(tsv_value, raw_value):
            raise SystemExit(
                f"ERROR [{algo}]: {key} mismatch: "
                f"TSV={tsv_value!r}, raw log={raw_value!r}"
            )

    # Thorup has an additional diagnostic that the generic runner records.
    raw_fallback = last_match(
        text,
        r"^[ \t]*fallback_calls[ \t]*=[ \t]*(.+?)[ \t]*$",
        "fallback_calls",
        required=(algo == "thorupsimple"),
    )
    if algo == "thorupsimple":
        if row.get("fallback_calls", "") == "":
            raise SystemExit("ERROR [thorupsimple]: TSV fallback_calls is empty")
        if not numeric_equal(row["fallback_calls"], raw_fallback):
            raise SystemExit(
                "ERROR [thorupsimple]: fallback_calls mismatch: "
                f"TSV={row['fallback_calls']!r}, raw log={raw_fallback!r}"
            )
    else:
        if row.get("fallback_calls", "") != "":
            raise SystemExit(
                f"ERROR [{algo}]: unexpected fallback_calls={row['fallback_calls']!r}"
            )

    centers = int(row["num_centers"])
    if not (1 <= centers <= 10):
        raise SystemExit(
            f"ERROR [{algo}]: expected 1 <= num_centers <= 10, got {centers}"
        )

    if row["unreachable_vertices"] != "0":
        raise SystemExit(
            f"ERROR [{algo}]: validation graph unexpectedly has "
            f"{row['unreachable_vertices']} unreachable vertices"
        )

    print(
        f"PASS [{algo}]: runtime={row['runtime_s']} "
        f"centers={row['num_centers']} radius={row['max_dist_to_centers']} "
        f"unreachable={row['unreachable_vertices']}"
        + (
            f" fallback_calls={row['fallback_calls']}"
            if algo == "thorupsimple"
            else ""
        )
    )

print()
print("PASS: exactly four algorithm rows")
print("PASS: all statuses are OK")
print("PASS: every raw log exists")
print("PASS: runtime/centers/radius/unreachable parsing matches every raw log")
print("PASS: Thorup fallback_calls parsing matches its raw log")
PY

echo
echo "Runner/parser validation PASSED for all four paper algorithms."
echo "Results kept in: ${RESULTS_DIR}"
