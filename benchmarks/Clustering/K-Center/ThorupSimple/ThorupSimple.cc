// flags:
//   required:
//     either:
//       -r <radius>          : fixed-radius mode
//     or:
//       -max_radius <radius> : upper bound for binary-search mode
//
//   optional:
//     -k <int>          : number of centers
//     -rpp <dbl>        : rounds-per-phase multiplier;
//                         actual rounds per phase are
//                           ceil(rpp * ln n)
//                         This controls the hidden constant in the
//                         O(log n) rounds-per-phase bound.
//     -s                : input graph is symmetric / undirected
//     -m                : input graph should be mmap'd
//     -c                : compressed graph input
//     -b                : binary graph input
//     -sc               : use single core SSSP backend
//     -shrink <dbl>     : shrink factor for sampling scale between phases
//     -lambda <dbl>     : sampling multiplier;
//                         sample probability is roughly
//                           min(1, lambda / sample_delta)
//     -delta <dbl>      : bucket width
//     -nb <int>         : number of buckets; must be a power of two
//     -seed <int>       : random/hash seed
//     -v                : verbose output

#include <algorithm>
#include <limits>
#include <type_traits>

#include "gbbs/gbbs.h"
#include "benchmarks/Clustering/K-Center/common/DispatchMain.h"
#include "ThorupSimple.h"
#include "benchmarks/Clustering/K-Center/common/KCenterQuality.h"
#include "benchmarks/Clustering/K-Center/ThorupSimple/ThorupSimple.h"

namespace gbbs {

template <class Graph>
double ThorupSimple_runner(Graph& G, commandLine P) {
  using W = typename Graph::weight_type;
  using Distance = thorup_simple::ThorupDistance<Graph>;

  uintE k = P.getOptionLongValue("-k", 1);

  double shrink_factor = P.getOptionDoubleValue("-shrink", 2.0);
  double rounds_per_phase_factor = P.getOptionDoubleValue("-rpp", 8.0);
  double lambda = P.getOptionDoubleValue("-lambda", 1.0);
  uint64_t seed = static_cast<uint64_t>(P.getOptionLongValue("-seed", 12345));

  double ds_delta = P.getOptionDoubleValue("-delta", 1.0);
  size_t num_buckets = P.getOptionLongValue("-nb", 32);
  bool single_core = P.getOption("-sc");

  bool verbose = P.getOption("-v");
  bool fixed_radius_mode = P.getOption("-r");
  bool has_max_radius = P.getOption("-max_radius");

  Distance radius = static_cast<Distance>(P.getOptionDoubleValue("-r", 0.0));
  Distance max_radius =
    has_max_radius
        ? static_cast<Distance>(P.getOptionDoubleValue("-max_radius", 0.0))
        : static_cast<Distance>(0);

  std::cout << "### Application: ThorupSimple" << std::endl;
  std::cout << "### Graph: " << P.getArgument(0) << std::endl;
  std::cout << "### Threads: "
            << (single_core ? 1 : num_workers())
            << std::endl;
  std::cout << "### Graph Type: "
            << (std::is_same<W, gbbs::empty>::value ? "unweighted" : "weighted")
            << std::endl;
  std::cout << "### SSSP Mode: "
            << (single_core ? "single-core" : "parallel") << std::endl;
  std::cout << "### n: " << G.n << std::endl;
  std::cout << "### m: " << G.m << std::endl;
  const size_t actual_rounds_per_phase =
      thorup_simple::rounds_per_phase_from_factor(
          G.n, rounds_per_phase_factor);

  std::cout << "### Params: -k = " << k
            << ", -shrink = " << shrink_factor
            << ", -rpp = " << rounds_per_phase_factor
            << ", rounds_per_phase = " << actual_rounds_per_phase
            << ", -lambda = " << lambda
            << ", -delta = " << ds_delta
            << ", -nb = " << num_buckets
            << ", -seed = " << seed;

  if (fixed_radius_mode) {
    std::cout << ", -r = " << radius;
  } else if (has_max_radius) {
    std::cout << ", -max_radius = " << max_radius;
  } else {
    std::cout << ", -max_radius = exponential-search";
  }

  std::cout << ", -v = " << (verbose ? "true" : "false")
            << (single_core ? ", -sc = true" : ", -sc = false")
            << std::endl;
  std::cout << "### ------------------------------------" << std::endl;

  if constexpr (!std::is_same<W, gbbs::empty>::value) {
    if (!single_core &&
        num_buckets != (((uintE)1) << parlay::log2_up(num_buckets))) {
      std::cout << "Please specify a number of buckets that is a power of two\n";
      exit(-1);
    }
  }

  if (!fixed_radius_mode &&
      has_max_radius &&
      max_radius <= static_cast<Distance>(0)) {
    std::cout << "Please specify a positive -max_radius\n";
    exit(-1);
  }

  thorup_simple::ThorupSimpleParams<Distance> params;
  params.shrink_factor = shrink_factor;
  params.rounds_per_phase_factor = rounds_per_phase_factor;
  params.sample_multiplier = lambda;
  params.ds_delta = ds_delta;
  params.num_buckets = num_buckets;
  params.single_core = single_core;
  params.seed = seed;
  params.verbose = verbose;
  params.use_two_r = false;

  timer t;
  t.start();

  thorup_simple::ThorupSimpleResult<Graph> result =
      fixed_radius_mode
          ? thorup_simple::compute_for_fixed_radius(G, k, radius, params)
          : thorup_simple::compute_kcenter(G, k, max_radius, params);

  double tt = t.stop();

  size_t preview = std::min<size_t>(result.centers.size(), 10);
  if (preview > 0) {
    std::cout << "### Centers (first " << preview << "): ";
    for (size_t i = 0; i < preview; ++i) {
      std::cout << result.centers[i] << (i + 1 == preview ? "\n" : " ");
    }
  }

  std::cout << "feasible = " << (result.feasible ? "true" : "false") << std::endl;
  std::cout << "radius = " << result.radius << std::endl;
  std::cout << "rounds = " << result.rounds << std::endl;
  std::cout << "phases = " << result.phases << std::endl;
  std::cout << "fallback_calls = " << result.fallback_calls << std::endl;
  std::cout << "fallback_added_centers = "
            << result.fallback_added_centers << std::endl;
  std::cout << "fallback_initial_alive = "
            << result.fallback_initial_alive << std::endl;
  auto q = gbbs::kcenter_quality::compute(
      G, result.centers, ds_delta, num_buckets, single_core);

  std::cout << "num_centers = " << result.centers.size() << std::endl;
  gbbs::kcenter_quality::print(q);
  std::cout << "### Running Time: " << tt << std::endl;

  return tt;
}

}  // namespace gbbs

int main(int argc, char* argv[]) {
  auto app = [](auto& G, gbbs::commandLine P) {
    return gbbs::ThorupSimple_runner(G, P);
  };
  return gbbs::kcenter_common::dispatch_main(argc, argv, app, false);
}