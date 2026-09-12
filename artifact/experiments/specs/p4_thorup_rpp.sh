#!/usr/bin/env bash

EXPERIMENT_ID="p4_thorup_rpp"
DESCRIPTION="Figure A.4: Simplified Thorup rounds-per-phase parameter choice"

REPETITIONS=1
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(64)
ALGORITHMS=(thorupsimple)

RPP_VALUES=(2 4 8 16 log2n 2log2n)
FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.001

THORUP_SHRINK=2
THORUP_LAMBDA=1
FIXED_THORUP_RPP=4

ALGORITHM_SWEEP_thorupsimple="rpp"

GRAPH_CASES=(
  "Snap_unweighted/ER_large/er_n10000000_d16_seed0.adj|unweighted|20,100,500,3000"
  "Snap_weighted/ER_large/er_n10000000_d4_seed0_w.adj|weighted|20,100"
  "Snap_weighted/ER_large/er_n10000000_d16_seed0_w.adj|weighted|20,100"
)
