
// flags:
//   required:
//     -k <int>          : number of centers
//   optional:
//     -rounds <int>     : number of times to run the algorithm
//     -s                : input graph is symmetric / undirected
//     -m                : input graph should be mmap'd
//     -c                : compressed graph input
//     -b                : binary graph input
//     -sc               : use single-core SSSP backend
//     -epsilon <dbl>    : approximation / alpha-bucketing parameter;
//                         must be positive
//     -delta <dbl>      : bucket width
//     -nb <int>         : number of buckets; must be a power of two
//     -cap <dbl>        : distance cap
//     -seed <int>       : random seed; if negative or omitted, uses time-based seed
//     -verbose          : print additional internal bucket/round information

#include <algorithm>
#include <limits>
#include <type_traits>

#include "gbbs/gbbs.h"
#include "benchmarks/Clustering/K-Center/common/DispatchMain.h"
#include "ApproximateGonzalez.h"
#include "benchmarks/Clustering/K-Center/common/KCenterQuality.h"

namespace gbbs {

template <class Graph>
double ApproximateGonzalez_runner(Graph& G, commandLine P) {
  using W = typename Graph::weight_type;
  using Distance =
      typename std::conditional<std::is_same<W, gbbs::empty>::value,
                                uintE, W>::type;

  size_t k = P.getOptionLongValue("-k", 10);
  double epsilon = P.getOptionDoubleValue("-epsilon", 0.1);
  double delta = P.getOptionDoubleValue("-delta", 1.0);
  size_t num_buckets = P.getOptionLongValue("-nb", 32);
  double dist_cap =
      P.getOptionDoubleValue("-cap", std::numeric_limits<double>::infinity());
  long seed = P.getOptionLongValue("-seed", -1);
  bool verbose = P.getOption("-verbose");
  bool single_core = P.getOption("-sc");

  std::cout << "### Application: ApproximateGonzalez" << std::endl;
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
  std::cout << "### Params: "
            << "-k = " << k
            << ", -epsilon = " << epsilon
            << ", -delta = " << delta
            << ", -nb = " << num_buckets
            << ", -cap = " << dist_cap
            << ", -seed = " << seed
            << ", -verbose = " << (verbose ? "true" : "false")
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

  timer t;
  t.start();
  auto result =
      ApproximateGonzalez<Graph, Distance>(G, k, epsilon, delta,
                                           num_buckets, dist_cap,
                                           seed, verbose, single_core);
  double tt = t.stop();

  size_t preview = result.centers.size();
  if (preview > 0) {
    std::cout << "### Centers (first " << preview << "): ";
    for (size_t i = 0; i < preview; ++i) {
      std::cout << result.centers[i] << (i + 1 == preview ? "\n" : " ");
    }
  }

  auto q = gbbs::kcenter_quality::compute(
    G, result.centers, delta, num_buckets, single_core);

  std::cout << "num_centers = " << result.centers.size() << std::endl;
  gbbs::kcenter_quality::print(q);
  std::cout << "### Running Time: " << tt << std::endl;

  return tt;
}

}  // namespace gbbs

int main(int argc, char* argv[]) {
  auto app = [](auto& G, gbbs::commandLine P) {
    return gbbs::ApproximateGonzalez_runner(G, P);
  };
  return gbbs::kcenter_common::dispatch_main(argc, argv, app, false);
}