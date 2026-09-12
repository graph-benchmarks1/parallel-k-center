#!/usr/bin/env bash
# Figures A.9 and A.10: full sweep on large synthetic graphs.
#
# All six densities and both graph types are tested using the one large graph
# seed (seed0) for each density/type.  Every individual configuration is
# repeated three times.
#
# Gonzalez, Approximate Gonzalez, and Simplified Thorup use 64-thread parallel
# execution.  Abboud MIS is executed both single-core and with 64 threads; the
# aggregation/plotting stage chooses the faster completed Abboud result at each
# graph/k configuration, as in Figure A.9.
#
# Figure A.10 omits rho=2 from the quality plot because those instances yielded
# infinite radii, but rho=2 is still part of the executed full sweep.

EXPERIMENT_ID="p10_full_sweep_large_synthetic"
DESCRIPTION="Figures A.9/A.10: Full sweep on large synthetic graphs"

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

GRAPH_CASES=()
for density in 2 4 8 16 32 64; do
  GRAPH_CASES+=(
    "Snap_unweighted/ER_large/er_n10000000_d${density}_seed0.adj|unweighted|20,100,500,sqrt_n"
    "Snap_weighted/ER_large/er_n10000000_d${density}_seed0_w.adj|weighted|20,100,500,sqrt_n"
  )
done
