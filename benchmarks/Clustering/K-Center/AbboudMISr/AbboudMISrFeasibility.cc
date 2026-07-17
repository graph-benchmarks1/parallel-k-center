// flags:
//   required:
//     -r <radius>           : distance-r independent set threshold
//   optional:
//     -rounds <int>         : number of times to run the algorithm
//     -s                    : input graph is symmetric / undirected
//     -m                    : input graph should be mmap'd
//     -c                    : compressed graph input
//     -b                    : binary graph input
//     -sc                   : use single core SSSP backend
//     -delta <dbl>          : bucket width
//     -nb <int>             : number of buckets; must be a power of two
//     -permute              : permute fixed scan order when -no_uniform_random
//     -seed <int>           : random seed
//     -no_uniform_random    : disable uniform random candidate selection;
//                             use fixed/permuted scan order

#include <algorithm>
#include <limits>
#include <type_traits>

#include "gbbs/gbbs.h"
#include "benchmarks/Clustering/K-Center/common/DispatchMain.h"
#include "AbboudMISrFeasibility.h"

namespace gbbs {

template <class Graph>
double AbboudMISrFeasibility_runner(Graph& G, commandLine P) {
  using W = typename Graph::weight_type;

  double r = P.getOptionDoubleValue("-r", 1.0);
  double delta = P.getOptionDoubleValue("-delta", 1.0);
  size_t num_buckets = P.getOptionLongValue("-nb", 32);
  bool permute = P.getOption("-permute");
  uint64_t seed =
      static_cast<uint64_t>(P.getOptionLongValue("-seed", 27491095));
  bool uniform_random = !P.getOption("-no_uniform_random");
  bool single_core = P.getOption("-sc");

  std::cout << "### Application: AbboudMISrFeasibility" << std::endl;
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
  std::cout << "### Params: -r = " << r
            << ", -delta = " << delta
            << ", -nb = " << num_buckets
            << (permute ? ", -permute = true" : ", -permute = false")
            << (permute ? (", -seed = " + std::to_string(seed)) : "")
            << (uniform_random ? ", -uniform_random = true"
                               : ", -uniform_random = false")
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
  auto centers = AbboudMISrFeasibility(G, r, delta, num_buckets, permute, seed,
                            uniform_random, single_core);
  double tt = t.stop();

  size_t preview = std::min<size_t>(centers.size(), 10);
  if (preview > 0) {
    std::cout << "### Centers (first " << preview << "): ";
    for (size_t i = 0; i < preview; ++i) {
      std::cout << centers[i] << (i + 1 == preview ? "\n" : " ");
    }
  }

  std::cout << "num_centers = " << centers.size() << std::endl;
  std::cout << "### Running Time: " << tt << std::endl;

  return tt;
}

}  // namespace gbbs

int main(int argc, char* argv[]) {
  auto app = [](auto& G, gbbs::commandLine P) {
    return gbbs::AbboudMISrFeasibility_runner(G, P);
  };
  return gbbs::kcenter_common::dispatch_main(argc, argv, app, false);
}
