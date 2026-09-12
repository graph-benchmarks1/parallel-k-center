#!/usr/bin/env bash
# Figures A.7 and A.8: full sweep on small synthetic graphs.
#
# All six densities and both graph types are tested.  For every density/type,
# all ten independently generated graph seeds are included.  Every individual
# configuration is repeated three times.
#
# Figure A.7 reports running time and Figure A.8 reports solution quality from
# these same executions.  The paper uses single-core execution for all four
# algorithms on graphs of this size.

EXPERIMENT_ID="p9_full_sweep_small_synthetic"
DESCRIPTION="Figures A.7/A.8: Full sweep on small synthetic graphs"

REPETITIONS=3
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(singlecore)
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
  for density in 2 4 8 16 32 64; do
    GRAPH_CASES+=(
      "Snap_unweighted/ER_small/er_n100000_d${density}_seed${seed}.adj|unweighted|20,50,100,sqrt_n"
      "Snap_weighted/ER_small/er_n100000_d${density}_seed${seed}_w.adj|weighted|20,50,100,sqrt_n"
    )
  done
done
