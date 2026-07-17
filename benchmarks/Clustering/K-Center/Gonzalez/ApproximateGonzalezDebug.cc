#define WEIGHTED 1

#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <random>
#include <type_traits>
#include <unordered_set>
#include <vector>

#include "ApproximateGonzalez.h"
#include "benchmarks/PositiveWeightSSSP/DeltaStepping/DeltaStepping.h"

namespace gbbs {

template <class Distance>
inline size_t debug_distance_to_bucket(
    const AlphaBucketState<Distance>& alpha_state, Distance d) {
  return alpha_state.distance_to_bucket(d);
}

template <class Distance>
bool CheckInitialization(const AlphaBucketState<Distance>& alpha_state, size_t n,
                         bool verbose) {
  bool ok = true;

  for (size_t b = 1; b < alpha_state.B; ++b) {
    if (!alpha_state.H[b].empty()) {
      std::cout << "[FAIL] Initialization: bucket " << b
                << " should be empty but has size " << alpha_state.H[b].size()
                << std::endl;
      ok = false;
    }
  }

  if (alpha_state.H[alpha_state.B].size() != n) {
    std::cout << "[FAIL] Initialization: highest bucket has size "
              << alpha_state.H[alpha_state.B].size() << " but expected " << n
              << std::endl;
    ok = false;
  }

  std::vector<uint8_t> seen(n, 0);
  for (uintE v : alpha_state.H[alpha_state.B]) {
    if (v >= n) {
      std::cout << "[FAIL] Initialization: invalid vertex id " << v
                << " in highest bucket" << std::endl;
      ok = false;
      continue;
    }
    if (seen[v]) {
      std::cout << "[FAIL] Initialization: duplicate vertex " << v
                << " in highest bucket" << std::endl;
      ok = false;
    }
    seen[v] = 1;
  }

  for (size_t v = 0; v < n; ++v) {
    if (!seen[v]) {
      std::cout << "[FAIL] Initialization: vertex " << v
                << " missing from highest bucket" << std::endl;
      ok = false;
    }
    if (alpha_state.is_center[v]) {
      std::cout << "[FAIL] Initialization: vertex " << v
                << " incorrectly marked as center" << std::endl;
      ok = false;
    }
    if (alpha_state.bucket_of[v] != alpha_state.B) {
      std::cout << "[FAIL] Initialization: bucket_of[" << v << "] = "
                << alpha_state.bucket_of[v] << " but expected "
                << alpha_state.B << std::endl;
      ok = false;
    }
  }

  if (ok && verbose) {
    std::cout << "[OK] Initialization check passed." << std::endl;
  }
  return ok;
}

template <class Distance>
bool CheckBucketStructure(const AlphaBucketState<Distance>& alpha_state,
                          const sequence<Distance>& dist, bool verbose) {
  const size_t n = alpha_state.n;
  bool ok = true;

  std::vector<uint8_t> seen(n, 0);

  for (size_t b = 1; b <= alpha_state.B; ++b) {
    const auto& bucket = alpha_state.H[b];
    for (size_t pos = 0; pos < bucket.size(); ++pos) {
      uintE v = bucket[pos];

      if (v >= n) {
        std::cout << "[FAIL] Bucket structure: invalid vertex " << v
                  << " in bucket " << b << std::endl;
        ok = false;
        continue;
      }

      if (alpha_state.is_center[v]) {
        std::cout << "[FAIL] Bucket structure: center " << v
                  << " appears in bucket " << b << std::endl;
        ok = false;
      }

      if (seen[v]) {
        std::cout << "[FAIL] Bucket structure: duplicate vertex " << v
                  << " across buckets" << std::endl;
        ok = false;
      }
      seen[v] = 1;

      if (alpha_state.bucket_of[v] != b) {
        std::cout << "[FAIL] Bucket structure: bucket_of[" << v << "] = "
                  << alpha_state.bucket_of[v]
                  << " but vertex appears in bucket " << b << std::endl;
        ok = false;
      }

      if (alpha_state.pos_in_bucket[v] != pos) {
        std::cout << "[FAIL] Bucket structure: pos_in_bucket[" << v << "] = "
                  << alpha_state.pos_in_bucket[v]
                  << " but actual pos is " << pos << " in bucket " << b
                  << std::endl;
        ok = false;
      }

      size_t expected_bucket = debug_distance_to_bucket(alpha_state, dist[v]);
      if (expected_bucket != b) {
        std::cout << "[FAIL] Bucket structure: vertex " << v
                  << " is in bucket " << b << " but distance " << dist[v]
                  << " implies bucket " << expected_bucket << std::endl;
        ok = false;
      }
    }
  }

  for (size_t v = 0; v < n; ++v) {
    if (alpha_state.is_center[v]) {
      if (alpha_state.bucket_of[v] != AlphaBucketState<Distance>::kNoBucket) {
        std::cout << "[FAIL] Bucket structure: center " << v
                  << " has bucket_of = " << alpha_state.bucket_of[v]
                  << " but should have kNoBucket" << std::endl;
        ok = false;
      }
      continue;
    }

    if (!seen[v]) {
      std::cout << "[FAIL] Bucket structure: non-center vertex " << v
                << " is missing from all buckets" << std::endl;
      ok = false;
    }
  }

  if (ok && verbose) {
    std::cout << "[OK] Bucket structure is consistent." << std::endl;
  }
  return ok;
}

template <class Distance>
size_t ComputeHighestNonEmptyBucket(
    const AlphaBucketState<Distance>& alpha_state) {
  for (size_t b = alpha_state.B; b >= 1; --b) {
    if (!alpha_state.bucket_empty(b)) return b;
    if (b == 1) break;
  }
  return 0;
}

template <class Distance>
bool CheckChosenCenter(const AlphaBucketState<Distance>& alpha_state, uintE v,
                       size_t claimed_bmax, bool verbose) {
  bool ok = true;

  size_t true_bmax = ComputeHighestNonEmptyBucket(alpha_state);
  if (claimed_bmax != true_bmax) {
    std::cout << "[FAIL] bmax mismatch: claimed " << claimed_bmax
              << " but true highest non-empty bucket is " << true_bmax
              << std::endl;
    ok = false;
  }

  if (v >= alpha_state.n) {
    std::cout << "[FAIL] Chosen center " << v << " is out of range" << std::endl;
    return false;
  }

  if (alpha_state.is_center[v]) {
    std::cout << "[FAIL] Chosen vertex " << v
              << " is already a center before selection" << std::endl;
    ok = false;
  }

  if (alpha_state.bucket_of[v] != claimed_bmax) {
    std::cout << "[FAIL] Chosen vertex " << v
              << " has bucket_of = " << alpha_state.bucket_of[v]
              << " but claimed_bmax = " << claimed_bmax << std::endl;
    ok = false;
  }

  const auto& bucket = alpha_state.H[claimed_bmax];
  bool found = false;
  for (uintE x : bucket) {
    if (x == v) {
      found = true;
      break;
    }
  }
  if (!found) {
    std::cout << "[FAIL] Chosen vertex " << v
              << " not found inside claimed highest bucket " << claimed_bmax
              << std::endl;
    ok = false;
  }

  if (ok && verbose) {
    std::cout << "[OK] Chosen center " << v
              << " is drawn from the correct highest non-empty bucket "
              << claimed_bmax << "." << std::endl;
  }
  return ok;
}

template <class Distance>
bool CheckChangedSet(const sequence<Distance>& old_dist,
                     const sequence<Distance>& new_dist,
                     const sequence<uint8_t>& changed, bool verbose) {
  bool ok = true;
  size_t n = old_dist.size();

  for (size_t v = 0; v < n; ++v) {
    bool improved = new_dist[v] < old_dist[v];
    bool marked = (changed[v] != 0);
    if (improved != marked) {
      std::cout << "[FAIL] Changed-set mismatch for vertex " << v
                << ": old_dist = " << old_dist[v]
                << ", new_dist = " << new_dist[v]
                << ", improved = " << improved
                << ", changed = " << marked << std::endl;
      ok = false;
    }
  }

  if (ok && verbose) {
    std::cout << "[OK] changed[v] matches exactly the set of improved vertices."
              << std::endl;
  }
  return ok;
}

template <class Distance>
bool CheckBucketMovesBeforeReconcile(
    const AlphaBucketState<Distance>& alpha_state,
    const sequence<Distance>& old_dist,
    const sequence<Distance>& new_dist,
    const sequence<size_t>& old_bucket_of,
    const sequence<uint8_t>& changed, bool verbose) {
  bool ok = true;
  size_t n = old_dist.size();

  for (size_t v = 0; v < n; ++v) {
    if (alpha_state.is_center[v]) continue;

    bool improved = new_dist[v] < old_dist[v];
    if (!improved) continue;

    size_t old_b = old_bucket_of[v];
    size_t expected_old_b =
        (old_dist[v] == alpha_state.inf_dist)
            ? alpha_state.B
            : debug_distance_to_bucket(alpha_state, old_dist[v]);
    size_t expected_new_b = debug_distance_to_bucket(alpha_state, new_dist[v]);

    if (old_b != expected_old_b) {
      std::cout << "[FAIL] Old bucket mismatch for vertex " << v
                << ": old_bucket_of = " << old_b
                << ", expected from old_dist = " << expected_old_b
                << std::endl;
      ok = false;
    }

    if (verbose) {
      std::cout << "  moved/improved vertex " << v
                << ": old_dist=" << old_dist[v]
                << " old_bucket=" << old_b
                << " -> new_dist=" << new_dist[v]
                << " new_bucket=" << expected_new_b << std::endl;
    }

    if (!changed[v]) {
      std::cout << "[FAIL] Vertex " << v
                << " improved but is not marked changed before reconcile"
                << std::endl;
      ok = false;
    }
  }

  if (ok && verbose) {
    std::cout << "[OK] Pre-reconcile bucket move data looks correct."
              << std::endl;
  }
  return ok;
}

// ----------------------------------------------------------------------
// Strong semantic check: recompute exact nearest-center distances from
// scratch using the trusted original GBBS DeltaStepping, once per center,
// then take the pointwise minimum.
//
// NOTE:
// The only part you may need to adapt is the exact call to DeltaStepping(...)
// below if your local DeltaStepping.h exposes a slightly different signature.
// Everything else should remain the same.
// ----------------------------------------------------------------------

template <class Graph, class Distance>
sequence<Distance> ComputeExactNearestCenterDistancesFromScratch(
    Graph& G, const std::vector<uintE>& centers, double delta,
    size_t num_buckets, double dist_cap_unused) {

  constexpr Distance kMaxWeight = std::numeric_limits<Distance>::max();
  const size_t n = G.n;

  auto exact = sequence<Distance>(n, kMaxWeight);

  if (centers.empty()) return exact;

  for (uintE src : centers) {
    // IMPORTANT: use the *correct* GBBS API
    auto single = DeltaStepping(G, src, delta, num_buckets,
                               std::numeric_limits<double>::infinity());

    parallel_for(0, n, [&](size_t i) {
      if (single[i] < exact[i]) {
        exact[i] = single[i];
      }
    });
  }

  return exact;
}

template <class Distance>
bool CheckExactNearestCenterDistances(const sequence<Distance>& maintained_dist,
                                      const sequence<Distance>& exact_dist,
                                      const std::vector<uintE>& centers,
                                      bool verbose) {
  bool ok = true;
  size_t n = maintained_dist.size();

  for (size_t v = 0; v < n; ++v) {
    if (maintained_dist[v] != exact_dist[v]) {
      std::cout << "[FAIL] Exact-distance mismatch for vertex " << v
                << ": maintained = " << maintained_dist[v]
                << ", exact = " << exact_dist[v] << std::endl;
      ok = false;
    }
  }

  if (ok && verbose) {
    std::cout << "[OK] maintained dist[] matches exact nearest-center distances "
                 "recomputed from scratch."
              << std::endl;
  }
  return ok;
}

template <class Graph>
double ApproximateGonzalezDebug_runner(Graph& G, commandLine P) {
  using W = typename Graph::weight_type;
  using Distance =
      typename std::conditional<std::is_same<W, gbbs::empty>::value, uintE,
                                W>::type;

  size_t k = P.getOptionLongValue("-k", 10);
  double epsilon = P.getOptionDoubleValue("-epsilon", 0.1);
  double delta = P.getOptionDoubleValue("-delta", 1.0);
  size_t num_buckets = P.getOptionLongValue("-nb", 32);
  double dist_cap =
      P.getOptionDoubleValue("-cap", std::numeric_limits<double>::infinity());
  long seed = P.getOptionLongValue("-seed", -1);
  bool verbose = P.getOption("-verbose");

  std::cout << "### Application: ApproximateGonzalezDebug" << std::endl;
  std::cout << "### Graph: " << P.getArgument(0) << std::endl;
  std::cout << "### Threads: " << num_workers() << std::endl;
  std::cout << "### n: " << G.n << std::endl;
  std::cout << "### m: " << G.m << std::endl;
  std::cout << "### Params:"
            << " -k=" << k
            << " -epsilon=" << epsilon
            << " -delta=" << delta
            << " -nb=" << num_buckets
            << " -cap=" << dist_cap
            << " -seed=" << seed
            << " -verbose=" << verbose << std::endl;
  std::cout << "### ------------------------------------" << std::endl;

  if (num_buckets != (((uintE)1) << parlay::log2_up(num_buckets))) {
    std::cout << "Please specify a number of buckets that is a power of two\n";
    exit(-1);
  }

  if (epsilon <= 0.0) {
    std::cout << "ApproximateGonzalezDebug: epsilon must be > 0" << std::endl;
    exit(-1);
  }

  constexpr Distance kMaxWeight = std::numeric_limits<Distance>::max();
  const size_t n = G.n;
  const double alpha = 1.0 + 0.5 * epsilon;
  const double D_bound = static_cast<double>(n) / epsilon;
  const double R = static_cast<double>(n) * D_bound;
  const size_t B = std::max<size_t>(
      1, static_cast<size_t>(std::ceil(std::log(R) / std::log(alpha))));

  auto dist = sequence<Distance>(n, kMaxWeight);
  AlphaBucketState<Distance> alpha_state(n, alpha, B, kMaxWeight);
  alpha_state.initialize_all_unreachable();

  std::mt19937_64 rng;
  if (seed >= 0) {
    rng.seed(static_cast<uint64_t>(seed));
  } else {
    rng.seed(static_cast<uint64_t>(
        std::chrono::high_resolution_clock::now().time_since_epoch().count()));
  }

  bool all_ok = true;

  all_ok &= CheckInitialization(alpha_state, n, true);
  all_ok &= CheckBucketStructure(alpha_state, dist, true);

  sequence<uintE> centers_out(k);
  std::vector<uintE> centers_so_far;
  centers_so_far.reserve(k);

  size_t bmax = B;
  size_t num_centers = 0;

  timer t;
  t.start();

  while (num_centers < k) {
    while (bmax >= 1 && alpha_state.bucket_empty(bmax)) {
      --bmax;
    }
    if (bmax == 0) break;

    auto& bucket = alpha_state.H[bmax];
    std::uniform_int_distribution<size_t> dist_idx(0, bucket.size() - 1);
    uintE v = bucket[dist_idx(rng)];

    std::cout << "\n=== Round " << (num_centers + 1) << " ===" << std::endl;
    std::cout << "Current highest non-empty bucket: " << bmax
              << ", size = " << bucket.size() << std::endl;

    all_ok &= CheckBucketStructure(alpha_state, dist, verbose);
    all_ok &= CheckChosenCenter(alpha_state, v, bmax, true);

    auto old_dist =
        sequence<Distance>::from_function(n, [&](size_t i) { return dist[i]; });
    auto old_bucket_of = sequence<size_t>::from_function(
        n, [&](size_t i) { return alpha_state.bucket_of[i]; });

    alpha_state.set_center(v);
    centers_out[num_centers++] = v;
    centers_so_far.push_back(v);

    std::cout << "Chosen center: " << v << std::endl;

    auto changed = sequence<uint8_t>(n, static_cast<uint8_t>(0));

    auto seed_pairs = sequence<std::pair<uintE, Distance>>(1);
    seed_pairs[0] = std::make_pair(v, static_cast<Distance>(0));

    DeltaSteppingRepairImpl(G, dist, seed_pairs, delta, num_buckets, dist_cap,
                            &changed);

    all_ok &= CheckChangedSet(old_dist, dist, changed, true);
    all_ok &= CheckBucketMovesBeforeReconcile(alpha_state, old_dist, dist,
                                             old_bucket_of, changed, verbose);

    auto changed_vertices = parlay::filter(
        parlay::tabulate(n, [&](size_t i) { return static_cast<uintE>(i); }),
        [&](uintE x) { return changed[x] != 0; });

    size_t num_moved = 0;
    for (size_t i = 0; i < changed_vertices.size(); ++i) {
      uintE x = changed_vertices[i];
      if (alpha_state.is_center[x]) continue;
      if (dist[x] < old_dist[x]) {
        size_t before_bucket = alpha_state.bucket_of[x];
        size_t expected_new_bucket =
            debug_distance_to_bucket(alpha_state, dist[x]);

        alpha_state.update_vertex_distance(x, dist[x]);

        size_t after_bucket = alpha_state.bucket_of[x];
        if (after_bucket != expected_new_bucket) {
          std::cout << "[FAIL] Reconcile: vertex " << x
                    << " ended in bucket " << after_bucket
                    << " but expected " << expected_new_bucket << std::endl;
          all_ok = false;
        }

        if (before_bucket != after_bucket) ++num_moved;
      }
    }

    std::cout << "Improved vertices this round: "
              << parlay::reduce(parlay::delayed_seq<size_t>(
                     n, [&](size_t i) { return changed[i] ? size_t(1) : size_t(0); }))
              << std::endl;
    std::cout << "Vertices moved across bucket boundaries this round: "
              << num_moved << std::endl;

    all_ok &= CheckBucketStructure(alpha_state, dist, true);

    size_t true_bmax_after = ComputeHighestNonEmptyBucket(alpha_state);
    std::cout << "Highest non-empty bucket after reconcile: "
              << true_bmax_after << std::endl;

    // Strong semantic check
    auto exact_dist = ComputeExactNearestCenterDistancesFromScratch<Graph, Distance>(
        G, centers_so_far, delta, num_buckets, dist_cap);
    all_ok &=
        CheckExactNearestCenterDistances(dist, exact_dist, centers_so_far, true);

    bmax = std::min(bmax, true_bmax_after == 0 ? size_t(0) : true_bmax_after);
  }

  double tt = t.stop();

  std::cout << "\n### Final centers:";
  for (size_t i = 0; i < num_centers; ++i) {
    std::cout << " " << centers_out[i];
  }
  std::cout << std::endl;

  std::cout << "### Running Time: " << tt << std::endl;

  if (all_ok) {
    std::cout << "\n[OK] All ApproximateGonzalez debug checks passed."
              << std::endl;
  } else {
    std::cout << "\n[FAIL] At least one ApproximateGonzalez debug check failed."
              << std::endl;
  }

  return tt;
}

}  // namespace gbbs

generate_weighted_main(gbbs::ApproximateGonzalezDebug_runner, false);