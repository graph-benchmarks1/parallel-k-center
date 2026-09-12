#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="${REPO_ROOT}/artifact/experiments/run_experiment.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

RESULTS="${TMP}/results"
mkdir -p "${RESULTS}"
SUMMARY="${RESULTS}/runs.tsv"

HEADER=$'experiment_id\tdescription\tgraph\tgraph_type\talgorithm\tk\tmode\tthreads\tdelta\tepsilon\trpp_token\trpp_value\trepetition\tseed\truntime_s\tnum_centers\tmax_dist_to_centers\tunreachable_vertices\tfallback_calls\tstatus\tlog'
printf '%s\n' "${HEADER}" > "${SUMMARY}"

# Pretend Gonzalez already completed successfully. Empty TSV fields are kept
# intentionally because real experiment rows contain many of them.
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "validation_runner_parser" \
  "Internal validation: all four paper algorithms through generic runner/parser" \
  "_ae_validation/er_n1000_d2_seed0.adj" "unweighted" "gonzalez" "10" \
  "parallel" "4" "" "" "" "" "1" "42" "0.01" "10" "3" "0" "" "OK" \
  "${RESULTS}/raw/existing-gonzalez.log" >> "${SUMMARY}"

before="$(sha256sum "${SUMMARY}" | awk '{print $1}')"

RESULTS_DIR="${RESULTS}" \
  "${RUNNER}" validation_runner_parser --resume --dry-run > "${TMP}/resume.log"

after="$(sha256sum "${SUMMARY}" | awk '{print $1}')"
[[ "${before}" == "${after}" ]] || {
  echo "FAIL: --resume --dry-run modified the existing runs.tsv" >&2
  exit 1
}

skip_count="$(grep -c '^\[resume\] skip ' "${TMP}/resume.log" || true)"
run_count="$(grep -c '^\[validation_runner_parser\] ' "${TMP}/resume.log" || true)"

[[ "${skip_count}" -eq 1 ]] || {
  echo "FAIL: expected exactly one resumed/skipped configuration, got ${skip_count}" >&2
  exit 1
}
[[ "${run_count}" -eq 3 ]] || {
  echo "FAIL: expected exactly three missing configurations in dry-run output, got ${run_count}" >&2
  exit 1
}

grep -q 'algo=gonzalez' "${TMP}/resume.log"
grep -q 'algo=approximategonzalez' "${TMP}/resume.log"
grep -q 'algo=abboud' "${TMP}/resume.log"
grep -q 'algo=thorupsimple' "${TMP}/resume.log"

# A non-resume dry-run must also be read-only.
RESULTS_DIR="${RESULTS}" \
  "${RUNNER}" validation_runner_parser --dry-run > "${TMP}/plain-dry.log"
after_plain="$(sha256sum "${SUMMARY}" | awk '{print $1}')"
[[ "${before}" == "${after_plain}" ]] || {
  echo "FAIL: ordinary --dry-run modified the existing runs.tsv" >&2
  exit 1
}

echo "PASS: resume recognizes an existing completed configuration with empty TSV fields"
echo "PASS: resume dry-run skips exactly that completed configuration and expands only the three missing runs"
echo "PASS: --resume --dry-run is read-only"
echo "PASS: ordinary --dry-run is also read-only"
echo
echo "Resume validation PASSED."
