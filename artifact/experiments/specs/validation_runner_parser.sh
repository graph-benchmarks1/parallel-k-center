#!/usr/bin/env bash
# Internal artifact validation spec.
#
# This is NOT a paper experiment and is deliberately excluded from every
# experiment batch. It exists only to exercise the generic experiment runner,
# raw-log capture, and TSV parsing end-to-end on a tiny graph.

EXPERIMENT_ID="validation_runner_parser"
DESCRIPTION="Internal validation: all four paper algorithms through generic runner/parser"

REPETITIONS=1
BASE_SEED=42
TIMEOUT_SECONDS=60
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(4)
ALGORITHMS=(gonzalez approximategonzalez abboud thorupsimple)

FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.001

THORUP_SHRINK=2
THORUP_LAMBDA=1
FIXED_THORUP_RPP=4

ALGORITHM_SWEEP_gonzalez="none"
ALGORITHM_SWEEP_approximategonzalez="none"
ALGORITHM_SWEEP_abboud="none"
ALGORITHM_SWEEP_thorupsimple="none"

GRAPH_CASES=(
  "_ae_validation/er_n1000_d2_seed0.adj|unweighted|10|1000"
)
