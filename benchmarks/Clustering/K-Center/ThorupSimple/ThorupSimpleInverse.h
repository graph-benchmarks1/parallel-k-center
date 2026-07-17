// This file provides the feasibility check of a certain radius for the simplified algorithm of Thorup.

#pragma once

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

#include "gbbs/gbbs.h"
#include "benchmarks/Clustering/K-Center/ThorupSimple/common/ThorupSimpleShared.h"
#include "parlay/primitives.h"
#include "parlay/sequence.h"

namespace gbbs {
namespace thorup_simple {

inline double seconds_since(
    const std::chrono::steady_clock::time_point& start) {
  using namespace std::chrono;
  return duration_cast<duration<double>>(steady_clock::now() - start).count();
}

template <class Graph>
size_t greedy_finish_remaining_alive(
    Graph& G,
    const parlay::sequence<typename Graph::edge>& base_edges,
    ThorupDistance<Graph> d,
    size_t abort_after_k,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params,
    parlay::sequence<uintE>& alive,
    parlay::sequence<uintE>& U) {
  size_t added = 0;

  while (!alive.empty()) {
    uintE center = alive[0];
    U.push_back(center);
    ++added;

    if (U.size() > abort_after_k) {
      alive = parlay::sequence<uintE>();
      return added;
    }

    parlay::sequence<uintE> singleton(1);
    singleton[0] = center;

    auto cover_dist = set_distances(base_edges, G, singleton, params, d);
    alive = parlay::filter(alive, [&](uintE v) { return cover_dist[v] > d; });
  }

  return added;
}

template <class Graph>
parlay::sequence<uintE> maximal_dist_d_independent_set(
    Graph& G,
    const parlay::sequence<typename Graph::edge>& base_edges,
    ThorupDistance<Graph> d,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params,
    size_t abort_after_k = std::numeric_limits<size_t>::max(),
    size_t* out_rounds = nullptr,
    size_t* out_phases = nullptr,
    size_t* out_fallback_calls = nullptr,
    size_t* out_fallback_added_centers = nullptr,
    size_t* out_fallback_initial_alive = nullptr) {
  using Distance = ThorupDistance<Graph>;

  const size_t n = G.n;
  const size_t rounds_per_phase =
      rounds_per_phase_from_factor(n, params.rounds_per_phase_factor);

  parlay::sequence<uintE> U;
  U.reserve(n);

  parlay::sequence<uintE> alive =
      parlay::tabulate(n, [&](size_t i) { return static_cast<uintE>(i); });

  double sample_delta = static_cast<double>(std::max<size_t>(1, n));
  size_t total_rounds = 0;
  size_t total_phases = 0;
  size_t fallback_calls = 0;
  size_t fallback_added_centers = 0;
  size_t fallback_initial_alive = 0;

  auto write_outputs = [&]() {
    if (out_rounds != nullptr) *out_rounds = total_rounds;
    if (out_phases != nullptr) *out_phases = total_phases;
    if (out_fallback_calls != nullptr) *out_fallback_calls = fallback_calls;
    if (out_fallback_added_centers != nullptr) {
      *out_fallback_added_centers = fallback_added_centers;
    }
    if (out_fallback_initial_alive != nullptr) {
      *out_fallback_initial_alive = fallback_initial_alive;
    }
  };

  while (!alive.empty()) {
    ++total_phases;
    size_t alive_at_phase_start = alive.size();

    for (size_t r = 0; r < rounds_per_phase && !alive.empty(); ++r) {
      ++total_rounds;

      const auto round_start = std::chrono::steady_clock::now();
      const size_t alive_before_round = alive.size();

      double sample_prob =
          std::min(1.0, params.sample_multiplier / std::max(1.0, sample_delta));
      uint64_t round_seed =
          params.seed + 0x9e3779b97f4a7c15ULL * total_rounds;

      const auto sampling_start = std::chrono::steady_clock::now();

      auto R = parlay::filter(alive, [&](uintE v) {
        return bernoulli_from_hash(v, round_seed, sample_prob);
      });

      const double sampling_sec = seconds_since(sampling_start);

      if (R.empty()) {
        if (params.verbose) {
          std::cout << "[ThorupSimple][round]"
                    << " phase=" << total_phases
                    << " local_round=" << r
                    << " total_round=" << total_rounds
                    << " alive_before=" << alive_before_round
                    << " sample_delta=" << sample_delta
                    << " sample_prob=" << sample_prob
                    << " R=0"
                    << " sampling_sec=" << sampling_sec
                    << " total_sec=" << seconds_since(round_start)
                    << std::endl;
        }
        continue;
      }

      if (R.empty()) continue;

      const size_t num_bits = ceil_log2_size(R.size());
      parlay::sequence<bool> is_isolated(R.size(), true);

      double build_sets_sec = 0.0;
      double isolation_sssp_sec = 0.0;
      double isolation_check_sec = 0.0;
      size_t isolation_set_dist_calls = 0;
      size_t nonempty_Ri_count = 0;
      size_t sum_Ri_sizes = 0;
      size_t max_Ri_size = 0;

      // Thorup's separating family has 2 * log_2(|R|) sets:
      // for each bit position b, one set with bit b = 0 and one with bit b = 1.
      for (size_t b = 0; b < num_bits; ++b) {
        for (int bit_value_int = 0; bit_value_int <= 1; ++bit_value_int) {
          const bool bit_value = static_cast<bool>(bit_value_int);

          const auto build_set_start = std::chrono::steady_clock::now();

          parlay::sequence<bool> in_Ri(R.size(), false);
          parallel_for(0, R.size(), [&](size_t i) {
            const bool bit = ((i >> b) & 1ULL) != 0ULL;
            in_Ri[i] = (bit == bit_value);
          });

          auto Ri = parlay::pack(R, in_Ri);

          build_sets_sec += seconds_since(build_set_start);

          if (Ri.empty()) continue;

          ++nonempty_Ri_count;
          sum_Ri_sizes += Ri.size();
          max_Ri_size = std::max(max_Ri_size, Ri.size());

          const auto iso_sssp_start = std::chrono::steady_clock::now();

          auto dist_to_Ri = set_distances(base_edges, G, Ri, params, d);

          isolation_sssp_sec += seconds_since(iso_sssp_start);
          ++isolation_set_dist_calls;

          const auto iso_check_start = std::chrono::steady_clock::now();

          parallel_for(0, R.size(), [&](size_t i) {
            if (!is_isolated[i]) return;

            const bool my_bit = ((i >> b) & 1ULL) != 0ULL;

            // Only sets not containing R[i] can witness another nearby sample.
            if (my_bit == bit_value) return;

            const uintE v = R[i];
            if (dist_to_Ri[v] <= d) {
              is_isolated[i] = false;
            }
          });

          isolation_check_sec += seconds_since(iso_check_start);
        }
      }

      const auto pack_T_start = std::chrono::steady_clock::now();
      auto T = parlay::pack(R, is_isolated);
      const double pack_T_sec = seconds_since(pack_T_start);
      if (T.empty()) {
        if (params.verbose) {
          std::cout << "[ThorupSimple][round]"
                    << " phase=" << total_phases
                    << " local_round=" << r
                    << " total_round=" << total_rounds
                    << " alive_before=" << alive_before_round
                    << " alive_after=" << alive.size()
                    << " sample_delta=" << sample_delta
                    << " sample_prob=" << sample_prob
                    << " R=" << R.size()
                    << " num_bits=" << num_bits
                    << " nonempty_Ri=" << nonempty_Ri_count
                    << " avg_Ri_size="
                    << (nonempty_Ri_count == 0
                          ? 0.0
                          : static_cast<double>(sum_Ri_sizes) / nonempty_Ri_count)
                    << " max_Ri_size=" << max_Ri_size
                    << " T=0"
                    << " iso_calls=" << isolation_set_dist_calls
                    << " sampling_sec=" << sampling_sec
                    << " build_sets_sec=" << build_sets_sec
                    << " isolation_sssp_sec=" << isolation_sssp_sec
                    << " isolation_check_sec=" << isolation_check_sec
                    << " pack_T_sec=" << pack_T_sec
                    << " cover_sssp_sec=0"
                    << " filter_alive_sec=0"
                    << " total_sec=" << seconds_since(round_start)
                    << std::endl;
        }
        continue;
      }

      const auto add_centers_start = std::chrono::steady_clock::now();

      for (size_t i = 0; i < T.size(); ++i) {
        U.push_back(T[i]);
        if (U.size() > abort_after_k) {
          if (params.verbose) {
            std::cout << "[ThorupSimple][round]"
                      << " phase=" << total_phases
                      << " local_round=" << r
                      << " total_round=" << total_rounds
                      << " alive_before=" << alive_before_round
                      << " alive_after=" << alive.size()
                      << " sample_delta=" << sample_delta
                      << " sample_prob=" << sample_prob
                      << " R=" << R.size()
                      << " num_bits=" << num_bits
                      << " nonempty_Ri=" << nonempty_Ri_count
                      << " avg_Ri_size="
                      << (nonempty_Ri_count == 0
                            ? 0.0
                            : static_cast<double>(sum_Ri_sizes) / nonempty_Ri_count)
                      << " max_Ri_size=" << max_Ri_size
                      << " T=" << T.size()
                      << " U=" << U.size()
                      << " abort=true"
                      << " iso_calls=" << isolation_set_dist_calls
                      << " sampling_sec=" << sampling_sec
                      << " build_sets_sec=" << build_sets_sec
                      << " isolation_sssp_sec=" << isolation_sssp_sec
                      << " isolation_check_sec=" << isolation_check_sec
                      << " pack_T_sec=" << pack_T_sec
                      << " add_centers_sec="
                      << seconds_since(add_centers_start)
                      << " cover_sssp_sec=0"
                      << " filter_alive_sec=0"
                      << " total_sec=" << seconds_since(round_start)
                      << std::endl;
          }

          write_outputs();
          return U;
        }
      }

      const double add_centers_sec = seconds_since(add_centers_start);

      const auto cover_start = std::chrono::steady_clock::now();
      auto cover_dist = set_distances(base_edges, G, T, params, d);
      const double cover_sssp_sec = seconds_since(cover_start);

      const auto filter_alive_start = std::chrono::steady_clock::now();
      alive = parlay::filter(alive, [&](uintE v) { return cover_dist[v] > d; });
      const double filter_alive_sec = seconds_since(filter_alive_start);

      if (params.verbose) {
        std::cout << "[ThorupSimple][round]"
                  << " phase=" << total_phases
                  << " local_round=" << r
                  << " total_round=" << total_rounds
                  << " alive_before=" << alive_before_round
                  << " alive_after=" << alive.size()
                  << " removed=" << (alive_before_round - alive.size())
                  << " sample_delta=" << sample_delta
                  << " sample_prob=" << sample_prob
                  << " R=" << R.size()
                  << " num_bits=" << num_bits
                  << " nonempty_Ri=" << nonempty_Ri_count
                  << " avg_Ri_size="
                  << (nonempty_Ri_count == 0
                        ? 0.0
                        : static_cast<double>(sum_Ri_sizes) / nonempty_Ri_count)
                  << " max_Ri_size=" << max_Ri_size
                  << " T=" << T.size()
                  << " U=" << U.size()
                  << " abort=false"
                  << " iso_calls=" << isolation_set_dist_calls
                  << " sampling_sec=" << sampling_sec
                  << " build_sets_sec=" << build_sets_sec
                  << " isolation_sssp_sec=" << isolation_sssp_sec
                  << " isolation_check_sec=" << isolation_check_sec
                  << " pack_T_sec=" << pack_T_sec
                  << " add_centers_sec=" << add_centers_sec
                  << " cover_sssp_sec=" << cover_sssp_sec
                  << " filter_alive_sec=" << filter_alive_sec
                  << " total_sec=" << seconds_since(round_start)
                  << std::endl;
      }
    }

    if (!alive.empty() &&
        alive.size() == alive_at_phase_start &&
        sample_delta <= 1.0) {
      ++fallback_calls;
      fallback_initial_alive += alive.size();

      std::cout << "[ThorupSimple] WARNING: invoking greedy fallback"
                << " phase=" << total_phases
                << " total_rounds=" << total_rounds
                << " rounds_per_phase=" << rounds_per_phase
                << " rpp_factor=" << params.rounds_per_phase_factor
                << " alive=" << alive.size()
                << " d=" << d
                << " sample_delta=" << sample_delta
                << std::endl;

      fallback_added_centers +=
          greedy_finish_remaining_alive(G, base_edges, d, abort_after_k,
                                        params, alive, U);
      break;
    }

    sample_delta = std::max(1.0, sample_delta / params.shrink_factor);
  }

  write_outputs();
  return U;
}

template <class Graph>
std::pair<bool, parlay::sequence<uintE>> feasible_for_radius(
    Graph& G,
    const parlay::sequence<typename Graph::edge>& base_edges,
    size_t k,
    ThorupDistance<Graph> radius,
    const ThorupSimpleParams<ThorupDistance<Graph>>& params,
    size_t* out_rounds = nullptr,
    size_t* out_phases = nullptr,
    size_t* out_fallback_calls = nullptr,
    size_t* out_fallback_added_centers = nullptr,
    size_t* out_fallback_initial_alive = nullptr) {
  using Distance = ThorupDistance<Graph>;

  Distance d = radius;

  auto U =
      maximal_dist_d_independent_set(G, base_edges, d, params,
                                     /*abort_after_k=*/k,
                                     out_rounds,
                                     out_phases,
                                     out_fallback_calls,
                                     out_fallback_added_centers,
                                     out_fallback_initial_alive);

  return {U.size() <= k, std::move(U)};
}

}  // namespace thorup_simple
}  // namespace gbbs