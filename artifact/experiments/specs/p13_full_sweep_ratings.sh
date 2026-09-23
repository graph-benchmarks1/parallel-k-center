#!/usr/bin/env bash

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
  "RatingNetworks_weighted/libimseti.adj|weighted|20,100,sqrt_n|220970"
  "RatingNetworks_weighted/movielens.adj|weighted|20,100,sqrt_n|414214"
  "RatingNetworks_weighted/yahoo-song.adj|weighted|20,100,500,sqrt_n|1625951"
)
