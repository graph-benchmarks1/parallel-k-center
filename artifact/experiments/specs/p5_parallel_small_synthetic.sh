#!/usr/bin/env bash

EXPERIMENT_ID="p5_parallel_small_synthetic"
DESCRIPTION="Figure A.5: Parallel scaling on small synthetic graphs"

REPETITIONS=3
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(singlecore 8 16 32 64 128)
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

GRAPH_CASES=()
for seed in {0..9}; do
  GRAPH_CASES+=(
    "Snap_unweighted/ER_small/er_n100000_d4_seed${seed}.adj|unweighted|20,200"
    "Snap_unweighted/ER_small/er_n100000_d16_seed${seed}.adj|unweighted|20,200"
    "Snap_weighted/ER_small/er_n100000_d4_seed${seed}_w.adj|weighted|20,200"
    "Snap_weighted/ER_small/er_n100000_d16_seed${seed}_w.adj|weighted|20,200"
  )
done
