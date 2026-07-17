// This file provides an implementation of the dynamic (2+epsilon) approximate k-center algorithm by Forster and Skarlatos [SODA 2024].

#pragma once

#include <limits>
#include <utility>

#include "gbbs/gbbs.h"
#include "parlay/primitives.h"
#include "parlay/random.h"
#include "parlay/sequence.h"
#include "benchmarks/PositiveWeightSSSP/RR/RR.h"

namespace gbbs {

template <class Graph>
parlay::sequence<uintE> Forster(Graph& G, uintE k, double delta,
                                size_t num_buckets = 128,
                                bool choose_random_first = true,
                                uintE first_center = 0,
                                uint64_t seed = 12345,
                                double dist_cap = std::numeric_limits<double>::infinity(),
                                bool single_core = false,
                                RRSPGMode spg_mode = RRSPGMode::Rebuild,
                                double spg_threshold = 0.25) {
  using Distance = typename RR<Graph>::Distance;
  const size_t n = G.n;

  if (k == 0 || n == 0) return parlay::sequence<uintE>();

  RR<Graph> rr(G, 0 /*dummy source, unused in empty mode*/, delta,
             num_buckets, dist_cap, single_core,
             spg_mode, spg_threshold);
  rr.initialize_empty();

  parlay::sequence<uintE> centers;
  centers.reserve(k);

  uintE first;
  if (choose_random_first) {
    parlay::random rng(seed);
    uint64_t r = rng.ith_rand(0);
    first = static_cast<uintE>(r % n);
  } else {
    first = first_center;
  }

  centers.push_back(first);
  rr.insert_center(first);

  while (centers.size() < k) {
    const auto& dist = rr.distances();

    auto max_pair_monoid = parlay::make_monoid(
        [](auto a, auto b) { return (a.second > b.second) ? a : b; },
        std::make_pair(size_t{0}, std::numeric_limits<Distance>::lowest()));

    auto farthest = parlay::reduce(
        parlay::tabulate(n, [&](size_t i) {
          Distance d = dist[i];
          return std::make_pair(i, d);
        }),
        max_pair_monoid);

    uintE farthest_vtx = static_cast<uintE>(farthest.first);

    // Avoid duplicate centers
    bool already_present = false;
    for (size_t i = 0; i < centers.size(); i++) {
      if (centers[i] == farthest_vtx) {
        already_present = true;
        break;
      }
    }

    if (already_present) break;

    centers.push_back(farthest_vtx);
    rr.insert_center(farthest_vtx);
  }

  return centers;
}

// Variant that also returns the final maintained distances.
template <class Graph>
std::pair<parlay::sequence<uintE>,
          parlay::sequence<typename RR<Graph>::Distance>>
ForsterWithDistances(Graph& G, uintE k, double delta,
                     size_t num_buckets = 128,
                     bool choose_random_first = true,
                     uintE first_center = 0,
                     uint64_t seed = 12345,
                     double dist_cap = std::numeric_limits<double>::infinity(),
                     bool single_core = false,
                     RRSPGMode spg_mode = RRSPGMode::Rebuild,
                     double spg_threshold = 0.25) {
  using Distance = typename RR<Graph>::Distance;
  const size_t n = G.n;

  if (k == 0 || n == 0) {
    return {parlay::sequence<uintE>(), parlay::sequence<Distance>()};
  }

  RR<Graph> rr(G, 0 /*dummy source, unused in empty mode*/, delta,
             num_buckets, dist_cap, single_core,
             spg_mode, spg_threshold);
  rr.initialize_empty();

  parlay::sequence<uintE> centers;
  centers.reserve(k);

  uintE first;
  if (choose_random_first) {
    parlay::random rng(seed);
    uint64_t r = rng.ith_rand(0);
    first = static_cast<uintE>(r % n);
  } else {
    first = first_center;
  }

  centers.push_back(first);
  rr.insert_center(first);

  while (centers.size() < k) {
    const auto& dist = rr.distances();

    auto max_pair_monoid = parlay::make_monoid(
        [](auto a, auto b) { return (a.second > b.second) ? a : b; },
        std::make_pair(size_t{0}, std::numeric_limits<Distance>::lowest()));

    auto farthest = parlay::reduce(
        parlay::tabulate(n, [&](size_t i) {
          Distance d = dist[i];
          return std::make_pair(i, d);
        }),
        max_pair_monoid);

    uintE farthest_vtx = static_cast<uintE>(farthest.first);

    bool already_present = false;
    for (size_t i = 0; i < centers.size(); i++) {
      if (centers[i] == farthest_vtx) {
        already_present = true;
        break;
      }
    }

    if (already_present) break;

    centers.push_back(farthest_vtx);
    rr.insert_center(farthest_vtx);
  }

  auto final_dist = parlay::sequence<Distance>::from_function(
      n, [&](size_t i) { return rr.distances()[i]; });

  std::cout << "spg_rebuild_calls = "
            << rr.num_spg_rebuild_calls() << std::endl;
  std::cout << "spg_local_calls = "
            << rr.num_spg_local_calls() << std::endl;
  std::cout << "spg_hybrid_rebuild_calls = "
            << rr.num_spg_hybrid_rebuild_calls() << std::endl;
  std::cout << "spg_hybrid_local_calls = "
            << rr.num_spg_hybrid_local_calls() << std::endl;
  std::cout << "spg_total_affected_vertices = "
            << rr.total_affected_vertices() << std::endl;
  std::cout << "spg_avg_affected_vertices = "
            << rr.avg_affected_vertices() << std::endl;
  std::cout << "spg_max_affected_vertices = "
            << rr.max_affected_vertices() << std::endl;

  return {centers, final_dist};
}

}  // namespace gbbs