#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_DIR="${REPO_ROOT}/artifact/bin"
SPEC_DIR="${SCRIPT_DIR}/specs"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./artifact/experiments/run_experiment.sh <experiment-id> [--dry-run] [--resume]
  ./artifact/experiments/run_experiment.sh <experiment-id> --custom [--dry-run] [--resume]

Official mode:
  Loads the frozen paper specification and ignores environment overrides.

Custom mode:
  Loads the same specification, then permits these optional overrides:
    REPETITIONS=<n>
    BASE_SEED=<n>
    TIMEOUT_SECONDS=<seconds>
    THREAD_POINTS=<comma-separated; e.g. singlecore,8,16,32,64,128>
    THREAD_COUNTS=<comma-separated numeric alias; retained for compatibility>
    K_VALUES=<comma-separated>
    DELTA_VALUES=<comma-separated>
    EPSILON_VALUES=<comma-separated>
    RPP_VALUES=<comma-separated>
    ALGORITHMS=<comma-separated>
    DATASETS=<comma-separated graph paths/basenames/globs>
    RESULTS_DIR=<path>

Resume:
  --resume preserves an existing runs.tsv and skips every configuration already
  recorded with status OK, TIMEOUT, or FAIL. Missing configurations are run and
  appended. Without --resume, an existing runs.tsv is intentionally replaced.

Dry-run:
  --dry-run is read-only: it does not create or overwrite result files.

Examples:
  ./artifact/experiments/run_experiment.sh p5_parallel_small_synthetic --dry-run
  ./artifact/experiments/run_experiment.sh p5_parallel_small_synthetic --resume
  REPETITIONS=1 THREAD_POINTS=singlecore,8,16 \
    ./artifact/experiments/run_experiment.sh p5_parallel_small_synthetic --custom --dry-run
USAGE
}

[[ $# -ge 1 ]] || { usage; exit 2; }
REQUESTED_EXPERIMENT_ID="$1"
shift

DRY_RUN=0
CUSTOM=0
RESUME=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --custom) CUSTOM=1 ;;
    --resume) RESUME=1 ;;
    -h|--help) usage; exit 0 ;;
    *) experiment_die "unknown argument: $1" ;;
  esac
  shift
done

SPEC="${SPEC_DIR}/${REQUESTED_EXPERIMENT_ID}.sh"
[[ -r "${SPEC}" ]] || experiment_die "unknown experiment '${REQUESTED_EXPERIMENT_ID}' (missing ${SPEC})"

# Preserve possible custom overrides before the frozen spec is sourced.
ENV_REPETITIONS="${REPETITIONS-}"
ENV_BASE_SEED="${BASE_SEED-}"
ENV_TIMEOUT_SECONDS="${TIMEOUT_SECONDS-}"
ENV_THREAD_POINTS="${THREAD_POINTS-}"
ENV_THREAD_COUNTS="${THREAD_COUNTS-}"
ENV_K_VALUES="${K_VALUES-}"
ENV_DELTA_VALUES="${DELTA_VALUES-}"
ENV_EPSILON_VALUES="${EPSILON_VALUES-}"
ENV_RPP_VALUES="${RPP_VALUES-}"
ENV_ALGORITHMS="${ALGORITHMS-}"
ENV_DATASETS="${DATASETS-}"
ENV_RESULTS_DIR="${RESULTS_DIR-}"

# shellcheck disable=SC1090
source "${SPEC}"

CUSTOM_K_VALUES=()

: "${EXPERIMENT_ID:?spec must define EXPERIMENT_ID}"
: "${DESCRIPTION:?spec must define DESCRIPTION}"
: "${REPETITIONS:?spec must define REPETITIONS}"
: "${BASE_SEED:?spec must define BASE_SEED}"
: "${TIMEOUT_SECONDS:?spec must define TIMEOUT_SECONDS}"
: "${GBBS_INTERNAL_ROUNDS:?spec must define GBBS_INTERNAL_ROUNDS}"
: "${NB:?spec must define NB}"
[[ "${EXPERIMENT_ID}" == "${REQUESTED_EXPERIMENT_ID}" ]] \
  || experiment_die "spec id '${EXPERIMENT_ID}' does not match requested id '${REQUESTED_EXPERIMENT_ID}'"

if ! declare -p THREAD_POINTS >/dev/null 2>&1; then
  if declare -p THREAD_COUNTS >/dev/null 2>&1; then
    THREAD_POINTS=( "${THREAD_COUNTS[@]}" )
  else
    experiment_die "spec must define THREAD_POINTS"
  fi
fi

[[ ${FIXED_DELTA_WEIGHTED+x} ]] || experiment_die "spec must define FIXED_DELTA_WEIGHTED"
[[ ${FIXED_DELTA_UNWEIGHTED+x} ]] || experiment_die "spec must define FIXED_DELTA_UNWEIGHTED"

if (( CUSTOM )); then
  [[ -z "${ENV_REPETITIONS}" ]] || REPETITIONS="${ENV_REPETITIONS}"
  [[ -z "${ENV_BASE_SEED}" ]] || BASE_SEED="${ENV_BASE_SEED}"
  [[ -z "${ENV_TIMEOUT_SECONDS}" ]] || TIMEOUT_SECONDS="${ENV_TIMEOUT_SECONDS}"

  if [[ -n "${ENV_THREAD_POINTS}" ]]; then
    csv_to_array "${ENV_THREAD_POINTS}" THREAD_POINTS
  elif [[ -n "${ENV_THREAD_COUNTS}" ]]; then
    csv_to_array "${ENV_THREAD_COUNTS}" THREAD_POINTS
  fi

  [[ -z "${ENV_K_VALUES}" ]] || csv_to_array "${ENV_K_VALUES}" CUSTOM_K_VALUES
  if [[ -n "${ENV_DELTA_VALUES}" ]]; then
    declare -p DELTA_VALUES >/dev/null 2>&1 \
      || experiment_die "experiment ${EXPERIMENT_ID} has no delta sweep to override"
    csv_to_array "${ENV_DELTA_VALUES}" DELTA_VALUES
  fi
  if [[ -n "${ENV_EPSILON_VALUES}" ]]; then
    declare -p EPSILON_VALUES >/dev/null 2>&1 \
      || experiment_die "experiment ${EXPERIMENT_ID} has no epsilon sweep to override"
    csv_to_array "${ENV_EPSILON_VALUES}" EPSILON_VALUES
  fi
  if [[ -n "${ENV_RPP_VALUES}" ]]; then
    declare -p RPP_VALUES >/dev/null 2>&1 \
      || experiment_die "experiment ${EXPERIMENT_ID} has no rpp sweep to override"
    csv_to_array "${ENV_RPP_VALUES}" RPP_VALUES
  fi
  [[ -z "${ENV_ALGORITHMS}" ]] || csv_to_array "${ENV_ALGORITHMS}" ALGORITHMS

  if [[ -n "${ENV_DATASETS}" ]]; then
    DATASET_PATTERNS=()
    csv_to_array "${ENV_DATASETS}" DATASET_PATTERNS
    FILTERED_GRAPH_CASES=()

    for graph_case in "${GRAPH_CASES[@]}"; do
      IFS='|' read -r candidate_rel _ <<< "${graph_case}"
      candidate_base="${candidate_rel##*/}"
      selected=0
      for pattern in "${DATASET_PATTERNS[@]}"; do
        if [[ "${candidate_rel}" == ${pattern} || "${candidate_base}" == ${pattern} ]]; then
          selected=1
          break
        fi
      done
      (( selected )) && FILTERED_GRAPH_CASES+=( "${graph_case}" )
    done

    [[ ${#FILTERED_GRAPH_CASES[@]} -gt 0 ]]       || experiment_die "DATASETS filter matched no graph cases: ${ENV_DATASETS}"
    GRAPH_CASES=( "${FILTERED_GRAPH_CASES[@]}" )
  fi
fi

DEFAULT_RESULTS_DIR="${REPO_ROOT}/artifact-results/experiments/${EXPERIMENT_ID}"
if (( CUSTOM )); then
  DEFAULT_RESULTS_DIR="${REPO_ROOT}/artifact-results/custom/${EXPERIMENT_ID}"
fi
RESULTS_DIR="${ENV_RESULTS_DIR:-${DEFAULT_RESULTS_DIR}}"

SUMMARY="${RESULTS_DIR}/runs.tsv"
MANIFEST="${RESULTS_DIR}/manifest.txt"
TSV_HEADER=$'experiment_id\tdescription\tgraph\tgraph_type\talgorithm\tk\tmode\tthreads\tdelta\tepsilon\trpp_token\trpp_value\trepetition\tseed\truntime_s\tnum_centers\tmax_dist_to_centers\tunreachable_vertices\tfallback_calls\tstatus\tlog'

declare -A COMPLETED_RUNS=()

load_completed_runs() {
  local summary="$1"
  [[ -f "${summary}" ]] || return 0

  local actual_header
  IFS= read -r actual_header < "${summary}" || true
  [[ "${actual_header}" == "${TSV_HEADER}" ]]     || experiment_die "cannot resume: unexpected TSV header in ${summary}"

  while IFS= read -r key; do
    [[ -n "${key}" ]] && COMPLETED_RUNS["${key}"]=1
  done < <(
    awk -F '\t' '
      NR > 1 && ($20 == "OK" || $20 == "TIMEOUT" || $20 == "FAIL") {
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n",
          $3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
      }
    ' "${summary}"
  )
}

if (( RESUME )); then
  load_completed_runs "${SUMMARY}"
fi

if (( ! DRY_RUN )); then
  mkdir -p "${RESULTS_DIR}/raw"

  printf '%s\n' \
    "experiment_id=${EXPERIMENT_ID}" \
    "description=${DESCRIPTION}" \
    "custom=${CUSTOM}" \
    "resume=${RESUME}" \
    "repetitions=${REPETITIONS}" \
    "base_seed=${BASE_SEED}" \
    "timeout_seconds=${TIMEOUT_SECONDS}" \
    "gbbs_internal_rounds=${GBBS_INTERNAL_ROUNDS}" \
    "nb=${NB}" \
    "thread_points=${THREAD_POINTS[*]}" \
    "dataset_filter=${ENV_DATASETS}" \
    > "${MANIFEST}"

  if (( ! RESUME )) || [[ ! -f "${SUMMARY}" ]]; then
    printf '%s\n' "${TSV_HEADER}" > "${SUMMARY}"
  fi
fi

for algo in "${ALGORITHMS[@]}"; do
  binary="$(algorithm_binary "${algo}")" || experiment_die "unsupported algorithm '${algo}'"
  if (( ! DRY_RUN )); then
    [[ -x "${BIN_DIR}/${binary}" ]] \
      || experiment_die "missing binary ${BIN_DIR}/${binary}; run ./artifact/build.sh"
  fi
done

run_one() {
  local graph_rel="$1"
  local graph_type="$2"
  local algo="$3"
  local k="$4"
  local thread_point="$5"
  local delta="$6"
  local epsilon="$7"
  local rpp_token="$8"
  local rep="$9"

  local graph="${REPO_ROOT}/inputs/${graph_rel}"
  local binary_name binary seed mode threads rpp_value

  binary_name="$(algorithm_binary "${algo}")"
  binary="${BIN_DIR}/${binary_name}"
  seed=$((BASE_SEED + rep - 1))
  rpp_value=""

  if [[ "${thread_point}" == "singlecore" ]]; then
    mode="singlecore"
    threads=1
  else
    [[ "${thread_point}" =~ ^[1-9][0-9]*$ ]] \
      || experiment_die "invalid thread point '${thread_point}'"
    mode="parallel"
    threads="${thread_point}"
  fi

  if [[ -n "${rpp_token}" ]]; then
    case "${rpp_token}" in
      log2n|1log2n|2log2n|3log2n|4log2n)
        if [[ -f "${graph}" ]]; then
          rpp_value="$(resolve_rpp_token "${rpp_token}" "${graph}")" \
            || experiment_die "could not resolve rpp token '${rpp_token}' for ${graph_rel}"
        elif (( DRY_RUN )); then
          rpp_value="<resolved-from-n:${rpp_token}>"
        else
          experiment_die "missing graph ${graph}"
        fi
        ;;
      *)
        rpp_value="${rpp_token}"
        ;;
    esac
  fi

  local run_key
  run_key="${graph_rel}|${graph_type}|${algo}|${k}|${mode}|${threads}|${delta}|${epsilon}|${rpp_token}|${rpp_value}|${rep}|${seed}"
  if (( RESUME )) && [[ -n "${COMPLETED_RUNS[${run_key}]+x}" ]]; then
    printf '[resume] skip graph=%s algo=%s k=%s mode=%s threads=%s delta=%s epsilon=%s rpp=%s rep=%s seed=%s\n' \
      "${graph_rel}" "${algo}" "${k}" "${mode}" "${threads}"       "${delta}" "${epsilon}" "${rpp_token}" "${rep}" "${seed}"
    return 0
  fi

  local cmd=(
    "${binary}"
    -s
    -rounds "${GBBS_INTERNAL_ROUNDS}"
    -k "${k}"
    -seed "${seed}"
  )

  if [[ "${mode}" == "singlecore" ]]; then
    cmd+=( -sc )
  # Delta-stepping is used only for weighted parallel SSSP.
  elif [[ "${graph_type}" == "weighted" && -n "${delta}" ]]; then
    cmd+=( -delta "${delta}" -nb "${NB}" )
  fi

  case "${algo}" in
    approximategonzalez)
      [[ -n "${epsilon}" ]] || experiment_die "ApproximateGonzalez requires epsilon"
      cmd+=( -epsilon "${epsilon}" )
      ;;
    thorupsimple)
      : "${THORUP_SHRINK:?ThorupSimple requires THORUP_SHRINK}"
      : "${THORUP_LAMBDA:?ThorupSimple requires THORUP_LAMBDA}"
      [[ -n "${rpp_value}" ]] || experiment_die "ThorupSimple requires rpp"
      cmd+=( -shrink "${THORUP_SHRINK}" -lambda "${THORUP_LAMBDA}" -rpp "${rpp_value}" )
      ;;
  esac

  cmd+=( "${graph}" )

  local log_name
  log_name="$(printf '%s__%s__k%s__%s__t%s__d%s__e%s__rpp%s__rep%s.log' \
    "${graph_rel//\//_}" "${algo}" "${k}" "${mode}" "${threads}" \
    "${delta:-na}" "${epsilon:-na}" "${rpp_token:-na}" "${rep}")"
  local log_path="${RESULTS_DIR}/raw/${log_name}"

  printf '[%s] graph=%s algo=%s k=%s mode=%s threads=%s delta=%s epsilon=%s rpp=%s rep=%s seed=%s\n' \
    "${EXPERIMENT_ID}" "${graph_rel}" "${algo}" "${k}" "${mode}" "${threads}" \
    "${delta}" "${epsilon}" "${rpp_token}" "${rep}" "${seed}"

  if (( DRY_RUN )); then
    printf '  PARLAY_NUM_THREADS=%q timeout %q ' "${threads}" "${TIMEOUT_SECONDS}"
    printf '%q ' "${cmd[@]}"
    printf '\n'
    return 0
  fi

  [[ -f "${graph}" ]] || experiment_die "missing graph ${graph}"

  set +e
  timeout "${TIMEOUT_SECONDS}" \
    env PARLAY_NUM_THREADS="${threads}" \
    "${cmd[@]}" >"${log_path}" 2>&1
  exit_code=$?
  set -e

  local status="OK"
  if [[ "${exit_code}" -eq 124 ]]; then
    status="TIMEOUT"
  elif [[ "${exit_code}" -ne 0 ]]; then
    status="FAIL"
  fi

  local runtime centers radius unreachable fallback
  runtime="$(extract_runtime "${log_path}")"
  centers="$(extract_scalar_eq "num_centers" "${log_path}")"
  radius="$(extract_scalar_eq "max_dist_to_centers" "${log_path}")"
  unreachable="$(extract_scalar_eq "unreachable_vertices" "${log_path}")"
  fallback="$(extract_scalar_eq "fallback_calls" "${log_path}")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${EXPERIMENT_ID}" "${DESCRIPTION}" "${graph_rel}" "${graph_type}" "${algo}" \
    "${k}" "${mode}" "${threads}" "${delta}" "${epsilon}" "${rpp_token}" "${rpp_value}" \
    "${rep}" "${seed}" "${runtime}" "${centers}" "${radius}" "${unreachable}" \
    "${fallback}" "${status}" "${log_path}" >> "${SUMMARY}"

  if [[ "${status}" == "FAIL" ]]; then
    echo "Run failed; see ${log_path}" >&2
  fi
}

expand_algorithm() {
  local graph_rel="$1"
  local graph_type="$2"
  local k="$3"
  local algo="$4"

  local sweep_var="ALGORITHM_SWEEP_${algo}"
  local sweep="${!sweep_var:-none}"

  local algo_thread_var="ALGORITHM_THREAD_POINTS_${algo}"
  local algorithm_thread_points=()
  if declare -p "${algo_thread_var}" >/dev/null 2>&1; then
    eval 'algorithm_thread_points=( "${'"${algo_thread_var}"'[@]}" )'
  else
    algorithm_thread_points=( "${THREAD_POINTS[@]}" )
  fi

  for thread_point in "${algorithm_thread_points[@]}"; do
    local mode
    if [[ "${thread_point}" == "singlecore" ]]; then
      mode="singlecore"
    else
      mode="parallel"
    fi

    local deltas=()
    local epsilons=()
    local rpps=()

    case "${sweep}" in
      delta)
        deltas=( "${DELTA_VALUES[@]}" )
        epsilons=( "${FIXED_APPROX_EPSILON:-}" )
        rpps=( "" )
        ;;
      epsilon)
        if [[ "${mode}" == "singlecore" || "${graph_type}" == "unweighted" ]]; then
          deltas=( "" )
        else
          deltas=( "${FIXED_DELTA_WEIGHTED}" )
        fi
        epsilons=( "${EPSILON_VALUES[@]}" )
        rpps=( "" )
        ;;
      rpp)
        if [[ "${mode}" == "singlecore" || "${graph_type}" == "unweighted" ]]; then
          deltas=( "" )
        else
          deltas=( "${FIXED_DELTA_WEIGHTED}" )
        fi
        epsilons=( "" )
        rpps=( "${RPP_VALUES[@]}" )
        ;;
      none)
        if [[ "${mode}" == "singlecore" || "${graph_type}" == "unweighted" ]]; then
          deltas=( "" )
        else
          deltas=( "${FIXED_DELTA_WEIGHTED}" )
        fi

        if [[ "${algo}" == "approximategonzalez" ]]; then
          epsilons=( "${FIXED_APPROX_EPSILON}" )
        else
          epsilons=( "" )
        fi

        if [[ "${algo}" == "thorupsimple" ]]; then
          rpps=( "${FIXED_THORUP_RPP}" )
        else
          rpps=( "" )
        fi
        ;;
      *)
        experiment_die "unsupported sweep '${sweep}' for ${algo}"
        ;;
    esac

    for delta in "${deltas[@]}"; do
      for epsilon in "${epsilons[@]}"; do
        for rpp in "${rpps[@]}"; do
          for rep in $(seq 1 "${REPETITIONS}"); do
            run_one "${graph_rel}" "${graph_type}" "${algo}" "${k}" "${thread_point}" \
              "${delta}" "${epsilon}" "${rpp}" "${rep}"
          done
        done
      done
    done
  done
}

echo
echo "Experiment: ${EXPERIMENT_ID}"
echo "Description: ${DESCRIPTION}"
echo "Mode: $([[ ${CUSTOM} -eq 1 ]] && echo custom || echo official)"
echo "Resume: $([[ ${RESUME} -eq 1 ]] && echo yes || echo no)"
echo "Results: ${RESULTS_DIR}"
echo

for graph_case in "${GRAPH_CASES[@]}"; do
  IFS='|' read -r graph_rel graph_type k_csv graph_n_hint <<< "${graph_case}"

  local_k_values=()
  if (( CUSTOM )) && [[ ${#CUSTOM_K_VALUES[@]} -gt 0 ]]; then
    local_k_values=( "${CUSTOM_K_VALUES[@]}" )
  else
    csv_to_array "${k_csv}" local_k_values
  fi

  for k_token in "${local_k_values[@]}"; do
    k="${k_token}"
    if [[ "${k_token}" == "sqrt_n" ]]; then
      graph="${REPO_ROOT}/inputs/${graph_rel}"
      if [[ -f "${graph}" ]]; then
        k="$(resolve_k_token "${k_token}" "${graph}")" \
          || experiment_die "could not resolve k token '${k_token}' for ${graph_rel}"
      elif (( DRY_RUN )); then
        if [[ -n "${graph_n_hint:-}" ]]; then
          k="$(awk -v n="${graph_n_hint}" 'BEGIN { printf "%d", sqrt(n) }')"
        else
          case "${graph_rel}" in
            */ER_small/*) k=316 ;;
            */ER_large/*) k=3162 ;;
            *) k="<resolved-from-n:${k_token}>" ;;
          esac
        fi
      else
        experiment_die "missing graph ${graph}"
      fi
    fi

    for algo in "${ALGORITHMS[@]}"; do
      expand_algorithm "${graph_rel}" "${graph_type}" "${k}" "${algo}"
    done
  done
done

if (( DRY_RUN )); then
  echo
  echo "Dry run complete; no experiments executed."
else
  echo
  echo "Experiment complete."
  echo "Per-run TSV: ${SUMMARY}"
fi
