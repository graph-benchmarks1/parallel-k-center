#!/usr/bin/env bash
# Figure 7.2: parallel scaling on USA-central.
# Parallel points stop at 32 threads because parallel execution was already
# slower than the true single-core implementation.

EXPERIMENT_ID="p8_parallel_road"
DESCRIPTION="Figure 7.2: Parallel scaling on the USA-central road network"

REPETITIONS=3
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(singlecore 8 16 32)
ALGORITHMS=(gonzalez approximategonzalez abboud thorupsimple)

FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.5
THORUP_SHRINK=2
THORUP_LAMBDA=1
FIXED_THORUP_RPP=4

ALGORITHM_SWEEP_gonzalez="none"
ALGORITHM_SWEEP_approximategonzalez="none"
ALGORITHM_SWEEP_abboud="none"
ALGORITHM_SWEEP_thorupsimple="none"

GRAPH_CASES=(
  "RoadNetworks_weighted/USA-road-d.CTR.adj|weighted|200,2000"
)
