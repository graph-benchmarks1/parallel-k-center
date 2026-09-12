#!/usr/bin/env bash

EXPERIMENT_ID="p11_full_sweep_social"
DESCRIPTION="Figures 7.3/A.11: Full sweep on social-network graphs"

REPETITIONS=3
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(64)
ALGORITHMS=(gonzalez approximategonzalez abboud thorupsimple)
ALGORITHM_THREAD_POINTS_abboud=(singlecore 64)

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
  "Snap_unweighted/com-dblp.adj|unweighted|20,100,sqrt_n|317080"
  "Snap_unweighted/com-youtube.adj|unweighted|20,100,500,sqrt_n|1134890"
  "Snap_unweighted/com-lj.adj|unweighted|20,100,500,sqrt_n|3997962"
  "Snap_unweighted/com-orkut.adj|unweighted|20,100,500,sqrt_n|3072441"
  "Snap_unweighted/twitter-2010.adj|unweighted|20,100,500,2000,sqrt_n|41652230"
  "Snap_unweighted/com-friendster.adj|unweighted|20,100,500,2000,sqrt_n|65608366"
)
