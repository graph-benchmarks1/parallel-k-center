#!/usr/bin/env bash
# Internal artifact validation spec: forced non-timeout failure.
# Not part of any paper batch.

EXPERIMENT_ID="validation_fail"
DESCRIPTION="Internal validation: force one run to fail on malformed graph input"

REPETITIONS=1
BASE_SEED=42
TIMEOUT_SECONDS=10
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(4)
ALGORITHMS=(gonzalez)

FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.001

THORUP_SHRINK=2
THORUP_LAMBDA=1
FIXED_THORUP_RPP=4

ALGORITHM_SWEEP_gonzalez="none"

GRAPH_CASES=(
  "_ae_validation/invalid.adj|unweighted|10|1"
)
