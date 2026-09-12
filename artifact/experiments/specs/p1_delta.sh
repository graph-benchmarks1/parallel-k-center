#!/usr/bin/env bash

EXPERIMENT_ID="p1_delta"
DESCRIPTION="Figure A.1: Delta-stepping bucket-width parameter choice"

REPETITIONS=1
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(64)
ALGORITHMS=(gonzalez approximategonzalez abboud)

DELTA_VALUES=(2 4 8 16)
FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.1

ALGORITHM_SWEEP_gonzalez="delta"
ALGORITHM_SWEEP_approximategonzalez="delta"
ALGORITHM_SWEEP_abboud="delta"

GRAPH_CASES=(
  "Snap_weighted/ER_small/er_n100000_d4_seed2_w.adj|weighted|20,200"
  "Snap_weighted/ER_small/er_n100000_d8_seed2_w.adj|weighted|20,200"
  "Snap_weighted/ER_small/er_n100000_d16_seed2_w.adj|weighted|20,200"
  "Snap_weighted/ER_large/er_n10000000_d4_seed0_w.adj|weighted|200,2000"
  "Snap_weighted/ER_large/er_n10000000_d8_seed0_w.adj|weighted|200,2000"
  "Snap_weighted/ER_large/er_n10000000_d16_seed0_w.adj|weighted|200,2000"
)
