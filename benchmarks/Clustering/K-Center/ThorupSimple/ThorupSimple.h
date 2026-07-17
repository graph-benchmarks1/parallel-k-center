// This file provides an implementation of a simplified version of the (2+epsilon) approximate k-center algorithm by Thorup [ICALP 2001].
// Instead of computing Cohen's linear time estimator, we pick delta=n and perform enough iterations s.t. the algorithm
// terminates w.h.p. If a solution was not found, we shrink delta by a constant factor and repeat until delta is 
// in the (1+epsilon) regime of the optimal delta*.

#pragma once

#include <cstdint>
#include <limits>
#include <tuple>
#include <utility>
#include <vector>

#include "gbbs/gbbs.h"
#include "benchmarks/Clustering/K-Center/ThorupSimple/common/ThorupSimpleShared.h"
#include "benchmarks/Clustering/K-Center/ThorupSimple/ThorupSimpleInverse.h"
#include "parlay/sequence.h"

namespace gbbs {
namespace thorup_simple {

template <class Graph>
ThorupSimpleResult<Graph> compute_kcenter(
    Graph& G,
    size_t k,
    ThorupDistance<Graph> max_radius,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params) {
  using Distance = ThorupDistance<Graph>;

  auto base_edges = extract_unique_undirected_edges(G);

  parlay::sequence<uintE> best_centers;
  Distance best_radius = static_cast<Distance>(0);

  size_t best_rounds = 0;
  size_t best_phases = 0;
  size_t best_fallback_calls = 0;
  size_t best_fallback_added_centers = 0;
  size_t best_fallback_initial_alive = 0;
  bool found_feasible = false;

  auto test_radius = [&](Distance r) {
    size_t rounds = 0, phases = 0;
    size_t fallback_calls = 0;
    size_t fallback_added_centers = 0;
    size_t fallback_initial_alive = 0;

    auto [ok, U] =
        feasible_for_radius(G, base_edges, k, r, params,
                            &rounds,
                            &phases,
                            &fallback_calls,
                            &fallback_added_centers,
                            &fallback_initial_alive);

    if (params.verbose) {
      std::cout << "[ThorupSimple] radius=" << r
                << " feasible=" << ok
                << " centers=" << U.size()
                << " rounds=" << rounds
                << " phases=" << phases
                << " fallback_calls=" << fallback_calls
                << " fallback_added_centers=" << fallback_added_centers
                << " fallback_initial_alive=" << fallback_initial_alive
                << std::endl;
    }

    return std::make_tuple(ok,
                           std::move(U),
                           rounds,
                           phases,
                           fallback_calls,
                           fallback_added_centers,
                           fallback_initial_alive);
  };

  Distance lo = static_cast<Distance>(0);
  Distance hi = max_radius;

  if (max_radius <= static_cast<Distance>(0)) {
    hi = static_cast<Distance>(1);
    constexpr size_t kMaxExpSearchIters = 64;
    bool found_hi = false;

    for (size_t exp_iter = 0; exp_iter < kMaxExpSearchIters; ++exp_iter) {
      auto [ok, U, rounds, phases, fallback_calls,
            fallback_added_centers, fallback_initial_alive] = test_radius(hi);

      if (ok) {
        found_hi = true;
        found_feasible = true;
        best_radius = hi;
        best_centers = std::move(U);
        best_rounds = rounds;
        best_phases = phases;
        best_fallback_calls = fallback_calls;
        best_fallback_added_centers = fallback_added_centers;
        best_fallback_initial_alive = fallback_initial_alive;
        break;
      }

      lo = hi;

      if (hi > std::numeric_limits<Distance>::max() / static_cast<Distance>(2)) {
        break;
      }

      hi = static_cast<Distance>(hi * static_cast<Distance>(2));
    }

    if (!found_hi) {
      auto [ok, U, rounds, phases, fallback_calls,
            fallback_added_centers, fallback_initial_alive] = test_radius(hi);

      return ThorupSimpleResult<Graph>{
          std::move(U),
          hi,
          rounds,
          phases,
          fallback_calls,
          fallback_added_centers,
          fallback_initial_alive,
          ok};
    }
  }

  while (lo < hi) {
    Distance mid = lo + (hi - lo) / static_cast<Distance>(2);

    auto [ok, U, rounds, phases, fallback_calls,
          fallback_added_centers, fallback_initial_alive] = test_radius(mid);

    if (ok) {
      found_feasible = true;
      hi = mid;
      best_radius = mid;
      best_centers = std::move(U);
      best_rounds = rounds;
      best_phases = phases;
      best_fallback_calls = fallback_calls;
      best_fallback_added_centers = fallback_added_centers;
      best_fallback_initial_alive = fallback_initial_alive;
    } else {
      lo = mid + static_cast<Distance>(1);
    }
  }

  if (!(found_feasible && best_radius == lo)) {
  size_t final_rounds = 0, final_phases = 0;
  size_t final_fallback_calls = 0;
  size_t final_fallback_added_centers = 0;
  size_t final_fallback_initial_alive = 0;

  auto [final_ok, final_U] =
      feasible_for_radius(G, base_edges, k, lo, params,
                          &final_rounds,
                          &final_phases,
                          &final_fallback_calls,
                          &final_fallback_added_centers,
                          &final_fallback_initial_alive);

  if (params.verbose) {
    std::cout << "[ThorupSimple] radius=" << lo
              << " feasible=" << final_ok
              << " centers=" << final_U.size()
              << " rounds=" << final_rounds
              << " phases=" << final_phases
              << " fallback_calls=" << final_fallback_calls
              << " fallback_added_centers=" << final_fallback_added_centers
              << " fallback_initial_alive=" << final_fallback_initial_alive
              << " final_check=true"
              << std::endl;
  }

  if (final_ok) {
    found_feasible = true;
    best_radius = lo;
    best_centers = std::move(final_U);
    best_rounds = final_rounds;
    best_phases = final_phases;
    best_fallback_calls = final_fallback_calls;
    best_fallback_added_centers = final_fallback_added_centers;
    best_fallback_initial_alive = final_fallback_initial_alive;
  } else if (!found_feasible) {
    return ThorupSimpleResult<Graph>{
        std::move(final_U),
        lo,
        final_rounds,
        final_phases,
        final_fallback_calls,
        final_fallback_added_centers,
        final_fallback_initial_alive,
        false};
  }
  } else if (params.verbose) {
    std::cout << "[ThorupSimple] radius=" << lo
              << " feasible=true"
              << " centers=" << best_centers.size()
              << " rounds=" << best_rounds
              << " phases=" << best_phases
              << " fallback_calls=" << best_fallback_calls
              << " fallback_added_centers=" << best_fallback_added_centers
              << " fallback_initial_alive=" << best_fallback_initial_alive
              << " final_check=skipped"
              << std::endl;
  }

  if (best_centers.size() < k) {
    std::vector<char> used(G.n, 0);

    for (size_t i = 0; i < best_centers.size(); ++i) {
      used[best_centers[i]] = 1;
    }

    for (uintE v = 0; v < G.n && best_centers.size() < k; ++v) {
      if (!used[v]) best_centers.push_back(v);
    }
  }

  return ThorupSimpleResult<Graph>{
      std::move(best_centers),
      best_radius,
      best_rounds,
      best_phases,
      best_fallback_calls,
      best_fallback_added_centers,
      best_fallback_initial_alive,
      true};
}

template <class Graph>
ThorupSimpleResult<Graph> compute_for_fixed_radius(
    Graph& G,
    size_t k,
    ThorupDistance<Graph> radius,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params) {
  auto base_edges = extract_unique_undirected_edges(G);

  size_t rounds = 0, phases = 0;
  size_t fallback_calls = 0;
  size_t fallback_added_centers = 0;
  size_t fallback_initial_alive = 0;

  auto [ok, U] =
      feasible_for_radius(G, base_edges, k, radius, params,
                          &rounds,
                          &phases,
                          &fallback_calls,
                          &fallback_added_centers,
                          &fallback_initial_alive);

  if (!ok && params.verbose) {
    std::cout << "[ThorupSimple] fixed-radius run produced "
              << U.size() << " centers for k=" << k << std::endl;
  }

  return ThorupSimpleResult<Graph>{
      std::move(U),
      radius,
      rounds,
      phases,
      fallback_calls,
      fallback_added_centers,
      fallback_initial_alive,
      ok};
}

template <class Graph>
parlay::sequence<ThorupDistance<Graph>> distances_to_centers(
    Graph& G,
    const parlay::sequence<uintE>& centers,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params) {
  auto base_edges = extract_unique_undirected_edges(G);
  return set_distances(base_edges, G, centers, params);
}

}  // namespace thorup_simple
}  // namespace gbbs