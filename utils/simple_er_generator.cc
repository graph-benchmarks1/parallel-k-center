#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <vector>

namespace {

uint64_t splitmix64(uint64_t x) {
  x += 0x9e3779b97f4a7c15ULL;
  x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
  x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
  return x ^ (x >> 31);
}

void usage(const char* name) {
  std::cerr
      << "Usage:\n"
      << "  " << name
      << " <n> <m_undirected> <seed> <max_weight> "
      << "<out_unweighted> <out_weighted>\n\n"
      << "Writes exactly m_undirected distinct undirected edges u v,\n"
      << "and a weighted copy u v w with weights in [1,max_weight].\n";
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 7) {
    usage(argv[0]);
    return 1;
  }

  const uint64_t n = std::stoull(argv[1]);
  const uint64_t m = std::stoull(argv[2]);
  const uint64_t seed = std::stoull(argv[3]);
  const uint64_t max_weight = std::stoull(argv[4]);
  const std::string out_unweighted = argv[5];
  const std::string out_weighted = argv[6];

  if (n < 2 || m == 0 || max_weight == 0) {
    std::cerr << "Invalid parameters.\n";
    return 1;
  }

  const long double max_edges =
      (static_cast<long double>(n) * static_cast<long double>(n - 1)) / 2.0L;
  if (static_cast<long double>(m) > max_edges) {
    std::cerr << "Requested more edges than possible simple undirected edges.\n";
    return 1;
  }

  std::mt19937_64 rng(seed);
  std::uniform_int_distribution<uint64_t> vertex_dist(0, n - 1);

  std::vector<uint64_t> edges;
  edges.reserve(m);

  while (edges.size() < m) {
    const uint64_t need = m - edges.size();
    const uint64_t batch = std::max<uint64_t>(need + need / 100 + 1024, 4096);

    for (uint64_t i = 0; i < batch; ++i) {
      uint64_t u = vertex_dist(rng);
      uint64_t v = vertex_dist(rng);

      if (u == v) continue;
      if (u > v) std::swap(u, v);

      edges.push_back(u * n + v);
    }

    std::sort(edges.begin(), edges.end());
    edges.erase(std::unique(edges.begin(), edges.end()), edges.end());

    std::cerr << "distinct_edges=" << edges.size()
              << " target=" << m << std::endl;
  }

  if (edges.size() > m) {
    std::shuffle(edges.begin(), edges.end(), rng);
    edges.resize(m);
    std::sort(edges.begin(), edges.end());
  }

  std::ofstream fout_u(out_unweighted);
  std::ofstream fout_w(out_weighted);

  if (!fout_u) {
    std::cerr << "Could not open unweighted output: " << out_unweighted << "\n";
    return 1;
  }

  if (!fout_w) {
    std::cerr << "Could not open weighted output: " << out_weighted << "\n";
    return 1;
  }

  for (uint64_t key : edges) {
    const uint64_t u = key / n;
    const uint64_t v = key % n;
    const uint64_t w =
        (splitmix64(key ^ seed ^ 0xdeadbeefcafebabeULL) % max_weight) + 1;

    fout_u << u << ' ' << v << '\n';
    fout_w << u << ' ' << v << ' ' << w << '\n';
  }

  std::cerr << "done edges=" << m << "\n";
  return 0;
}
