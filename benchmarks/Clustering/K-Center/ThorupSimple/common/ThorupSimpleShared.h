#pragma once

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdint>
#include <limits>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

#include "gbbs/gbbs.h"
#include "benchmarks/BFS/BFSdist/BFSdist.h"
#include "benchmarks/BFS/BFSdist/BFSdistSeq.h"
#include "benchmarks/BFS/BFSdist/BFSdistMultiSources.h"
#include "benchmarks/BFS/BFSdist/BFSdistSeqMultiSources.h"
#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaStepping.h"
#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaSteppingMultiSources.h"
#include "benchmarks/PositiveWeightSSSP/Dijkstra/Dijkstra.h"
#include "benchmarks/PositiveWeightSSSP/Dijkstra/DijkstraMultiSources.h"
#include "parlay/sequence.h"

namespace gbbs {
namespace thorup_simple {

inline double seconds_since_shared(
    const std::chrono::steady_clock::time_point& start) {
  using namespace std::chrono;
  return duration_cast<duration<double>>(steady_clock::now() - start).count();
}

template <class Distance>
struct ThorupSimpleParams {
  double shrink_factor = 2.0;
  double rounds_per_phase_factor = 8.0;
  double sample_multiplier = 1.0;

  double ds_delta = 1.0;
  size_t num_buckets = 32;
  bool single_core = false;

  bool use_two_r = true;
  uint64_t seed = 12345;
  bool verbose = false;
};

template <class Graph>
using ThorupDistance =
    typename std::conditional<std::is_same<typename Graph::weight_type,
                                           gbbs::empty>::value,
                              uintE,
                              typename Graph::weight_type>::type;

template <class Graph>
struct ThorupSimpleResult {
  using distance_type = ThorupDistance<Graph>;

  parlay::sequence<uintE> centers;
  distance_type radius;
  size_t rounds = 0;
  size_t phases = 0;
  size_t fallback_calls = 0;
  size_t fallback_added_centers = 0;
  size_t fallback_initial_alive = 0;
  bool feasible = true;
};

inline uint64_t splitmix64(uint64_t x) {
  x += 0x9e3779b97f4a7c15ULL;
  x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
  x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
  return x ^ (x >> 31);
}

inline size_t ceil_nat_log(size_t n) {
  if (n <= 1) return 1;
  return static_cast<size_t>(std::ceil(std::log(static_cast<double>(n))));
}

inline size_t rounds_per_phase_from_factor(size_t n, double rpp_factor) {
  (void)n;

  if (rpp_factor <= 0.0) return 1;

  return std::max<size_t>(
      1,
      static_cast<size_t>(std::ceil(rpp_factor)));
}

inline size_t ceil_log2_size(size_t n) {
  if (n <= 1) return 1;

  size_t k = 0;
  size_t x = 1;
  while (x < n) {
    x <<= 1;
    ++k;
  }
  return k;
}

template <class Distance>
inline Distance infinity() {
  return std::numeric_limits<Distance>::max();
}

inline bool bernoulli_from_hash(uintE v, uint64_t round_seed, double p) {
  if (p >= 1.0) return true;
  if (p <= 0.0) return false;

  constexpr long double U64_MAX_LD =
      static_cast<long double>(std::numeric_limits<uint64_t>::max());

  uint64_t h = splitmix64(static_cast<uint64_t>(v) ^ round_seed);
  long double threshold = p * U64_MAX_LD;
  return static_cast<long double>(h) <= threshold;
}

template <class Graph>
parlay::sequence<typename Graph::edge> extract_unique_undirected_edges(Graph& G) {
  using W = typename Graph::weight_type;
  using edge = typename Graph::edge;

  std::vector<edge> edges;
  edges.reserve(G.m / 2 + 1);

  for (uintE u = 0; u < G.n; ++u) {
    auto map_f = [&](const uintE& src, const uintE& v, const W& w) {
      if (src <= v) {
        edges.emplace_back(src, v, w);
      }
    };
    G.get_vertex(u).out_neighbors().map(map_f, false);
  }

  return parlay::sequence<edge>(edges.begin(), edges.end());
}

template <class W>
using TempSymGraph = gbbs::symmetric_graph<gbbs::symmetric_vertex, W>;

template <class Graph>
TempSymGraph<typename Graph::weight_type> build_augmented_graph_with_supersource(
    const parlay::sequence<typename Graph::edge>& base_edges,
    size_t n,
    const parlay::sequence<uintE>& sources) {
  using W = typename Graph::weight_type;
  using edge = std::tuple<uintE, uintE, W>;

  const uintE s_star = static_cast<uintE>(n);
  parlay::sequence<edge> edges_aug(base_edges.size() + sources.size());

  parallel_for(0, base_edges.size(), [&](size_t i) {
    edges_aug[i] = base_edges[i];
  });

  parallel_for(0, sources.size(), [&](size_t i) {
    edges_aug[base_edges.size() + i] =
        std::make_tuple(s_star, sources[i], W{});
  });

  return TempSymGraph<W>::from_edges(edges_aug, n + 1);
}

template <class Graph>
parlay::sequence<ThorupDistance<Graph>> set_distances(
    const parlay::sequence<typename Graph::edge>& base_edges,
    Graph& G,
    const parlay::sequence<uintE>& sources,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params,
    ThorupDistance<Graph> dist_cap = infinity<ThorupDistance<Graph>>()) {
  using W = typename Graph::weight_type;
  using Distance = ThorupDistance<Graph>;

  if (sources.empty()) {
    return parlay::sequence<Distance>(G.n, infinity<Distance>());
  }

  const auto setdist_start = std::chrono::steady_clock::now();

  if constexpr (std::is_same<W, gbbs::empty>::value) {
    double bfs_cap =
        (dist_cap == infinity<Distance>())
            ? std::numeric_limits<double>::infinity()
            : static_cast<double>(dist_cap);

    const auto sssp_start = std::chrono::steady_clock::now();

    auto dist =
        params.single_core
            ? BFSdistSeqMultiSources(G, sources, bfs_cap, /*verbose=*/false)
            : BFSdistMultiSources(G, sources, bfs_cap, /*verbose=*/false);

    const double sssp_sec = seconds_since_shared(sssp_start);

    if (params.verbose) {
      std::cout << "[ThorupSimple][set_distances]"
                << " graph_type=unweighted"
                << (params.single_core
                      ? " mode=single_core_multisource"
                      : " mode=parallel_multisource")
                << " sources=" << sources.size()
                << " cap=" << dist_cap
                << " build_sec=0"
                << " sssp_sec=" << sssp_sec
                << " copy_sec=0"
                << " total_sec=" << seconds_since_shared(setdist_start)
                << std::endl;
    }

    return dist;
  } else {
    double sssp_cap =
        (dist_cap == infinity<Distance>())
            ? std::numeric_limits<double>::infinity()
            : static_cast<double>(dist_cap);

    const auto sssp_start = std::chrono::steady_clock::now();

    auto dist =
        params.single_core
            ? DijkstraMultiSources(G, sources, sssp_cap, /*verbose=*/false)
            : DeltaSteppingMultiSources(G,
                                        sources,
                                        params.ds_delta,
                                        params.num_buckets,
                                        sssp_cap,
                                        /*verbose=*/false);

    const double sssp_sec = seconds_since_shared(sssp_start);

    if (params.verbose) {
      std::cout << "[ThorupSimple][set_distances]"
                << " graph_type=weighted"
                << (params.single_core
                      ? " mode=single_core_multisource"
                      : " mode=parallel_multisource")
                << " sources=" << sources.size()
                << " cap=" << dist_cap
                << " build_sec=0"
                << " sssp_sec=" << sssp_sec
                << " copy_sec=0"
                << " total_sec=" << seconds_since_shared(setdist_start)
                << std::endl;
    }

    return dist;
  }
}

}  // namespace thorup_simple
}  // namespace gbbs