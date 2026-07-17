// This file provides an implementation of the alpha-approximate Gonzalez
// algorithm by Abboud et al. [SOSA 2023].

#pragma once

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <random>
#include <type_traits>
#include <utility>
#include <vector>

#include "gbbs/gbbs.h"

#include "benchmarks/BFS/BFSdist/BFSdistRepair.h"
#include "benchmarks/BFS/BFSdist/BFSdistRepairSeq.h"

#include "benchmarks/Clustering/K-Center/Gonzalez/common/KCenterResult.h"

#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaSteppingRepair.h"
#include "benchmarks/PositiveWeightSSSP/Dijkstra/DijkstraRepair.h"

namespace gbbs {

template <class Graph, class Distance>
KCenterResult<Distance> ApproximateGonzalez(
    Graph& G, size_t k, double epsilon, double delta,
    size_t num_buckets = 128,
    double dist_cap = std::numeric_limits<double>::infinity(),
    long seed = -1,
    bool verbose = false,
    bool single_core = false) {
  using W = typename Graph::weight_type;

  constexpr Distance kMaxWeight = std::numeric_limits<Distance>::max();
  const size_t n = G.n;

  if (k == 0 || n == 0) {
    return {sequence<uintE>(), static_cast<Distance>(0), n};
  }

  if (epsilon <= 0.0) {
    std::cout << "ApproximateGonzalez: epsilon must be > 0" << std::endl;
    exit(-1);
  }

  const double alpha = 1.0 + 0.5 * epsilon;

  const double D_bound = static_cast<double>(n) / epsilon;
  const double R = static_cast<double>(n) * D_bound;
  const size_t B =
      std::max<size_t>(1, static_cast<size_t>(
                              std::ceil(std::log(R) / std::log(alpha))));

  if (verbose) {
    std::cout << "### ApproximateGonzalez internal settings\n";
    std::cout << "### alpha = " << alpha << "\n";
    std::cout << "### B = " << B << "\n";
    std::cout << "### ------------------------------------\n";
  }

  auto dist = sequence<Distance>(n, kMaxWeight);

  AlphaBucketState<Distance> alpha_state(n, alpha, B, kMaxWeight);
  alpha_state.initialize_all_unreachable();

  uint64_t actual_seed;
  if (seed >= 0) {
    actual_seed = static_cast<uint64_t>(seed);
  } else {
    actual_seed = static_cast<uint64_t>(
        std::chrono::high_resolution_clock::now().time_since_epoch().count());
  }

  parlay::random rng(actual_seed);
  size_t rng_counter = 0;

  sequence<uintE> centers(k);

  size_t bmax = B;
  size_t num_centers = 0;

  while (num_centers < k) {
    while (bmax >= 1 && alpha_state.bucket_empty(bmax)) {
      --bmax;
    }

    if (bmax == 0) break;

    auto& bucket = alpha_state.H[bmax];

    uint64_t r = rng.ith_rand(rng_counter++);
    uintE v = bucket[static_cast<size_t>(r % bucket.size())];

    alpha_state.set_center(v);
    centers[num_centers++] = v;

    if (verbose) {
      std::cout << "Round " << num_centers
                << ": picked v = " << v
                << " from bucket " << bmax
                << " (size = " << (bucket.size() + 1) << ")\n";
    }

    if constexpr (std::is_same<W, gbbs::empty>::value) {
      static_assert(std::is_same<Distance, uintE>::value,
                    "Unweighted ApproximateGonzalez expects Distance = uintE");

      auto seeds = sequence<std::pair<uintE, uintE>>(1);
      seeds[0] = std::make_pair(v, static_cast<uintE>(0));

      if (single_core) {
        BFSdistRepairSeq(G, dist, seeds, dist_cap, &alpha_state);
      } else {
        BFSdistRepair(G, dist, seeds, dist_cap, &alpha_state);
      }
    } else {
      auto seeds = sequence<std::pair<uintE, Distance>>(1);
      seeds[0] = std::make_pair(v, static_cast<Distance>(0));

      if (single_core) {
        DijkstraRepair(G, dist, seeds, dist_cap, &alpha_state);
      } else {
        DeltaSteppingRepair(G, dist, seeds, delta, num_buckets, dist_cap,
                            &alpha_state);
      }
    }
  }

  sequence<uintE> out(num_centers);
  parallel_for(0, num_centers, [&](size_t i) { out[i] = centers[i]; });

  size_t unreachable_vertices = 0;
  Distance max_dist_to_centers = static_cast<Distance>(0);

  for (size_t i = 0; i < n; ++i) {
    if (dist[i] == kMaxWeight) {
      unreachable_vertices++;
    } else {
      max_dist_to_centers = std::max(max_dist_to_centers, dist[i]);
    }
  }

  return {std::move(out), max_dist_to_centers, unreachable_vertices};
}

}  // namespace gbbs