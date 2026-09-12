#!/usr/bin/env bash
# Figures A.12 and A.13: full sweep on the three rating-network instances.
#
# The submitted paper states that all algorithms use parallel execution with
# 64 threads for this family. Runtime and solution quality come from the same
# executions.
#
# The final k point is defined literally as floor(sqrt(n)) and is resolved
# from the actual prepared graph header at execution time. The fourth field
# in each GRAPH_CASE is only an n hint for concrete dry-run output.

EXPERIMENT_ID="p13_full_sweep_ratings"
DESCRIPTION="Figures A.12/A.13: Full sweep on rating-network graphs"

REPETITIONS=3
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(64)
ALGORITHMS=(gonzalez approximategonzalez abboud thorupsimple)

FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""

# Section A.6.2: only road networks use epsilon=0.5.
# These dense rating networks use epsilon=0.001.
FIXED_APPROX_EPSILON=0.001

THORUP_SHRINK=2
THORUP_LAMBDA=1
FIXED_THORUP_RPP=4

ALGORITHM_SWEEP_gonzalez="none"
ALGORITHM_SWEEP_approximategonzalez="none"
ALGORITHM_SWEEP_abboud="none"
ALGORITHM_SWEEP_thorupsimple="none"

GRAPH_CASES=(
  "Snap_weighted/libimseti.adj|weighted|20,100,sqrt_n|220970"
  "Snap_weighted/movielens.adj|weighted|20,100,sqrt_n|414214"
  "Snap_weighted/yahoo-song.adj|weighted|20,100,500,sqrt_n|1625951"
)
