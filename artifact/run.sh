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
    "${REPO_ROOT}/artifact/build.sh"
    exec "${REPO_ROOT}/artifact/run_smoke_test.sh" "$@"
    ;;
  smoke-no-build)
    exec "${REPO_ROOT}/artifact/run_smoke_test.sh" "$@"
    ;;
  validate-runner)
    exec "${REPO_ROOT}/artifact/scripts/validate_experiment_runner.sh" "$@"
    ;;
  validate-outcomes)
    exec "${REPO_ROOT}/artifact/scripts/validate_runner_outcomes.sh" "$@"
    ;;
  validate-aggregation)
    exec python3 "${REPO_ROOT}/artifact/scripts/validate_aggregation.py" "$@"
    ;;
  aggregate)
    exec "${REPO_ROOT}/artifact/scripts/aggregate_experiment.sh" "$@"
    ;;
  derive)
    exec "${REPO_ROOT}/artifact/scripts/derive_experiment.sh" "$@"
    ;;
  validate-derivation)
    exec python3 "${REPO_ROOT}/artifact/scripts/validate_paper_derivation.py" "$@"
    ;;
  plot)
    exec "${REPO_ROOT}/artifact/scripts/plot_experiment.sh" "$@"
    ;;
  validate-plotting)
    exec python3 "${REPO_ROOT}/artifact/scripts/validate_plotting.py" "$@"
    ;;
  validate-parameter-plotting)
    exec python3 "${REPO_ROOT}/artifact/scripts/validate_parameter_plotting.py" "$@"
    ;;
  validate-parallel-plotting)
    exec python3 "${REPO_ROOT}/artifact/scripts/validate_parallel_plotting.py" "$@"
    ;;
  validate-profiles)
    exec "${REPO_ROOT}/artifact/scripts/validate_profiles.sh" "$@"
    ;;
  validate-resume)
    exec "${REPO_ROOT}/artifact/scripts/validate_resume.sh" "$@"
    ;;
  light_synthetic|light_real|light|full_synthetic|full_real|full)
    exec "${REPO_ROOT}/artifact/scripts/run_profile.sh" "${MODE}" "$@"
    ;;
  experiment)
    [[ $# -ge 1 ]] || {
      echo "Usage: ./artifact/run.sh experiment <experiment-id> [--dry-run] [--resume]" >&2
      exit 2
    }
    exec "${REPO_ROOT}/artifact/experiments/run_experiment.sh" "$@"
    ;;
  batch)
    [[ $# -ge 1 ]] || {
      echo "Usage: ./artifact/run.sh batch <batch-name> [--dry-run] [--resume]" >&2
      exit 2
    }
    exec "${REPO_ROOT}/artifact/experiments/run_batch.sh" "$@"
    ;;
  custom)
    [[ $# -ge 1 ]] || {
      echo "Usage: ./artifact/run.sh custom <experiment-id> [--dry-run] [--resume]" >&2
      exit 2
    }
    exec "${REPO_ROOT}/artifact/experiments/run_experiment.sh" "$1" --custom "${@:2}"
    ;;
  help|-h|--help)
    cat <<'USAGE'
Usage:
  ./artifact/run.sh build
      Build the four paper algorithms and utilities.

  ./artifact/run.sh smoke
      Build, then run the complete smoke test.

  ./artifact/run.sh smoke-no-build
      Run the smoke test using existing artifact/bin binaries.

  ./artifact/run.sh validate-runner
      Execute one tiny real run and cross-check TSV parsing against its raw log.

  ./artifact/run.sh validate-outcomes
      Force one timeout and one application failure and verify TSV status handling.

  ./artifact/run.sh validate-aggregation
      Regression-test median-over-repetitions and median-over-graph-seeds aggregation.

  ./artifact/run.sh aggregate <experiment-id>
      Aggregate one completed experiment into summary/per_graph.tsv and summary/aggregated.tsv.

  ./artifact/run.sh derive <experiment-id>
      Build paper-facing results, including Gonzalez-relative radius and P10/P11 Abboud mode selection.

  ./artifact/run.sh validate-derivation
      Regression-test paper-specific derived quantities and Abboud mode selection.

  ./artifact/run.sh plot <experiment-id>
      Reconstruct full-sweep paper figures for completed P9-P13 experiments.

  ./artifact/run.sh validate-plotting
      Regression-test P9-P13 plotting from fixture result data (does not run experiments).

  ./artifact/run.sh validate-parameter-plotting
      Regression-test P1-P4 plotting from fixture result data (does not run experiments).

  ./artifact/run.sh validate-parallel-plotting
      Regression-test P5-P8 plotting from fixture aggregated data (does not run experiments).

  ./artifact/run.sh validate-profiles
      Dry-run and validate the high-level light profiles; executes no experiments.

  ./artifact/run.sh validate-resume
      Fixture-test resume matching and verify that all dry-runs are read-only.

  ./artifact/run.sh light_synthetic [--dry-run] [--resume]
      Prepare small synthetic data and reproduce a manageable exact P9 witness subset:
      rho={4,16}, weighted/unweighted, seeds 0..9, k={20,200}.

  ./artifact/run.sh light_real [--dry-run] [--resume]
      Prepare and reproduce the submitted-paper configurations for DBLP, YouTube,
      and libimseti.

  ./artifact/run.sh light [--dry-run] [--resume]
      Run light_synthetic followed by light_real.

  ./artifact/run.sh full_synthetic [--dry-run] [--resume]
      Prepare all synthetic datasets and run/postprocess all synthetic experiment families.

  ./artifact/run.sh full_real [--dry-run] [--resume]
      Prepare all real datasets and run/postprocess all real experiment families.

  ./artifact/run.sh full [--dry-run] [--resume]
      Prepare all datasets and run/postprocess the complete P1-P13 paper suite.

  ./artifact/run.sh experiment <id> [--dry-run] [--resume]
      Run one frozen paper experiment exactly as specified. --resume skips
      configurations already recorded as OK, TIMEOUT, or FAIL.

  ./artifact/run.sh batch parameter_choices [--dry-run] [--resume]
      Run all algorithmic parameter-choice experiments (P1-P4).

  ./artifact/run.sh batch parallel_scaling [--dry-run] [--resume]
      Run all parallel-scaling experiments (Figures A.5, A.6, 7.1, 7.2).

  ./artifact/run.sh batch full_sweep_synthetic [--dry-run] [--resume]
      Run the full small/large synthetic sweeps (Figures A.7-A.10).

  ./artifact/run.sh batch full_sweep_real [--dry-run] [--resume]
      Run the full social-network, road-network, and rating-network sweeps.

  ./artifact/run.sh custom <id> [--dry-run] [--resume]
      Use the same executor while permitting documented environment overrides.

Experiment IDs:
  p1_delta
  p2_approx_epsilon_synthetic
  p3_approx_epsilon_real
  p4_thorup_rpp
  p5_parallel_small_synthetic
  p6_parallel_large_synthetic
  p7_parallel_social
  p8_parallel_road
  p9_full_sweep_small_synthetic
  p10_full_sweep_large_synthetic
  p11_full_sweep_social
  p12_full_sweep_roads
  p13_full_sweep_ratings
USAGE
    ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    echo "Run './artifact/run.sh help' for usage." >&2
    exit 2
    ;;
esac
