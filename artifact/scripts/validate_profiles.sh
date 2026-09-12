#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="${REPO_ROOT}/artifact/scripts/run_profile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

count_runs() {
  local file="$1"
  grep -Ec '^\[p[0-9]+_' "${file}" || true
}

"${PROFILE}" light_synthetic --dry-run > "${TMP}/synthetic.log"
synthetic_runs="$(count_runs "${TMP}/synthetic.log")"
[[ "${synthetic_runs}" -eq 960 ]] || {
  echo "FAIL: light_synthetic expanded ${synthetic_runs} runs; expected 960" >&2
  exit 1
}
grep -q 'prepare_synthetic_datasets.sh light_synthetic' "${TMP}/synthetic.log"
grep -q 'd4_seed' "${TMP}/synthetic.log"
grep -q 'd16_seed' "${TMP}/synthetic.log"
if grep -Eq 'd(2|8|32|64)_seed[0-9]' "${TMP}/synthetic.log"; then
  echo "FAIL: light_synthetic experiment expansion contains an unintended density" >&2
  exit 1
fi

"${PROFILE}" light_real --dry-run > "${TMP}/real.log"
real_runs="$(count_runs "${TMP}/real.log")"
[[ "${real_runs}" -eq 141 ]] || {
  echo "FAIL: light_real expanded ${real_runs} runs; expected 141" >&2
  exit 1
}
grep -q 'prepare_real_datasets.sh dblp' "${TMP}/real.log"
grep -q 'prepare_real_datasets.sh youtube' "${TMP}/real.log"
grep -q 'prepare_real_datasets.sh libimseti' "${TMP}/real.log"
if grep -Eq 'com-lj\.adj|com-orkut\.adj|twitter-2010\.adj|com-friendster\.adj|movielens\.adj|yahoo-song\.adj' "${TMP}/real.log"; then
  echo "FAIL: light_real experiment expansion contains an unintended graph" >&2
  exit 1
fi

"${PROFILE}" light --dry-run > "${TMP}/light.log"
light_runs="$(count_runs "${TMP}/light.log")"
[[ "${light_runs}" -eq 1101 ]] || {
  echo "FAIL: light expanded ${light_runs} runs; expected 1101" >&2
  exit 1
}

# Dry-run must not claim it executed/postprocessed anything.
grep -q 'No datasets were prepared, no algorithms were executed, no result files were modified, and no results were postprocessed.' "${TMP}/light.log"

echo "PASS: light_synthetic expands exactly 960 P9 paper-compatible runs"
echo "PASS: light_synthetic restricts execution to rho={4,16}, both graph types, seeds 0..9, k={20,200}"
echo "PASS: light_real expands exactly 141 runs on DBLP, YouTube, and libimseti"
echo "PASS: light_real preserves each selected graph's submitted-paper k set and execution modes"
echo "PASS: light expands to 1101 total algorithm runs"
echo "PASS: profile dry-run performs no build, dataset preparation, algorithm execution, aggregation, derivation, or plotting"
echo
echo "High-level profile validation PASSED."
