// This file provides the feasibility check of a certain radius for the algorithm of Abboud et al.

#pragma once

#include <cstdint>
#include <limits>
#include <type_traits>
#include <utility>

#include "gbbs/gbbs.h"
#include "benchmarks/BFS/BFSdist/BFSdistRepair.h"
#include "benchmarks/BFS/BFSdist/BFSdistRepairSeq.h"
#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaSteppingRepair.h"
#include "benchmarks/PositiveWeightSSSP/Dijkstra/DijkstraRepair.h"
#include "parlay/primitives.h"
#include "parlay/random.h"
#include "parlay/sequence.h"

namespace gbbs {

template <class Graph>
parlay::sequence<uintE> AbboudMISrFeasibility(
    Graph& G, double r, double delta, size_t num_buckets = 128,
    bool permute = false, uint64_t seed = 27491095ULL,
    bool uniform_random = true, bool single_core = false,
    size_t abort_after_k = std::numeric_limits<size_t>::max()) {
  using W = typename Graph::weight_type;
  using vertex_id = uintE;
  using Distance =
      typename std::conditional<std::is_same<W, gbbs::empty>::value,
                                uintE, float>::type;

  const size_t n = G.n;
  const Distance kInf = std::numeric_limits<Distance>::max();
  const double cap = r;

  parlay::sequence<vertex_id> order;
  if (!uniform_random) {
    if (permute) {
      parlay::random rng(seed);
      auto keyed = parlay::tabulate(n, [&](size_t i) {
        return std::pair<uint64_t, vertex_id>(
            rng.ith_rand(i), static_cast<vertex_id>(i));
      });
      parlay::sort_inplace(keyed, [](const auto& a, const auto& b) {
        return a.first < b.first;
      });
      order = parlay::tabulate(n, [&](size_t i) { return keyed[i].second; });
    } else {
      order = parlay::tabulate(n, [&](size_t i) {
        return static_cast<vertex_id>(i);
      });
    }
  }

  parlay::sequence<uintE> centers;
  centers.reserve(n / 8 + 1);

  auto should_abort = [&]() {
    return centers.size() > abort_after_k;
  };

  auto run_repair = [&](parlay::sequence<Distance>& dist,
                        const parlay::sequence<std::pair<uintE, Distance>>& seeds) {
    if constexpr (std::is_same<W, gbbs::empty>::value) {
      if (single_core) {
        BFSdistRepairSeq(G, dist, seeds, cap);
      } else {
        BFSdistRepair(G, dist, seeds, cap);
      }
    } else {
      if (single_core) {
        DijkstraRepair(G, dist, seeds, cap);
      } else {
        DeltaSteppingRepair(G, dist, seeds, delta, num_buckets, cap);
      }
    }
  };

  parlay::sequence<Distance> dist(n, kInf);

  if (!uniform_random) {
    for (size_t idx = 0; idx < n; ++idx) {
      vertex_id v = order[idx];
      if (static_cast<double>(dist[v]) <= r) continue;

      centers.push_back(v);
      if (should_abort()) return centers;

      auto seeds = parlay::sequence<std::pair<uintE, Distance>>(1);
      seeds[0] = std::make_pair(v, static_cast<Distance>(0));

      run_repair(dist, seeds);
    }
  } else {
    auto T = parlay::tabulate(n, [&](size_t i) {
      return static_cast<vertex_id>(i);
    });

    size_t T_size = n;
    uint64_t iter = 0;

    while (T_size > 0) {
      parlay::random rng(seed + iter);
      uint64_t rnd = rng.ith_rand(0);
      size_t j = static_cast<size_t>(rnd % T_size);

      vertex_id v = T[j];

      // Remove v from T by swap-delete, exactly preserving the
      // "consider every vertex once" structure of Abboud et al.'s algorithm.
      T[j] = T[T_size - 1];
      --T_size;

      if (static_cast<double>(dist[v]) <= r) {
        ++iter;
        continue;
      }

      centers.push_back(v);
      if (should_abort()) return centers;

      auto seeds = parlay::sequence<std::pair<uintE, Distance>>(1);
      seeds[0] = std::make_pair(v, static_cast<Distance>(0));

      run_repair(dist, seeds);

      ++iter;
    }
  }

  return centers;
}

}  // namespace gbbs
