// This file provides a sequential implementation of a Dijkstra variant
// that can use a previously computed distance array.
//
// Optionally, multiplicative alpha-bucket bookkeeping can be enabled
// by passing a pointer. In that mode, we snapshot the
// old distances, mark changed vertices during the distance update run and update
// bucket memberships after.

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <limits>
#include <queue>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

#include "gbbs/gbbs.h"
#include "benchmarks/PositiveWeightSSSP/common/AlphaBucketState.h"

namespace gbbs {

template <class Graph, class Distance>
void DijkstraRepairImpl(
    Graph& G, sequence<Distance>& dist,
    const sequence<std::pair<uintE, Distance>>& seeds,
    double dist_cap = std::numeric_limits<double>::infinity(),
    sequence<uint8_t>* changed = nullptr) {
  using W = typename Graph::weight_type;
  constexpr Distance kMaxWeight = std::numeric_limits<Distance>::max();

  const Distance CAP =
      (std::isinf(dist_cap) ? kMaxWeight : static_cast<Distance>(dist_cap));

  const size_t n = G.n;

  if (dist.size() != n) {
    std::cout << "DijkstraRepair: dist.size() != G.n" << std::endl;
    exit(-1);
  }

  if (changed != nullptr && changed->size() != n) {
    std::cout << "DijkstraRepair: changed.size() != G.n" << std::endl;
    exit(-1);
  }

  using PQEntry = std::pair<Distance, uintE>;
  std::priority_queue<PQEntry, std::vector<PQEntry>, std::greater<PQEntry>> pq;

  for (size_t i = 0; i < seeds.size(); ++i) {
    const auto& [v, new_dist] = seeds[i];
    if (new_dist > CAP) continue;
    if (new_dist < dist[v]) {
      dist[v] = new_dist;
      pq.push({new_dist, v});
      if (changed != nullptr) {
        (*changed)[v] = static_cast<uint8_t>(1);
      }
    }
  }

  while (!pq.empty()) {
    auto [du, u] = pq.top();
    pq.pop();

    // Skip stale priority-queue entries.
    if (du != dist[u]) continue;
    if (du > CAP) continue;

    auto map_f = [&](const uintE& s, const uintE& d, const W& wgh) {
      Distance w;
      if constexpr (std::is_same<W, gbbs::empty>::value) {
        w = static_cast<Distance>(1);
      } else {
        w = static_cast<Distance>(wgh);
      }

      if (dist[s] > kMaxWeight - w) return;

      Distance nd = dist[s] + w;
      if (nd > CAP) return;

      if (nd < dist[d]) {
        dist[d] = nd;
        pq.push({nd, d});
        if (changed != nullptr) {
          (*changed)[d] = static_cast<uint8_t>(1);
        }
      }
    };

    G.get_vertex(u).out_neighbors().map(map_f, false);
  }
}

template <class Graph, class Distance>
sequence<uintE> DijkstraRepairAffected(
    Graph& G,
    sequence<Distance>& dist,
    const sequence<std::pair<uintE, Distance>>& seeds,
    double dist_cap = std::numeric_limits<double>::infinity()) {
  const size_t n = G.n;
  auto changed = sequence<uint8_t>(n, static_cast<uint8_t>(0));

  DijkstraRepairImpl(G, dist, seeds, dist_cap, &changed);

  return parlay::filter(
      parlay::tabulate(n, [&](size_t i) { return static_cast<uintE>(i); }),
      [&](uintE v) { return changed[v] != 0; });
}

template <class Graph, class Distance>
void DijkstraRepair(
    Graph& G, sequence<Distance>& dist,
    const sequence<std::pair<uintE, Distance>>& seeds,
    double dist_cap = std::numeric_limits<double>::infinity(),
    AlphaBucketState<Distance>* alpha_state = nullptr) {
  const size_t n = G.n;

  if (alpha_state == nullptr) {
    DijkstraRepairImpl(G, dist, seeds, dist_cap, nullptr);
    return;
  }

  auto old_dist = sequence<Distance>::from_function(n, [&](size_t i) {
    return dist[i];
  });
  auto changed = sequence<uint8_t>(n, static_cast<uint8_t>(0));

  DijkstraRepairImpl(G, dist, seeds, dist_cap, &changed);

  auto changed_vertices = parlay::filter(
      parlay::tabulate(n, [&](size_t i) { return static_cast<uintE>(i); }),
      [&](uintE v) { return changed[v] != 0; });

  for (size_t i = 0; i < changed_vertices.size(); ++i) {
    uintE v = changed_vertices[i];
    if (alpha_state->is_center[v]) continue;
    if (dist[v] < old_dist[v]) {
      alpha_state->update_vertex_distance(v, dist[v]);
    }
  }
}

template <class Graph, class Distance>
void DijkstraRepair(
    Graph& G, sequence<Distance>& dist,
    const sequence<uintE>& active_vertices,
    double dist_cap = std::numeric_limits<double>::infinity(),
    AlphaBucketState<Distance>* alpha_state = nullptr) {
  constexpr Distance kMaxWeight = std::numeric_limits<Distance>::max();

  auto seeds = sequence<std::pair<uintE, Distance>>::from_function(
      active_vertices.size(), [&](size_t i) {
        uintE v = active_vertices[i];
        return std::make_pair(v, dist[v]);
      });

  for (size_t i = 0; i < active_vertices.size(); ++i) {
    uintE v = active_vertices[i];
    dist[v] = kMaxWeight;
  }

  DijkstraRepair(G, dist, seeds, dist_cap, alpha_state);
}

template <class Graph, class Distance>
void DijkstraRepair(
    Graph& G, sequence<Distance>& dist, uintE src,
    double dist_cap = std::numeric_limits<double>::infinity(),
    AlphaBucketState<Distance>* alpha_state = nullptr) {
  auto active = sequence<uintE>(1, src);
  DijkstraRepair(G, dist, active, dist_cap, alpha_state);
}

}  // namespace gbbs