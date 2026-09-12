#!/usr/bin/env bash

EXPERIMENT_ID="p12_full_sweep_roads"
DESCRIPTION="Figures 7.4/7.5: Full sweep on road-network graphs"

REPETITIONS=3
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(singlecore)
ALGORITHMS=(gonzalez approximategonzalez abboud thorupsimple)

# Delta-stepping is not used in true single-core mode.
FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""

# Section A.6.2: epsilon=0.5 for road-network graphs.
FIXED_APPROX_EPSILON=0.5

THORUP_SHRINK=2
THORUP_LAMBDA=1
FIXED_THORUP_RPP=4

ALGORITHM_SWEEP_gonzalez="none"
ALGORITHM_SWEEP_approximategonzalez="none"
ALGORITHM_SWEEP_abboud="none"
ALGORITHM_SWEEP_thorupsimple="none"

GRAPH_CASES=(
  "Snap_weighted/USA-road-d.CTR.adj|weighted|20,100,500,3700|14081816"
  "Snap_weighted/USA-road-d.USA.adj|weighted|20,100,500,5200|23947347"
)
