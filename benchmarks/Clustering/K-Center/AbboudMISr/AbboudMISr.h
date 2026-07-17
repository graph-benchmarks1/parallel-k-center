// This file provides an implementation of the maximal distance-r independent set algorithm
// by Abboud et al [SOSA 2023].

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <type_traits>
#include <utility>

#include "gbbs/gbbs.h"

#include "AbboudMISrFeasibility.h"
#include "benchmarks/BFS/BFSdist/BFSdistRepair.h"
#include "benchmarks/BFS/BFSdist/BFSdistRepairSeq.h"
#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaSteppingRepair.h"
#include "benchmarks/PositiveWeightSSSP/Dijkstra/DijkstraRepair.h"

#include "parlay/primitives.h"
#include "parlay/random.h"
#include "parlay/sequence.h"

namespace gbbs {

template <class Distance>
struct AbboudMISrResult {
  parlay::sequence<uintE> centers;
  double radius = 0.0;
  size_t iters_exp_search = 0;
  size_t iters_binary_search = 0;
  Distance max_dist_to_centers = static_cast<Distance>(0);
  size_t unreachable_vertices = 0;
};

template <class Graph>
inline std::pair<parlay::sequence<uintE>, bool>
AbboudMISr_feasible(Graph& G, double r, size_t k, double delta,
                    size_t num_buckets, bool permute, uint64_t seed,
                    bool uniform_random = true,
                    bool single_core = false) {
  auto centers = AbboudMISrFeasibility(G, r, delta, num_buckets, permute, seed,
                            uniform_random, single_core,
                            /*abort_after_k=*/k);
  bool ok = (centers.size() <= k);
  return {std::move(centers), ok};
}

template <class Graph>
inline std::pair<
    typename std::conditional<
        std::is_same<typename Graph::weight_type, gbbs::empty>::value,
        uintE,
        float>::type,
    size_t>
AbboudMISr_compute_solution_quality(Graph& G,
                                    const parlay::sequence<uintE>& centers,
                                    double delta,
                                    size_t num_buckets,
                                    bool single_core = false) {
  using W = typename Graph::weight_type;
  using Distance =
      typename std::conditional<std::is_same<W, gbbs::empty>::value,
                                uintE, float>::type;

  const Distance kInf = std::numeric_limits<Distance>::max();

  if (G.n == 0) {
    return {static_cast<Distance>(0), 0};
  }

  if (centers.empty()) {
    return {static_cast<Distance>(0), G.n};
  }

  parlay::sequence<Distance> dist(G.n, kInf);

  auto seeds = parlay::sequence<std::pair<uintE, Distance>>::from_function(
      centers.size(), [&](size_t i) {
        return std::make_pair(centers[i], static_cast<Distance>(0));
      });

  if constexpr (std::is_same<W, gbbs::empty>::value) {
    if (single_core) {
      BFSdistRepairSeq(G, dist, seeds);
    } else {
      BFSdistRepair(G, dist, seeds);
    }
  } else {
    if (single_core) {
      DijkstraRepair(G, dist, seeds);
    } else {
      DeltaSteppingRepair(G, dist, seeds, delta, num_buckets);
    }
  }

  size_t unreachable_vertices = 0;
  Distance max_dist_to_centers = static_cast<Distance>(0);

  for (size_t i = 0; i < G.n; ++i) {
    if (dist[i] == kInf) {
      unreachable_vertices++;
    } else {
      max_dist_to_centers = std::max(max_dist_to_centers, dist[i]);
    }
  }

  return {max_dist_to_centers, unreachable_vertices};
}

template <class Graph>
auto AbboudMISr(Graph& G, size_t k, double delta,
                       size_t num_buckets = 128,
                       bool permute = false,
                       uint64_t seed = 27491095ULL,
                       double eps = 1e-6,
                       size_t max_exp = 64,
                       size_t max_bs = 64,
                       bool uniform_random = true,
                       bool single_core = false) {
  using W = typename Graph::weight_type;
  using Distance =
      typename std::conditional<std::is_same<W, gbbs::empty>::value,
                                uintE, float>::type;

  AbboudMISrResult<Distance> out;

  if (k == 0) {
    out.unreachable_vertices = G.n;
    return out;
  }

  if (k >= G.n) {
    out.radius = 0.0;
    out.centers = parlay::tabulate<uintE>(G.n, [&](size_t i) {
      return static_cast<uintE>(i);
    });
    out.max_dist_to_centers = static_cast<Distance>(0);
    out.unreachable_vertices = 0;
    return out;
  }

  double lo = 0.0;
  double hi = 0.0;
  parlay::sequence<uintE> centers_hi;

  {
    auto [c0, ok0] = AbboudMISr_feasible(
        G, 0.0, k, delta, num_buckets, permute, seed, uniform_random,
        single_core);
    if (ok0) {
      out.radius = 0.0;
      out.centers = std::move(c0);

      auto [max_dist, inf_count] = AbboudMISr_compute_solution_quality(
          G, out.centers, delta, num_buckets, single_core);
      out.max_dist_to_centers = max_dist;
      out.unreachable_vertices = inf_count;

      return out;
    }
    lo = 0.0;
  }

  hi = 1.0;
  size_t exp_iters = 0;
  bool found = false;

  while (exp_iters < max_exp) {
    auto [c_hi, ok_hi] = AbboudMISr_feasible(
        G, hi, k, delta, num_buckets, permute, seed, uniform_random,
        single_core);
    if (ok_hi) {
      centers_hi = std::move(c_hi);
      found = true;
      break;
    }

    lo = hi;
    hi = (hi == 0.0 ? 1.0 : hi * 2.0);
    exp_iters++;
  }

  if (!found) {
    double trial = std::pow(2.0, static_cast<int>(max_exp));
    auto [c_last, ok_last] = AbboudMISr_feasible(
        G, trial, k, delta, num_buckets, permute, seed, uniform_random,
        single_core);

    if (!ok_last) {
      out.radius = std::numeric_limits<double>::infinity();
      out.centers = std::move(c_last);
      out.iters_exp_search = exp_iters + 1;
      out.iters_binary_search = 0;

      auto [max_dist, inf_count] = AbboudMISr_compute_solution_quality(
          G, out.centers, delta, num_buckets, single_core);
      out.max_dist_to_centers = max_dist;
      out.unreachable_vertices = inf_count;

      return out;
    }

    lo = hi;
    hi = trial;
    centers_hi = std::move(c_last);
  }

  out.iters_exp_search = exp_iters;

  size_t bs_iters = 0;
  parlay::sequence<uintE> best_centers = std::move(centers_hi);
  double best_r = hi;

  while (bs_iters < max_bs) {
    if (hi <= lo * (1.0 + eps)) break;

    double mid = (lo + hi) / 2.0;
    auto [c_mid, ok_mid] = AbboudMISr_feasible(
        G, mid, k, delta, num_buckets, permute, seed, uniform_random,
        single_core);

    if (ok_mid) {
      hi = mid;
      best_centers = std::move(c_mid);
      best_r = mid;
    } else {
      lo = mid;
    }

    bs_iters++;
  }

  out.radius = best_r;
  out.centers = std::move(best_centers);
  out.iters_binary_search = bs_iters;

  auto [max_dist, inf_count] = AbboudMISr_compute_solution_quality(
      G, out.centers, delta, num_buckets, single_core);
  out.max_dist_to_centers = max_dist;
  out.unreachable_vertices = inf_count;

  return out;
}

}  // namespace gbbs
