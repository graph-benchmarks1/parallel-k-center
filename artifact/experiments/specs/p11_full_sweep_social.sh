#!/usr/bin/env bash
# Figures 7.3 and A.11: full sweep on the six social-network instances.
#
# Figure 7.3 reports running time and Figure A.11 reports solution quality from
# the same executions.  Gonzalez, Approximate Gonzalez, and Simplified Thorup
# use 64-thread parallel execution. Abboud MIS is executed both single-core and
# with 64 threads; plotting/aggregation chooses the faster completed Abboud
# result for each graph/k configuration.
#
# The largest k point is defined literally as floor(sqrt(n)) and is resolved
# from the actual prepared graph header at execution time. The fourth field in
# each GRAPH_CASE is only an n hint so dry-runs can show the concrete k value.

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
