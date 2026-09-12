#!/usr/bin/env bash
# Figure A.3 / Appendix A.6.2: Approximate Gonzalez epsilon on real-world data.
# The submitted figure compares epsilon=0.001 and epsilon=0.5.

EXPERIMENT_ID="p3_approx_epsilon_real"
DESCRIPTION="Figure A.3: Approximate Gonzalez epsilon on real-world graphs"

REPETITIONS=1
BASE_SEED=42
TIMEOUT_SECONDS=10800
GBBS_INTERNAL_ROUNDS=1
NB=128

THREAD_POINTS=(64)
ALGORITHMS=(gonzalez approximategonzalez)

EPSILON_VALUES=(0.001 0.5)
FIXED_DELTA_WEIGHTED=8
FIXED_DELTA_UNWEIGHTED=""
FIXED_APPROX_EPSILON=0.001

ALGORITHM_SWEEP_gonzalez="none"
ALGORITHM_SWEEP_approximategonzalez="epsilon"

GRAPH_CASES=(
  "SocialNetworks_unweighted/livejournal.adj|unweighted|10,50,300,2000"
  "SocialNetworks_unweighted/youtube.adj|unweighted|10,50,300,2000"
  "SocialNetworks_unweighted/orkut.adj|unweighted|10,50,300,2000"
  "RoadNetworks_weighted/USA-road-d.CTR.adj|weighted|10,50,300,2000"
)
