// flags:
//   required:
//     -k <int>        : number of centers
//   optional:
//     -rounds <int>   : number of times to run the algorithm
//     -s              : input graph is symmetric / undirected
//     -m              : input graph should be mmap'd
//     -c              : compressed graph input
//     -b              : binary graph input
//     -sc             : use single-core SSSP backend 
//     -delta <dbl>    : bucket width
//     -nb <int>       : number of buckets; must be a power of two
//     -cap <dbl>      : distance cap
//     -first <vertex> : fixed first center;
//                       if omitted or negative, choose first center randomly
//     -seed <int>     : random seed used when first center is random
//     -spg_mode <str> : support graph maintenance mode;
//                       one of rebuild, local, hybrid
//     -spg_threshold <dbl>
//                     : affected-vertex threshold for hybrid mode

#include <algorithm>
#include <limits>
#include <string>
#include <type_traits>

#include "gbbs/gbbs.h"
#include "benchmarks/Clustering/K-Center/common/DispatchMain.h"
#include "Forster.h"
#include "benchmarks/Clustering/K-Center/common/KCenterQuality.h"

namespace gbbs {

template <class Graph>
double Forster_runner(Graph& G, commandLine P) {
  using W = typename Graph::weight_type;
  using RRType = RR<Graph>;

  uintE k = P.getOptionLongValue("-k", 1);
  size_t num_buckets = P.getOptionLongValue("-nb", 32);
  double delta = P.getOptionDoubleValue("-delta", 1.0);
  double dist_cap =
      P.getOptionDoubleValue("-cap", std::numeric_limits<double>::infinity());
  bool single_core = P.getOption("-sc");

  std::string spg_mode_str = P.getOptionValue("-spg_mode", "rebuild");
  double spg_threshold = P.getOptionDoubleValue("-spg_threshold", 0.25);

  RRSPGMode spg_mode = RRSPGMode::Rebuild;
  if (spg_mode_str == "local") {
    spg_mode = RRSPGMode::Local;
  } else if (spg_mode_str == "hybrid") {
    spg_mode = RRSPGMode::Hybrid;
  } else if (spg_mode_str != "rebuild") {
    std::cout << "Unknown -spg_mode: " << spg_mode_str
              << " (expected rebuild, local, or hybrid)" << std::endl;
    exit(-1);
  }

  long first_opt = P.getOptionLongValue("-first", -1);
  uint64_t seed = static_cast<uint64_t>(P.getOptionLongValue("-seed", 12345));

  bool choose_random_first = (first_opt < 0);
  uintE first_center = (first_opt < 0) ? 0 : static_cast<uintE>(first_opt);

  std::cout << "### Application: Forster" << std::endl;
  std::cout << "### Graph: " << P.getArgument(0) << std::endl;
  std::cout << "### Threads: "
          << (single_core ? 1 : num_workers())
          << std::endl;
  std::cout << "### Graph Type: "
            << (std::is_same<W, gbbs::empty>::value ? "unweighted" : "weighted")
            << std::endl;
  std::cout << ", -spg_mode = " << spg_mode_str
            << ", -spg_threshold = " << spg_threshold
            << (single_core ? ", -sc = true" : ", -sc = false")
            << std::endl;
  std::cout << "### n: " << G.n << std::endl;
  std::cout << "### m: " << G.m << std::endl;
  std::cout << "### Params: -k = " << k
            << ", -delta = " << delta
            << ", -nb = " << num_buckets
            << ", -cap = " << dist_cap;
  if (choose_random_first) {
    std::cout << ", -first = RANDOM"
              << ", -seed = " << seed;
  } else {
    std::cout << ", -first = " << first_center;
  }
  std::cout << (single_core ? ", -sc = true" : ", -sc = false")
            << std::endl;
  std::cout << "### ------------------------------------" << std::endl;

  if constexpr (!std::is_same<W, gbbs::empty>::value) {
    if (!single_core &&
        num_buckets != (((uintE)1) << parlay::log2_up(num_buckets))) {
      std::cout << "Please specify a number of buckets that is a power of two\n";
      exit(-1);
    }
  }

  timer t;
  t.start();

  auto [centers, final_dist] =
    ForsterWithDistances(G, k, delta, num_buckets,
                         choose_random_first, first_center,
                         seed, dist_cap, single_core,
                         spg_mode, spg_threshold);

  double tt = t.stop();

  size_t preview = std::min<size_t>(centers.size(), 10);
  if (preview > 0) {
    std::cout << "### Centers (first " << preview << "): ";
    for (size_t i = 0; i < preview; ++i) {
      std::cout << centers[i] << (i + 1 == preview ? "\n" : " ");
    }
  }

  auto q = gbbs::kcenter_quality::compute(
    G, centers, delta, num_buckets, single_core);

  std::cout << "num_centers = " << centers.size() << std::endl;
  gbbs::kcenter_quality::print(q);
  std::cout << "### Running Time: " << tt << std::endl;

  return tt;
}

}  // namespace gbbs

int main(int argc, char* argv[]) {
  auto app = [](auto& G, gbbs::commandLine P) {
    return gbbs::Forster_runner(G, P);
  };
  return gbbs::kcenter_common::dispatch_main(argc, argv, app, false);
}