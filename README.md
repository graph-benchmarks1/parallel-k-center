# GBBS: Graph Based Benchmark Suite  ![Bazel build](https://github.com/paralg/gbbs/workflows/CI/badge.svg)

Organization
--------

This repository contains code for our SPAA paper "Theoretically Efficient
Parallel Graph Algorithms Can Be Fast and Scalable" (SPAA'18). It includes
implementations of the following parallel graph algorithms:

**Clustering Problems**
* SCAN Graph Clustering
* Graph-Based Hierarchical Agglomerative Clustering (Graph HAC)

**Connectivity Problems**
* Low-Diameter Decomposition
* Connectivity
* Spanning Forest
* Biconnectivity
* Minimum Spanning Tree
* Strongly Connected Components

**Covering Problems**
* Coloring
* Maximal Matching
* Maximal Independent Set
* Approximate Set Cover

**Eigenvector Problems**
* PageRank

**Substructure Problems**
* Triangle Counting
* Approximate Densest Subgraph
* k-Core (Coreness)
* Degeneracy Ordering (Low-Outdegree Orientation)
* k-Clique Counting
* 5-Cycle Counting
* k-Truss

**Shortest Path Problems**
* Unweighted SSSP (Breadth-First Search)
* General Weight SSSP (Bellman-Ford)
* Integer Weight SSSP (Weighted Breadth-First Search)
* Single-Source Betweenness Centrality
* Single-Source Widest Path
* k-Spanner

The code for these applications is located in the `benchmark` directory. The
implementations are based on the Ligra/Ligra+/Julienne graph processing
frameworks. The framework code is located in the `src` directory.

If you use our work, please cite our [paper](https://arxiv.org/abs/1805.05208):

```
@inproceedings{dhulipala2018theoretically,
  author    = {Laxman Dhulipala and
               Guy E. Blelloch and
               Julian Shun},
  title     = {Theoretically Efficient Parallel Graph Algorithms Can Be Fast and
               Scalable},
  booktitle = {ACM Symposium on Parallelism in Algorithms and Architectures (SPAA)},
  year      = {2018},
}
```

Compilation
--------

Compiler:
* g++ &gt;= 7.4.0 with support for Cilk Plus
* g++ &gt;= 7.4.0 with pthread support (Homemade Scheduler)

Build system:
* [Bazel](https://docs.bazel.build/versions/master/install.html) 2.1.0
* Make --- though our primary build system is Bazel, we also maintain Makefiles
  for those who wish to run benchmarks without installing Bazel.

The default compilation uses a lightweight scheduler developed at CMU (Homemade)
for parallelism, which results in comparable performance to Cilk Plus. The
half-lengths for certain functions such as histogramming are lower using
Homemade, which results in better performance for codes like KCore.

The benchmark supports both uncompressed and compressed graphs. The uncompressed
format is identical to the uncompressed format in Ligra. The compressed format,
called bytepd_amortized (bytepda) is similar to the parallelByte format used in
Ligra+, with some additional functionality to support efficiently packs,
filters, and other operations over neighbor lists.

To compile codes for graphs with more than 2^32 edges, the `GBBSLONG` command-line
parameter should be set. If the graph has more than 2^32 vertices, the
`GBBSEDGELONG` command-line parameter should be set. Note that the codes have not
been tested with more than 2^32 vertices, so if any issues arise please contact
[Laxman Dhulipala](mailto:laxman@umd.edu).

To compile with the Cilk Plus scheduler instead of the Homegrown scheduler, use
the Bazel configuration `--config=cilk`. To compile using OpenMP instead, use
the Bazel configuration `--config=openmp`. To compile serially instead, use the
Bazel configuration `--config=serial`. (For the Makefiles, instead set the
environment variables `CILK`, `OPENMP`, or `SERIAL` respectively.)

To build:
```sh
# Load external libraries as submodules. (This only needs to be run once.)
git submodule update --init

# For Bazel:
$ bazel build  //...  # compiles all benchmarks

# For Make:
# First set the appropriate environment variables, e.g., first run
# `export CILK=1` to compile with Cilk Plus.
# After that, build using `make`.
$ cd benchmarks/BFS/NonDeterministicBFS  # go to a benchmark
$ make
```
Note that the default compilation mode in bazel is to build optimized binaries
(stripped of debug symbols). You can compile debug binaries by supplying `-c
dbg` to the bazel build command.

The following commands cleans the directory:
```sh
# For Bazel:
$ bazel clean  # removes all executables

# For Make:
$ make clean  # removes executables for the current directory
```

Running code
-------
The applications take the input graph as input as well as an optional
flag "-s" to indicate a symmetric graph.  Symmetric graphs should be
called with the "-s" flag for better performance. For example:

```sh
# For Bazel:
$ bazel run //benchmarks/BFS/NonDeterministicBFS:BFS_main -- -s -src 10 ~/gbbs/inputs/rMatGraph_J_5_100
$ bazel run //benchmarks/IntegralWeightSSSP/JulienneDBS17:wBFS_main -- -s -w -src 15 ~/gbbs/inputs/rMatGraph_WJ_5_100

# For Make:
$ ./BFS -s -src 10 ../../../inputs/rMatGraph_J_5_100
$ ./wBFS -s -w -src 15 ../../../inputs/rMatGraph_WJ_5_100
```

Note that the codes that compute single-source shortest paths (or centrality)
take an extra `-src` flag. The benchmark is run four times by default, and can
be changed by passing the `-rounds` flag followed by an integer indicating the
number of runs.

On NUMA machines, adding the command "numactl -i all " when running
the program may improve performance for large graphs. For example:

```sh
$ numactl -i all bazel run [...]
```

Running code on compressed graphs
-----------

We make use of the bytePDA format in our benchmark, which is similar to the
parallelByte format of Ligra+, extended with additional functionality. We have
provided a converter utility which takes as input an uncompressed graph and
outputs a bytePDA graph. The converter can be used as follows:

```sh
# For Bazel:
bazel run //utils:compressor -- -s -o ~/gbbs/inputs/rMatGraph_J_5_100.bytepda ~/gbbs/inputs/rMatGraph_J_5_100
bazel run //utils:compressor -- -s -w -o ~/gbbs/inputs/rMatGraph_WJ_5_100.bytepda ~/gbbs/inputs/rMatGraph_WJ_5_100

# For Make:
./compressor -s -o ../inputs/rMatGraph_J_5_100.bytepda ../inputs/rMatGraph_J_5_100
./compressor -s -w -o ../inputs/rMatGraph_WJ_5_100.bytepda ../inputs/rMatGraph_WJ_5_100
```

After an uncompressed graph has been converted to the bytepda format,
applications can be run on it by passing in the usual command-line flags, with
an additional `-c` flag.

```sh
# For Bazel:
$ bazel run //benchmarks/BFS/NonDeterministicBFS:BFS_main -- -s -c -src 10 ~/gbbs/inputs/rMatGraph_J_5_100.bytepda

# For Make:
$ ./BFS -s -c -src 10 ../../../inputs/rMatGraph_J_5_100.bytepda
$ ./wBFS -s -w -c -src 15 ../../../inputs/rMatGraph_WJ_5_100.bytepda
```

When processing large compressed graphs, using the `-m` command-line flag can
help if the file is already in the page cache, since the compressed graph data
can be mmap'd. Application performance will be affected if the file is not
already in the page-cache. We have found that using `-m` when the compressed
graph is backed by SSD results in a slow first-run, followed by fast subsequent
runs.

Running code on binary-encoded graphs
-----------
We make use of a binary-graph format in our benchmark. The binary representation
stores the representation we use for in-memory processing (compressed sparse row)
directly on disk, which enables applications to avoid string-conversion overheads
associated with the adjacency graph format described below. We have provided a
converter utility which takes as input an uncompressed graph (e.g., in adjacency
graph format) and outputs this graph in the binary format. The converter can be
used as follows:

```sh
# For Bazel:
bazel run //utils:compressor -- -s -o ~/gbbs/inputs/rMatGraph_J_5_100.binary ~/gbbs/inputs/rMatGraph_J_5_100

# For Make:
./compressor -s -o ../inputs/rMatGraph_J_5_100.binary ../inputs/rMatGraph_J_5_100
```

After an uncompressed graph has been converted to the binary format,
applications can be run on it by passing in the usual command-line flags, with
an additional `-b` flag. Note that the application will always load the binary
file using mmap.

```sh
# For Bazel:
$ bazel run //benchmarks/BFS/NonDeterministicBFS:BFS_main -- -s -b -src 10 ~/gbbs/inputs/rMatGraph_J_5_100.binary

# For Make:
$ ./BFS -s -b -src 10 ../../../inputs/rMatGraph_J_5_100.binary
```

Note that application performance will be affected if the file is not already
in the page-cache. We have found that using `-m` when the binary graph is backed
by SSD or disk results in a slow first-run, followed by fast subsequent runs.


Input Formats
-----------
We support the adjacency graph format used by the [Problem Based Benchmark
suite](http://www.cs.cmu.edu/~pbbs/benchmarks/graphIO.html)
and [Ligra](https://github.com/jshun/ligra).

The adjacency graph format starts with a sequence of offsets one for each
vertex, followed by a sequence of directed edges ordered by their source vertex.
The offset for a vertex i refers to the location of the start of a contiguous
block of out edges for vertex i in the sequence of edges. The block continues
until the offset of the next vertex, or the end if i is the last vertex. All
vertices and offsets are 0 based and represented in decimal. The specific format
is as follows:

```
AdjacencyGraph
<n>
<m>
<o0>
<o1>
...
<o(n-1)>
<e0>
<e1>
...
<e(m-1)>
```

This file is represented as plain text.

Weighted graphs are represented in the weighted adjacency graph format. The file
should start with the string "WeightedAdjacencyGraph". The m edge weights
should be stored after all of the edge targets in the .adj file.

**Using SNAP graphs**

Graphs from the [SNAP dataset
collection](https://snap.stanford.edu/data/index.html) are commonly used for
graph algorithm benchmarks. We provide a tool that converts the most common SNAP
graph format to the adjacency graph format that GBBS accepts. Usage example:
```sh
# Download a graph from the SNAP collection.
wget https://snap.stanford.edu/data/wiki-Vote.txt.gz
gzip --decompress ${PWD}/wiki-Vote.txt.gz
# Run the SNAP-to-adjacency-graph converter.
# Run with Bazel:
bazel run //utils:snap_converter -- -s -i ${PWD}/wiki-Vote.txt -o <output file>
# Or run with Make:
#   cd utils
#   make snap_converter
#   ./snap_converter -s -i <input file> -o <output file>
```

## Reproducing the Experiments of An experimental evaluation of static k-center clustering algorithms on graphs

This repository contains the artifact for the above mentioned paper.

The artifact provides an automated workflow for

- building the four algorithms evaluated in the paper,
- downloading/generating the required datasets,
- preprocessing the graphs,
- executing the experiments,
- aggregating repeated runs,
- generating corresponding plots

The recommended way to evaluate the artifact is through the supplied Docker
environment. The high-level commands described below are intended to be the
main interface for artifact evaluation; it is not necessary to invoke Bazel or
the individual benchmark binaries manually.

### Requirements

The recommended workflow requires

- Docker,
- Internet access for downloading the real-world datasets, and
- sufficient disk space for the selected reproduction profile. (~300GB for the full experimental reproduction should be sufficient)

Large experiments may require substantial memory, disk space, and running time.
For this reason, the artifact provides both manageable `light` profiles and
the complete `full` reproduction.

### Quick Start

From the repository root, build the artifact image:

```bash
docker build -f artifact/Dockerfile -t kcenter-ae .
```

First run the smoke test:

```bash
docker run --rm kcenter-ae smoke
```

The smoke test runs small deterministic test instances and checks all four
algorithms used in the paper:

- Gonzalez,
- Approximate Gonzalez,
- Abboud et al.,
- Thorup.

The smoke test is a functionality check and not a reproduction of
the paper experiments.

### Persistent Dataset and Result Directories

For actual reproduction runs, we recommend keeping generated/downloaded
datasets and experiment results outside the container. This allows results to
be inspected directly on the host and makes interrupted experiments resumable
across separate Docker invocations.

Create the directories once:

```bash
mkdir -p inputs artifact-results
```

Then mount them when running a reproduction profile:

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae <profile>
```

In the commands below, `<profile>` is replaced by one of the reproduction
profiles described in the next section.

### Reproduction Profiles

The artifact provides several high-level profiles so that evaluators can
choose a reproduction scope appropriate for the available resources.

#### Light Synthetic Reproduction

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae light_synthetic
```

This prepares the small synthetic instances and executes a manageable subset:

- `n = 100,000`,
- densities `rho = 4, 16`,
- weighted and unweighted graphs,
- graph-generation seeds `0,...,9`,
- `k = 20, 200`,
- all four algorithms,
- 3 repetitions.

This corresponds to **960 individual algorithm runs**.

The selected configurations use the same algorithms, parameters, datasets,
repetitions, and aggregation procedure as the corresponding subfigures in the paper.

#### Light Real-World Reproduction

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae light_real
```

This downloads, prepares and evaluates three representative real-world
datasets:

- DBLP,
- YouTube,
- libimseti.

Their `k` values and execution modes are those stated in the paper. The profile
executes **141 individual algorithm runs**.

#### Combined Light Reproduction

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae light
```

This runs `light_synthetic` followed by `light_real`, for a total of
**1101 individual algorithm runs**.

We recommend this profile as the main manageable reproduction of the artifact
when the complete experiment suite is too expensive.

#### Complete Synthetic Reproduction

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae full_synthetic
```

This prepares all synthetic datasets and executes the experiments of the paper.

#### Complete Real-World Reproduction

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae full_real
```

This prepares all real-world datasets and executes the experiments of the paper.

#### Complete Reproduction

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae full
```

This prepares all required datasets and executes the complete experimental sweep.

**Warning:** This is only intended for machines with substantial memory, disk space, CPU resources, and available
running time (multiple weeks). The `light` profiles are provided specifically to permit
evaluation on more modest resources.

### Resuming Interrupted Experiments

Long-running experiments can be resumed with `--resume`. For example:

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae light_synthetic --resume
```

Dataset preparation is cache-aware, so datasets that have already been
prepared are reused instead of being re-generated.

For experiment execution, `--resume` preserves the existing `runs.tsv` and
skips configurations already recorded with one of the terminal statuses

```text
OK
TIMEOUT
FAIL
```

while executing configurations that are still missing.

Without `--resume`, an existing `runs.tsv` for the same experiment is
intentionally replaced.

### Experiment-to-Figure Mapping

The complete artifact is divided into thirteen experiment specifications:

| ID | Experiment | Paper output |
|---|---|---|
| P1 | Delta parameter study | Figure A.1 |
| P2 | Approximate-Gonzalez epsilon study on synthetic graphs | Figure A.2 |
| P3 | Approximate-Gonzalez epsilon study on real graphs | Figure A.3 |
| P4 | Thorup rounds-per-phase study | Figure A.4 |
| P5 | Parallel scaling on small synthetic graphs | Figure A.5 |
| P6 | Parallel scaling on large synthetic graphs | Figure A.6 |
| P7 | Parallel scaling on social networks | Figure 7.1 |
| P8 | Parallel scaling on the USA-central road network | Figure 7.2 |
| P9 | Full sweep on small synthetic graphs | Figures A.7 and A.8 |
| P10 | Full sweep on large synthetic graphs | Figures A.9 and A.10 |
| P11 | Full sweep on social networks | Figure 7.3 and Figure A.11 |
| P12 | Full sweep on road networks | Figures 7.4 and 7.5 |
| P13 | Full sweep on rating networks | Figures A.12 and A.13 |

Each experiment has a frozen specification under

```text
artifact/experiments/specs/
```

containing the parameters used for the paper experiments.

### Running an Individual Paper Experiment

An individual frozen experiment can be executed with

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae experiment <experiment-id>
```

For example:

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  kcenter-ae experiment p9_full_sweep_small_synthetic
```

The available experiment IDs are:

```text
p1_delta
p2_approx_epsilon_synthetic
p3_approx_epsilon_real
p4_thorup_rpp
p5_parallel_small_synthetic
p6_parallel_large_synthetic
p7_parallel_social
p8_parallel_road
p9_full_sweep_small_synthetic
p10_full_sweep_large_synthetic
p11_full_sweep_social
p12_full_sweep_roads
p13_full_sweep_ratings
```

The `experiment` mode uses the frozen paper specification.

Note that running an individual experiment directly assumes that its required
datasets have already been prepared.

### Experiment Batches

Related experiments can also be executed as batches to further simplify to reproduce the papers results:

```bash
docker run --rm ... kcenter-ae batch parameter_choices [--dry-run] [--resume]
docker run --rm ... kcenter-ae batch parallel_scaling [--dry-run] [--resume]
docker run --rm ... kcenter-ae batch full_sweep_synthetic [--dry-run] [--resume]
docker run --rm ... kcenter-ae batch full_sweep_real [--dry-run] [--resume]
```

As with individual experiments, the datasets required by a batch must already
be prepared.

### Custom Experiments

The same execution engine can be used for smaller or modified experiments
without changing the frozen paper specifications.

Use

```text
custom <experiment-id>
```

as the artifact command and provide the desired overrides as environment
variables using Docker's `-e` option.

Supported overrides are:

```text
REPETITIONS
BASE_SEED
TIMEOUT_SECONDS
THREAD_POINTS
THREAD_COUNTS
K_VALUES
DELTA_VALUES
EPSILON_VALUES
RPP_VALUES
ALGORITHMS
DATASETS
RESULTS_DIR
```

For example, to execute only one repetition of experiment P9 on a particular graph:

```bash
docker run --rm \
  --mount type=bind,src="$PWD/inputs",dst=/artifact/inputs \
  --mount type=bind,src="$PWD/artifact-results",dst=/artifact/artifact-results \
  -e REPETITIONS=1 \
  -e DATASETS='er_n100000_d16_seed0_w.adj' \
  kcenter-ae custom p9_full_sweep_small_synthetic
```

Custom mode changes only the requested dimensions; all remaining settings are
inherited from the corresponding paper specification.

Custom runs are stored separately from official paper runs unless
`RESULTS_DIR` is explicitly overridden.

#### Synthetic Graphs

The synthetic experiments use Erdős--Rényi graphs generated by the supplied

```text
utils/simple_er_generator.cc
```

utility.

The preparation pipeline is

```text
simple-er-generator
  -> edge lists
  -> snap-converter (provided by GBBS)
  -> temporary GBBS adjacency graph
  -> clean-csr-graph (our preprocessing described in the paper)
  -> experiment-ready graph
```

The small synthetic collection uses

- `n = 100,000`,
- `rho = m/n` in `{2,4,8,16,32,64}`,
- graph seeds `0,...,9`,
- weighted and unweighted variants.

The large collection uses

- `n = 10,000,000`,
- the same six densities,
- graph seed `0`,
- weighted and unweighted variants.

Weighted synthetic edges receive uniformly distributed positive integer
weights from `1` to `10000`.

The `n` and `m = n * rho` values are generation parameters. Isolated
vertices are removed during common preprocessing, so the final number of
vertices can be slightly smaller.

#### Real-World Graphs

The artifact prepares the following real-world datasets:

- DBLP
- YouTube
- LiveJournal
- Orkut
- Twitter
- Friendster
- USA-central road network
- USA-full road network
- libimseti
- MovieLens
- Yahoo Song

The dataset-specific download URLs, transformations, expected graph sizes, and
validation checks are encoded in

```text
artifact/scripts/prepare_real_datasets.sh
```

The principal sources are SNAP, the 9th DIMACS Shortest-Path Implementation
Challenge, KONECT and the Network Repository.

Each prepared real-world graph is validated against its expected post-cleanup
vertex and edge counts before being used by the artifact.

#### Rating Network weight transformations

For the rating networks, larger ratings are transformed into smaller positive
edge weights before common graph cleanup.

The transformations used by the artifact are

```text
libimseti: w = 11  - r
MovieLens: w = 11  - 2r
Yahoo Song: w = 101 - r
```

where `r` denotes the original rating.

MovieLens and Yahoo Song are bipartite networks. Their two vertex namespaces
are kept disjoint during conversion before the resulting graph is compactly
renumbered by the common preprocessing step.

The exact transformation procedures are implemented in

```text
artifact/scripts/prepare_real_datasets.sh
scripts/rating_weights_to_distances.py
```

### Common Graph Preprocessing

All experiment graphs are converted to symmetric GBBS adjacency graphs and
passed through the common cleaner.

Preprocessing

- removes self-loops,
- removes isolated vertices,
- removes duplicate/parallel edges,
- renumbers the remaining vertices compactly, and
- produces sorted symmetric adjacency lists.

For weighted graphs, duplicate edges retain the minimum weight.

The common cleaner is implemented in

```text
utils/clean_csr_graph.cc
```

and is invoked automatically by the dataset-preparation scripts.

### Repetitions, Random Seeds, and Timeouts

The main paper experiments use **3 repetitions** for each fixed experiment
configuration.

The parameter-choice experiments P1--P4 use **1 repetition** by default.

Algorithm seeds are deterministic:

```text
seed(repetition) = 42 + repetition - 1
```

Thus the three main-experiment repetitions use seeds `42`, `43`, and `44`.

The graph-generation seed and algorithm seed are separate. In particular,
the ten small synthetic graph instances use graph-generation seeds `0,...,9`,
while repeated executions of an algorithm use the algorithm seeds above.

Each individual algorithm run has a timeout of **10800 seconds (3 hours)**.
A timeout is recorded in the result table rather than aborting the complete
experiment family.

### Aggregation

For ordinary experiments, reported values are medians over the repetitions of
a fixed experiment configuration.

For the small synthetic experiments that use ten independently generated
graphs, aggregation is hierarchical:

1. compute the median over repetitions for each fixed generated graph;
2. compute the median of those per-graph medians over the ten graph seeds.

### Results and Generated Figures

Each experiment stores its raw and processed results below

```text
artifact-results/
```

Official individual paper experiments use

```text
artifact-results/experiments/<experiment-id>/
```

and the high-level light profiles use directories below

```text
artifact-results/profiles/
```

The main per-run table is

```text
runs.tsv
```

and records information including

- graph and graph type,
- algorithm,
- `k`,
- execution mode,
- thread count,
- algorithm parameters,
- repetition and seed,
- running time,
- number of centers,
- solution radius,
- unreachable-vertex count,
- timeout/failure status, and
- raw-log location.

Raw output from individual algorithm executions is retained below

```text
raw/
```

Postprocessing creates files below

```text
summary/
```

including, where applicable,

```text
per_graph.tsv
aggregated.tsv
paper_results.tsv
```

as well as the reconstructed figures.

Figures are generated in both PDF and PNG format.

For experiments requiring solution-quality comparisons, the paper-facing
results express solution radius relative to Gonzalez on the same graph and
`k`.

For P10 and P11, the paper-facing derivation also selects the faster usable
Abboud execution mode when both single-core and parallel measurements are
present, matching the comparison used for the paper.

### Parallel and Single-Core Runs

Parallel experiment points set the number of Parlay workers through
`PARLAY_NUM_THREADS`.

Single-core experiment points use the algorithms' explicit single-core mode
and set

```text
PARLAY_NUM_THREADS=1
```

They are therefore executions of the sequential implementation path rather
than parallel runs with an unrestricted worker pool.

### Direct Use Without Docker

The artifact scripts can also be executed directly on a compatible Linux
system. For example:

```bash
./artifact/run.sh build
./artifact/run.sh smoke
./artifact/run.sh light_synthetic
./artifact/run.sh light_real
./artifact/run.sh light
```

However, Docker is the recommended evaluation environment because it provides
the software versions and dependencies used by the artifact automatically.

The complete host-side command reference is available with

```bash
./artifact/run.sh help
```

and the corresponding Docker command is

```bash
docker run --rm kcenter-ae help
```
