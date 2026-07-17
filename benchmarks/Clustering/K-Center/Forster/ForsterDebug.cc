#define WEIGHTED 1

#include <limits>
#include <string>
#include <utility>

#include "Forster.h"
#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaStepping.h"

namespace gbbs {

template <class Distance>
static inline std::string dist_to_string(Distance d, Distance inf) {
  if (d == inf) return "INF";
  return std::to_string(d);
}

template <class Graph>
double Forster_runner(Graph& G, commandLine P) {
  using RRType = RR<Graph>;
  using Distance = typename RRType::Distance;
  constexpr Distance kMaxDistance = RRType::kMaxDistance;

  uintE k = P.getOptionLongValue("-k", 1);
  size_t num_buckets = P.getOptionLongValue("-nb", 32);
  double delta = P.getOptionDoubleValue("-delta", 1.0);
  double dist_cap =
      P.getOptionDoubleValue("-cap", std::numeric_limits<double>::infinity());

  long first_opt = P.getOptionLongValue("-first", -1);
  uint64_t seed = static_cast<uint64_t>(P.getOptionLongValue("-seed", 12345));

  bool choose_random_first = (first_opt < 0);
  uintE first_center = (first_opt < 0) ? 0 : static_cast<uintE>(first_opt);

  std::cout << "### Application: Forster" << std::endl;
  std::cout << "### Graph: " << P.getArgument(0) << std::endl;
  std::cout << "### Threads: " << num_workers() << std::endl;
  std::cout << "### n: " << G.n << std::endl;
  std::cout << "### m: " << G.m << std::endl;
  std::cout << "### Params: -k = " << k
            << " -delta = " << delta
            << " -nb (num_buckets) = " << num_buckets
            << " -cap = " << dist_cap;
  if (choose_random_first) {
    std::cout << " -first = RANDOM"
              << " -seed = " << seed;
  } else {
    std::cout << " -first = " << first_center;
  }
  std::cout << std::endl;
  std::cout << "### ------------------------------------" << std::endl;

  if (num_buckets != (((uintE)1) << parlay::log2_up(num_buckets))) {
    std::cout << "Please specify a number of buckets that is a power of two\n";
    exit(-1);
  }

  timer t;
  t.start();

  RRType rr(G, 0, delta, num_buckets, dist_cap);
  rr.initialize_empty();

  parlay::sequence<uintE> centers;
  centers.reserve(k);

  auto compute_reference = [&](const parlay::sequence<uintE>& cur_centers) {
    sequence<Distance> ref(G.n, kMaxDistance);

    for (size_t j = 0; j < cur_centers.size(); j++) {
      uintE c = cur_centers[j];
      auto d_from_c = DeltaStepping(G, c, delta, num_buckets, dist_cap);
      parallel_for(0, G.n, [&](size_t i) {
        if (d_from_c[i] < ref[i]) ref[i] = d_from_c[i];
      });
    }

    return ref;
  };

  auto print_round_check = [&](size_t round_id, uintE chosen_center) {
    const auto& rr_dist = rr.distances();
    auto ref = compute_reference(centers);

    size_t mismatches = 0;
    size_t first_bad = G.n;
    for (size_t i = 0; i < G.n; i++) {
      if (rr_dist[i] != ref[i]) {
        mismatches++;
        if (first_bad == G.n) first_bad = i;
      }
    }

    size_t inf_count_rr = 0;
    size_t inf_count_ref = 0;
    for (size_t i = 0; i < G.n; i++) {
      if (rr_dist[i] == kMaxDistance) inf_count_rr++;
      if (ref[i] == kMaxDistance) inf_count_ref++;
    }

    auto rr_im = parlay::delayed_seq<Distance>(
        G.n, [&](size_t i) { return (rr_dist[i] == kMaxDistance) ? 0 : rr_dist[i]; });
    auto ref_im = parlay::delayed_seq<Distance>(
        G.n, [&](size_t i) { return (ref[i] == kMaxDistance) ? 0 : ref[i]; });

    std::cout << "round " << round_id
              << " chose center " << chosen_center << std::endl;
    std::cout << "  rr max_dist = " << parlay::reduce_max(rr_im) << std::endl;
    std::cout << "  ref max_dist = " << parlay::reduce_max(ref_im) << std::endl;
    std::cout << "  rr unreachable_vertices = " << inf_count_rr << std::endl;
    std::cout << "  ref unreachable_vertices = " << inf_count_ref << std::endl;
    std::cout << "  mismatches = " << mismatches << std::endl;

    if (first_bad < G.n) {
      std::cout << "  first mismatch at v=" << first_bad
                << " rr=" << dist_to_string(rr_dist[first_bad], kMaxDistance)
                << " ref=" << dist_to_string(ref[first_bad], kMaxDistance)
                << std::endl;

      size_t shown = 0;
      for (size_t i = 0; i < G.n && shown < 10; i++) {
        if (rr_dist[i] != ref[i]) {
          std::cout << "    v=" << i
                    << " rr=" << dist_to_string(rr_dist[i], kMaxDistance)
                    << " ref=" << dist_to_string(ref[i], kMaxDistance)
                    << std::endl;
          shown++;
        }
      }
    }
  };

  uintE first;
  if (choose_random_first) {
    parlay::random rng(seed);
    uint64_t r = rng.ith_rand(0);
    first = static_cast<uintE>(r % G.n);
  } else {
    first = first_center;
  }

  centers.push_back(first);
  rr.insert_center(first);
  print_round_check(1, first);

  while (centers.size() < k) {
    const auto& dist = rr.distances();

    auto max_pair_monoid = parlay::make_monoid(
        [](auto a, auto b) { return (a.second > b.second) ? a : b; },
        std::make_pair(size_t{0}, std::numeric_limits<Distance>::lowest()));

    auto farthest = parlay::reduce(
        parlay::tabulate(G.n, [&](size_t i) {
          return std::make_pair(i, dist[i]);
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

    if (already_present) {
      std::cout << "Encountered duplicate farthest center "
                << farthest_vtx << ", stopping early." << std::endl;
      break;
    }

    centers.push_back(farthest_vtx);
    rr.insert_center(farthest_vtx);
    print_round_check(centers.size(), farthest_vtx);
  }

  double tt = t.stop();

  const auto& final_dist = rr.distances();

  size_t inf_count = 0;
  for (size_t i = 0; i < G.n; i++) {
    if (final_dist[i] == kMaxDistance) inf_count++;
  }

  auto dist_im = parlay::delayed_seq<Distance>(
      G.n, [&](size_t i) {
        return (final_dist[i] == kMaxDistance) ? 0 : final_dist[i];
      });

  std::cout << "centers:";
  for (size_t i = 0; i < centers.size(); i++) {
    std::cout << " " << centers[i];
  }
  std::cout << std::endl;

  std::cout << "num_centers = " << centers.size() << std::endl;
  std::cout << "max_dist_to_centers = "
            << parlay::reduce_max(dist_im) << std::endl;
  std::cout << "unreachable_vertices = "
            << inf_count << std::endl;
  std::cout << "### Running Time: " << tt << std::endl;

  return tt;
}

}  // namespace gbbs

generate_weighted_main(gbbs::Forster_runner, false);