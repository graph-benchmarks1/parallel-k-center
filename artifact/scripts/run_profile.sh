#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="${REPO_ROOT}/artifact/experiments/run_experiment.sh"

usage() {
  cat <<'EOF'
Usage:
  ./artifact/run.sh light_synthetic [--dry-run] [--resume]
  ./artifact/run.sh light_real [--dry-run] [--resume]
  ./artifact/run.sh light [--dry-run] [--resume]
  ./artifact/run.sh full_synthetic [--dry-run] [--resume]
  ./artifact/run.sh full_real [--dry-run] [--resume]
  ./artifact/run.sh full [--dry-run] [--resume]

Profiles:
  light_synthetic
      Prepare all small synthetic graphs (n=100,000), then execute an exact
      paper-compatible witness subset of P9:
        rho={4,16}, weighted+unweighted, graph seeds 0..9,
        k={20,200}, all four algorithms, 3 repetitions.
      This is 960 individual algorithm runs.

  light_real
      Prepare DBLP, YouTube, and libimseti, then execute their exact P11/P13
      paper configurations (including the paper k sets and execution modes).
      This is 141 individual algorithm runs.

  light
      light_synthetic + light_real (1101 algorithm runs).

  full_synthetic
      Prepare all synthetic datasets and execute P1,P2,P4,P5,P6,P9,P10.

  full_real
      Prepare all real datasets and execute P3,P7,P8,P11,P12,P13.

  full
      Prepare all datasets and execute P1-P13.

For non-dry runs, each experiment is automatically aggregated, paper-derived
quantities are generated where applicable, and the corresponding figure(s)
are plotted.

--dry-run prints preparation commands and expands experiment commands, but
does not build, download/generate datasets, execute algorithms, aggregate,
derive, plot, or modify existing result files.

--resume preserves partial runs.tsv files and skips configurations already
recorded as OK, TIMEOUT, or FAIL. Dataset preparation remains cache-aware.
EOF
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
PROFILE="$1"
shift

DRY_RUN=0
RESUME=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --resume) RESUME=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "${PROFILE}" in
  light_synthetic|light_real|light|full_synthetic|full_real|full) ;;
  *) echo "ERROR: unknown profile: ${PROFILE}" >&2; usage >&2; exit 2 ;;
esac

say() { printf '\n==== %s ====\n' "$*"; }

prepare_synthetic() {
  local prep_profile="$1"
  say "Prepare synthetic datasets: ${prep_profile}"
  if (( DRY_RUN )); then
    echo "${REPO_ROOT}/artifact/scripts/prepare_synthetic_datasets.sh ${prep_profile}"
  else
    "${REPO_ROOT}/artifact/scripts/prepare_synthetic_datasets.sh" "${prep_profile}"
  fi
}

prepare_real_dataset() {
  local ds="$1"
  say "Prepare real dataset: ${ds}"
  if (( DRY_RUN )); then
    echo "${REPO_ROOT}/artifact/scripts/prepare_real_datasets.sh ${ds}"
  else
    "${REPO_ROOT}/artifact/scripts/prepare_real_datasets.sh" "${ds}"
  fi
}

needs_derive() {
  case "$1" in
    p2_approx_epsilon_synthetic|p3_approx_epsilon_real|\
    p9_full_sweep_small_synthetic|p10_full_sweep_large_synthetic|\
    p11_full_sweep_social|p12_full_sweep_roads|p13_full_sweep_ratings)
      return 0 ;;
    *) return 1 ;;
  esac
}

postprocess() {
  local exp="$1"
  local results_dir="$2"

  say "Aggregate ${exp}"
  RESULTS_DIR="${results_dir}" "${REPO_ROOT}/artifact/scripts/aggregate_experiment.sh" "${exp}"

  if needs_derive "${exp}"; then
    say "Derive paper quantities for ${exp}"
    RESULTS_DIR="${results_dir}" "${REPO_ROOT}/artifact/scripts/derive_experiment.sh" "${exp}"
  fi

  say "Plot ${exp}"
  RESULTS_DIR="${results_dir}" "${REPO_ROOT}/artifact/scripts/plot_experiment.sh" "${exp}"
}

run_official() {
  local exp="$1"
  local args=()
  (( DRY_RUN )) && args+=( --dry-run )
  (( RESUME )) && args+=( --resume )

  say "Run official experiment ${exp}"
  "${RUNNER}" "${exp}" "${args[@]}"

  if (( ! DRY_RUN )); then
    postprocess "${exp}" "${REPO_ROOT}/artifact-results/experiments/${exp}"
  fi
}

run_light_custom() {
  local profile_name="$1"
  local exp="$2"
  local datasets="$3"
  local kvals="${4:-}"

  local results_dir="${REPO_ROOT}/artifact-results/profiles/${profile_name}/${exp}"
  say "Run ${profile_name}: ${exp}"

  local args=( --custom )
  (( DRY_RUN )) && args+=( --dry-run )
  (( RESUME )) && args+=( --resume )

  if [[ -n "${kvals}" ]]; then
    DATASETS="${datasets}" K_VALUES="${kvals}" RESULTS_DIR="${results_dir}" \
      "${RUNNER}" "${exp}" "${args[@]}"
  else
    DATASETS="${datasets}" RESULTS_DIR="${results_dir}" \
      "${RUNNER}" "${exp}" "${args[@]}"
  fi

  if (( ! DRY_RUN )); then
    postprocess "${exp}" "${results_dir}"
  fi
}

build_once() {
  if (( DRY_RUN )); then
    say "Build"
    echo "${REPO_ROOT}/artifact/build.sh"
  else
    say "Build"
    "${REPO_ROOT}/artifact/build.sh"
  fi
}

run_light_synthetic() {
  prepare_synthetic light_synthetic

  # Exact P9 subset. Wildcards are interpreted by run_experiment.sh's DATASETS
  # filter, not by the invoking shell.
  run_light_custom \
    light_synthetic \
    p9_full_sweep_small_synthetic \
    '*d4_seed*.adj,*d16_seed*.adj' \
    '20,200'
}

run_light_real() {
  prepare_real_dataset dblp
  prepare_real_dataset youtube
  prepare_real_dataset libimseti

  # Keep each graph's submitted-paper k set. Therefore no global K_VALUES
  # override is supplied for these two experiment families.
  run_light_custom \
    light_real \
    p11_full_sweep_social \
    'com-dblp.adj,com-youtube.adj'

  run_light_custom \
    light_real \
    p13_full_sweep_ratings \
    'libimseti.adj'
}

run_full_synthetic() {
  prepare_synthetic full_synthetic
  for exp in \
    p1_delta \
    p2_approx_epsilon_synthetic \
    p4_thorup_rpp \
    p5_parallel_small_synthetic \
    p6_parallel_large_synthetic \
    p9_full_sweep_small_synthetic \
    p10_full_sweep_large_synthetic
  do
    run_official "${exp}"
  done
}

run_full_real() {
  for ds in \
    dblp youtube livejournal orkut twitter friendster \
    usa-central usa-full \
    libimseti movielens yahoo-song
  do
    prepare_real_dataset "${ds}"
  done

  for exp in \
    p3_approx_epsilon_real \
    p7_parallel_social \
    p8_parallel_road \
    p11_full_sweep_social \
    p12_full_sweep_roads \
    p13_full_sweep_ratings
  do
    run_official "${exp}"
  done
}

build_once

case "${PROFILE}" in
  light_synthetic)
    run_light_synthetic
    ;;
  light_real)
    run_light_real
    ;;
  light)
    run_light_synthetic
    run_light_real
    ;;
  full_synthetic)
    run_full_synthetic
    ;;
  full_real)
    run_full_real
    ;;
  full)
    # Prepare/run both sides, but build only once.
    run_full_synthetic
    run_full_real
    ;;
esac

if (( DRY_RUN )); then
  say "${PROFILE} dry-run complete"
  echo "No datasets were prepared, no algorithms were executed, no result files were modified, and no results were postprocessed."
else
  say "${PROFILE} complete"
  echo "Results are under ${REPO_ROOT}/artifact-results/."
fi
