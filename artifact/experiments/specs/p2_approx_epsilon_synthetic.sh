#!/usr/bin/env bash

EXPERIMENT_ID="p2_approx_epsilon_synthetic"
DESCRIPTION="Figure A.2: Approximate Gonzalez epsilon on weighted synthetic graph"

REPETITIONS=1
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(64)
ALGORITHMS=(gonzalez approximategonzalez)

EPSILON_VALUES=(0.001 0.01 0.1 0.5)
FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.001

ALGORITHM_SWEEP_gonzalez="none"
ALGORITHM_SWEEP_approximategonzalez="epsilon"

GRAPH_CASES=(
  "Snap_weighted/ER_large/er_n10000000_d16_seed0_w.adj|weighted|10,50,200,3000"
)
