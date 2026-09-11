#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <queue>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
#include <unistd.h>

namespace fs = std::filesystem;

namespace {

constexpr uint32_t kMissingVertex = std::numeric_limits<uint32_t>::max();

struct CanonicalEdge {
  uint32_t u;
  uint32_t v;
  int64_t w;
};

struct DirectedEdge {
  uint32_t u;
  uint32_t v;
  int64_t w;
};

bool CanonicalLess(const CanonicalEdge& a, const CanonicalEdge& b) {
  return std::tie(a.u, a.v) < std::tie(b.u, b.v);
}

bool DirectedLess(const DirectedEdge& a, const DirectedEdge& b) {
  return std::tie(a.u, a.v) < std::tie(b.u, b.v);
}

template <class T>
void WriteBinary(std::ofstream& out, const T& value) {
  out.write(reinterpret_cast<const char*>(&value), sizeof(T));
  if (!out) throw std::runtime_error("Failed to write temporary file");
}

template <class T>
bool ReadBinary(std::ifstream& in, T* value) {
  in.read(reinterpret_cast<char*>(value), sizeof(T));
  if (in.gcount() == 0 && in.eof()) return false;
  if (!in) throw std::runtime_error("Truncated temporary file");
  return true;
}

uint64_t ParseU64Line(std::istream& in, const char* what) {
  std::string line;
  if (!std::getline(in, line)) {
    throw std::runtime_error(std::string("Unexpected EOF while reading ") + what);
  }
  try {
    size_t pos = 0;
    const auto value = std::stoull(line, &pos);
    if (pos != line.size()) throw std::invalid_argument("trailing characters");
    return value;
  } catch (const std::exception&) {
    throw std::runtime_error(std::string("Invalid integer while reading ") + what + ": " + line);
  }
}

int64_t ParseI64Line(std::istream& in, const char* what) {
  std::string line;
  if (!std::getline(in, line)) {
    throw std::runtime_error(std::string("Unexpected EOF while reading ") + what);
  }
  try {
    size_t pos = 0;
    const auto value = std::stoll(line, &pos);
    if (pos != line.size()) throw std::invalid_argument("trailing characters");
    return value;
  } catch (const std::exception&) {
    throw std::runtime_error(std::string("Invalid integer while reading ") + what + ": " + line);
  }
}

struct InputLayout {
  std::string header;
  bool weighted = false;
  uint64_t n = 0;
  uint64_t m = 0;
  std::streampos offsets_pos{};
  std::streampos neighbors_pos{};
  std::streampos weights_pos{};
};

InputLayout ScanLayout(const fs::path& input) {
  std::ifstream in(input);
  if (!in) throw std::runtime_error("Cannot open input file: " + input.string());

  InputLayout layout;
  if (!std::getline(in, layout.header)) throw std::runtime_error("Input file is empty");
  if (layout.header != "AdjacencyGraph" && layout.header != "WeightedAdjacencyGraph") {
    throw std::runtime_error("Unexpected header: " + layout.header);
  }
  layout.weighted = layout.header == "WeightedAdjacencyGraph";
  layout.n = ParseU64Line(in, "vertex count");
  layout.m = ParseU64Line(in, "edge-entry count");
  if (layout.n > kMissingVertex) {
    throw std::runtime_error("This cleaner currently supports fewer than 2^32 vertices");
  }

  layout.offsets_pos = in.tellg();
  for (uint64_t i = 0; i < layout.n; ++i) ParseU64Line(in, "offset");
  layout.neighbors_pos = in.tellg();
  for (uint64_t i = 0; i < layout.m; ++i) ParseU64Line(in, "neighbor");
  layout.weights_pos = in.tellg();
  return layout;
}

struct TempDir {
  fs::path path;
  bool keep = false;
  ~TempDir() {
    if (!keep && !path.empty()) {
      std::error_code ec;
      fs::remove_all(path, ec);
    }
  }
};

fs::path MakeTempDir(const fs::path& output) {
  fs::path parent = output.parent_path();
  if (parent.empty()) parent = ".";
  fs::create_directories(parent);
  const std::string base = output.filename().string() + ".clean_tmp." + std::to_string(::getpid());
  fs::path dir = parent / base;
  fs::remove_all(dir);
  fs::create_directories(dir);
  return dir;
}

void SortAndDedupCanonicalChunk(std::vector<CanonicalEdge>* edges, bool weighted) {
  auto& v = *edges;
  std::sort(v.begin(), v.end(), CanonicalLess);
  size_t out = 0;
  for (size_t i = 0; i < v.size();) {
    size_t j = i + 1;
    int64_t best = v[i].w;
    while (j < v.size() && v[j].u == v[i].u && v[j].v == v[i].v) {
      if (weighted) best = std::min(best, v[j].w);
      ++j;
    }
    v[out++] = CanonicalEdge{v[i].u, v[i].v, best};
    i = j;
  }
  v.resize(out);
}

fs::path FlushCanonicalChunk(std::vector<CanonicalEdge>* edges, bool weighted,
                             const fs::path& temp_dir, size_t chunk_id) {
  SortAndDedupCanonicalChunk(edges, weighted);
  fs::path path = temp_dir / ("canonical_chunk_" + std::to_string(chunk_id) + ".bin");
  std::ofstream out(path, std::ios::binary);
  if (!out) throw std::runtime_error("Cannot create temporary file: " + path.string());
  for (const auto& e : *edges) WriteBinary(out, e);
  edges->clear();
  return path;
}

struct CanonicalCursor {
  std::ifstream in;
  CanonicalEdge edge{};
  size_t id = 0;
};

struct CanonicalCursorGreater {
  bool operator()(const CanonicalCursor* a, const CanonicalCursor* b) const {
    if (CanonicalLess(b->edge, a->edge)) return true;
    if (CanonicalLess(a->edge, b->edge)) return false;
    return a->id > b->id;
  }
};

uint64_t MergeCanonicalChunks(const std::vector<fs::path>& chunks,
                              const fs::path& canonical_path, bool weighted,
                              std::vector<uint8_t>* active) {
  std::vector<CanonicalCursor> cursors(chunks.size());
  std::priority_queue<CanonicalCursor*, std::vector<CanonicalCursor*>, CanonicalCursorGreater> pq;

  for (size_t i = 0; i < chunks.size(); ++i) {
    cursors[i].id = i;
    cursors[i].in.open(chunks[i], std::ios::binary);
    if (!cursors[i].in) throw std::runtime_error("Cannot open temporary chunk");
    if (ReadBinary(cursors[i].in, &cursors[i].edge)) pq.push(&cursors[i]);
  }

  std::ofstream out(canonical_path, std::ios::binary);
  if (!out) throw std::runtime_error("Cannot create canonical edge file");

  uint64_t count = 0;
  while (!pq.empty()) {
    CanonicalCursor* cur = pq.top();
    pq.pop();
    const uint32_t u = cur->edge.u;
    const uint32_t v = cur->edge.v;
    int64_t best = cur->edge.w;

    if (ReadBinary(cur->in, &cur->edge)) pq.push(cur);

    while (!pq.empty() && pq.top()->edge.u == u && pq.top()->edge.v == v) {
      CanonicalCursor* same = pq.top();
      pq.pop();
      if (weighted) best = std::min(best, same->edge.w);
      if (ReadBinary(same->in, &same->edge)) pq.push(same);
    }

    WriteBinary(out, CanonicalEdge{u, v, best});
    (*active)[u] = 1;
    (*active)[v] = 1;
    ++count;
  }
  return count;
}

struct Stats {
  uint64_t raw_entries = 0;
  uint64_t raw_self_loops = 0;
  uint64_t bad_weights = 0;
};

std::vector<fs::path> BuildCanonicalChunks(const fs::path& input,
                                           const InputLayout& layout,
                                           const fs::path& temp_dir,
                                           uint64_t memory_bytes,
                                           Stats* stats) {
  std::ifstream offsets(input), neighbors(input), weights;
  offsets.seekg(layout.offsets_pos);
  neighbors.seekg(layout.neighbors_pos);
  if (layout.weighted) {
    weights.open(input);
    weights.seekg(layout.weights_pos);
  }

  const size_t capacity = std::max<uint64_t>(1, memory_bytes / sizeof(CanonicalEdge));
  std::vector<CanonicalEdge> buffer;
  buffer.reserve(capacity);
  std::vector<fs::path> chunks;

  uint64_t next_offset = layout.n == 0 ? 0 : ParseU64Line(offsets, "offset");
  if (layout.n > 0 && next_offset != 0) {
    throw std::runtime_error("First CSR offset must be zero");
  }
  uint64_t following_offset = layout.n > 1 ? ParseU64Line(offsets, "offset") : layout.m;
  if (following_offset < next_offset || following_offset > layout.m) {
    throw std::runtime_error("CSR offsets are not monotone or exceed m");
  }
  uint64_t u = 0;

  for (uint64_t idx = 0; idx < layout.m; ++idx) {
    while (u + 1 < layout.n && idx >= following_offset) {
      ++u;
      next_offset = following_offset;
      following_offset = (u + 1 < layout.n) ? ParseU64Line(offsets, "offset") : layout.m;
      if (following_offset < next_offset || following_offset > layout.m) {
        throw std::runtime_error("CSR offsets are not monotone or exceed m");
      }
    }

    const uint64_t v64 = ParseU64Line(neighbors, "neighbor");
    const int64_t w = layout.weighted ? ParseI64Line(weights, "weight") : 1;
    ++stats->raw_entries;

    if (v64 >= layout.n) {
      throw std::runtime_error("Bad neighbor id " + std::to_string(v64) +
                               " at edge index " + std::to_string(idx));
    }
    if (layout.weighted && w <= 0) ++stats->bad_weights;
    if (u == v64) {
      ++stats->raw_self_loops;
      continue;
    }

    const uint32_t v = static_cast<uint32_t>(v64);
    const uint32_t a = std::min(static_cast<uint32_t>(u), v);
    const uint32_t b = std::max(static_cast<uint32_t>(u), v);
    buffer.push_back(CanonicalEdge{a, b, w});
    if (buffer.size() == capacity) {
      chunks.push_back(FlushCanonicalChunk(&buffer, layout.weighted, temp_dir, chunks.size()));
    }
  }

  if (!buffer.empty()) {
    chunks.push_back(FlushCanonicalChunk(&buffer, layout.weighted, temp_dir, chunks.size()));
  }
  return chunks;
}

void FlushDirectedSorted(std::vector<DirectedEdge>* edges, const fs::path& path) {
  std::sort(edges->begin(), edges->end(), DirectedLess);
  std::ofstream out(path, std::ios::binary);
  if (!out) throw std::runtime_error("Cannot create directed sort chunk");
  for (const auto& e : *edges) WriteBinary(out, e);
  edges->clear();
}

struct DirectedCursor {
  std::ifstream in;
  DirectedEdge edge{};
  size_t id = 0;
};

struct DirectedCursorGreater {
  bool operator()(const DirectedCursor* a, const DirectedCursor* b) const {
    if (DirectedLess(b->edge, a->edge)) return true;
    if (DirectedLess(a->edge, b->edge)) return false;
    return a->id > b->id;
  }
};

void EmitSortedShard(const fs::path& shard, uint64_t memory_bytes,
                     const fs::path& temp_dir, size_t shard_id,
                     std::ofstream& neighbors_out, std::ofstream* weights_out,
                     std::ofstream& offsets_out, uint32_t* next_vertex,
                     uint64_t* directed_count) {
  const uint64_t file_bytes = fs::file_size(shard);
  const uint64_t record_count = file_bytes / sizeof(DirectedEdge);
  const size_t capacity = std::max<uint64_t>(1, memory_bytes / sizeof(DirectedEdge));

  std::vector<fs::path> chunks;
  std::ifstream in(shard, std::ios::binary);
  if (!in) throw std::runtime_error("Cannot open shard: " + shard.string());

  if (record_count <= capacity) {
    std::vector<DirectedEdge> all;
    all.reserve(static_cast<size_t>(record_count));
    DirectedEdge e;
    while (ReadBinary(in, &e)) all.push_back(e);
    std::sort(all.begin(), all.end(), DirectedLess);

    size_t pos = 0;
    while (pos < all.size()) {
      const uint32_t u = all[pos].u;
      while (*next_vertex <= u) {
        offsets_out << *directed_count << '\n';
        ++(*next_vertex);
      }
      while (pos < all.size() && all[pos].u == u) {
        neighbors_out << all[pos].v << '\n';
        if (weights_out) *weights_out << all[pos].w << '\n';
        ++(*directed_count);
        ++pos;
      }
    }
    return;
  }

  size_t chunk_id = 0;
  while (true) {
    std::vector<DirectedEdge> buffer;
    buffer.reserve(capacity);
    DirectedEdge e;
    while (buffer.size() < capacity && ReadBinary(in, &e)) buffer.push_back(e);
    if (buffer.empty()) break;
    fs::path p = temp_dir / ("shard_" + std::to_string(shard_id) + "_chunk_" +
                             std::to_string(chunk_id++) + ".bin");
    FlushDirectedSorted(&buffer, p);
    chunks.push_back(p);
  }

  std::vector<DirectedCursor> cursors(chunks.size());
  std::priority_queue<DirectedCursor*, std::vector<DirectedCursor*>, DirectedCursorGreater> pq;
  for (size_t i = 0; i < chunks.size(); ++i) {
    cursors[i].id = i;
    cursors[i].in.open(chunks[i], std::ios::binary);
    if (!cursors[i].in) throw std::runtime_error("Cannot open directed sort chunk");
    if (ReadBinary(cursors[i].in, &cursors[i].edge)) pq.push(&cursors[i]);
  }

  while (!pq.empty()) {
    DirectedCursor* cur = pq.top();
    pq.pop();
    const DirectedEdge e = cur->edge;
    while (*next_vertex <= e.u) {
      offsets_out << *directed_count << '\n';
      ++(*next_vertex);
    }
    neighbors_out << e.v << '\n';
    if (weights_out) *weights_out << e.w << '\n';
    ++(*directed_count);
    if (ReadBinary(cur->in, &cur->edge)) pq.push(cur);
  }

  for (const auto& p : chunks) fs::remove(p);
}

void AppendFile(std::ofstream& out, const fs::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("Cannot open temporary output component: " + path.string());
  out << in.rdbuf();
  if (!out) throw std::runtime_error("Failed while assembling output graph");
}

struct Options {
  fs::path input;
  fs::path output;
  uint64_t memory_mb = 512;
  size_t shards = 128;
  bool keep_temp = false;
};

Options ParseOptions(int argc, char** argv) {
  if (argc < 3) {
    throw std::runtime_error(
        "Usage: clean_csr_graph <input.adj> <output.adj> [--memory-mb N] [--shards N] [--keep-temp]");
  }
  Options o;
  o.input = argv[1];
  o.output = argv[2];
  for (int i = 3; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--memory-mb") {
      if (++i >= argc) throw std::runtime_error("--memory-mb requires a value");
      o.memory_mb = std::stoull(argv[i]);
    } else if (arg == "--shards") {
      if (++i >= argc) throw std::runtime_error("--shards requires a value");
      o.shards = std::stoull(argv[i]);
    } else if (arg == "--keep-temp") {
      o.keep_temp = true;
    } else {
      throw std::runtime_error("Unknown option: " + arg);
    }
  }
  if (o.memory_mb < 16) throw std::runtime_error("--memory-mb must be at least 16");
  if (o.shards == 0 || o.shards > 512) throw std::runtime_error("--shards must be in [1,512]");
  return o;
}

int Run(const Options& options) {
  std::cout << "Reading " << options.input.string() << '\n';
  const InputLayout layout = ScanLayout(options.input);
  const uint64_t memory_bytes = options.memory_mb * 1024ULL * 1024ULL;

  TempDir temp{MakeTempDir(options.output), options.keep_temp};
  Stats stats;
  const auto chunks = BuildCanonicalChunks(options.input, layout, temp.path, memory_bytes, &stats);

  std::vector<uint8_t> active(layout.n, 0);
  const fs::path canonical = temp.path / "canonical.bin";
  uint64_t unique_edges = 0;
  if (!chunks.empty()) {
    unique_edges = MergeCanonicalChunks(chunks, canonical, layout.weighted, &active);
  } else {
    std::ofstream empty(canonical, std::ios::binary);
  }
  for (const auto& p : chunks) fs::remove(p);

  if (stats.bad_weights != 0) {
    throw std::runtime_error("Weighted graph contains non-positive weights (" +
                             std::to_string(stats.bad_weights) + " entries)");
  }

  std::vector<uint32_t> old_to_new(layout.n, kMissingVertex);
  uint32_t new_n = 0;
  for (uint64_t u = 0; u < layout.n; ++u) {
    if (active[u]) old_to_new[u] = new_n++;
  }
  active.clear();
  active.shrink_to_fit();

  const size_t shard_count = std::max<size_t>(1, std::min<size_t>(options.shards, new_n == 0 ? 1 : new_n));
  const uint64_t vertices_per_shard = new_n == 0 ? 1 : (static_cast<uint64_t>(new_n) + shard_count - 1) / shard_count;
  std::vector<fs::path> shard_paths(shard_count);
  std::vector<std::ofstream> shard_out(shard_count);
  for (size_t i = 0; i < shard_count; ++i) {
    shard_paths[i] = temp.path / ("directed_shard_" + std::to_string(i) + ".bin");
    shard_out[i].open(shard_paths[i], std::ios::binary);
    if (!shard_out[i]) throw std::runtime_error("Cannot create directed shard");
  }

  {
    std::ifstream in(canonical, std::ios::binary);
    if (!in) throw std::runtime_error("Cannot reopen canonical edge file");
    CanonicalEdge e;
    while (ReadBinary(in, &e)) {
      const uint32_t u = old_to_new[e.u];
      const uint32_t v = old_to_new[e.v];
      const size_t su = std::min<size_t>(u / vertices_per_shard, shard_count - 1);
      const size_t sv = std::min<size_t>(v / vertices_per_shard, shard_count - 1);
      WriteBinary(shard_out[su], DirectedEdge{u, v, e.w});
      WriteBinary(shard_out[sv], DirectedEdge{v, u, e.w});
    }
  }
  for (auto& out : shard_out) out.close();
  old_to_new.clear();
  old_to_new.shrink_to_fit();
  fs::remove(canonical);

  const fs::path offsets_path = temp.path / "offsets.txt";
  const fs::path neighbors_path = temp.path / "neighbors.txt";
  const fs::path weights_path = temp.path / "weights.txt";
  std::ofstream offsets_out(offsets_path), neighbors_out(neighbors_path);
  std::ofstream weights_out;
  if (layout.weighted) weights_out.open(weights_path);
  if (!offsets_out || !neighbors_out || (layout.weighted && !weights_out)) {
    throw std::runtime_error("Cannot create temporary output components");
  }

  uint32_t next_vertex = 0;
  uint64_t directed_count = 0;
  for (size_t i = 0; i < shard_count; ++i) {
    EmitSortedShard(shard_paths[i], memory_bytes, temp.path, i, neighbors_out,
                    layout.weighted ? &weights_out : nullptr, offsets_out,
                    &next_vertex, &directed_count);
    fs::remove(shard_paths[i]);
  }
  while (next_vertex < new_n) {
    offsets_out << directed_count << '\n';
    ++next_vertex;
  }
  offsets_out.close();
  neighbors_out.close();
  if (layout.weighted) weights_out.close();

  if (directed_count != 2 * unique_edges) {
    throw std::runtime_error("Output is not symmetric as expected");
  }

  std::cout << "Writing " << options.output.string() << '\n';
  fs::create_directories(options.output.parent_path().empty() ? fs::path(".") : options.output.parent_path());
  std::ofstream out(options.output, std::ios::binary);
  if (!out) throw std::runtime_error("Cannot create output file: " + options.output.string());
  out << layout.header << '\n' << new_n << '\n' << directed_count << '\n';
  AppendFile(out, offsets_path);
  AppendFile(out, neighbors_path);
  if (layout.weighted) AppendFile(out, weights_path);
  out.close();

  const int64_t duplicate_or_asym = static_cast<int64_t>(stats.raw_entries) -
      static_cast<int64_t>(2 * unique_edges) - static_cast<int64_t>(stats.raw_self_loops);

  std::cout << "old_header=" << layout.header << '\n';
  std::cout << "old_n=" << layout.n << '\n';
  std::cout << "old_m=" << layout.m << '\n';
  std::cout << "new_n=" << new_n << '\n';
  std::cout << "new_m=" << directed_count << '\n';
  std::cout << "distinct_undirected_edges=" << unique_edges << '\n';
  std::cout << "removed_vertices=" << (layout.n - new_n) << '\n';
  std::cout << "removed_self_loop_entries=" << stats.raw_self_loops << '\n';
  std::cout << "removed_duplicate_or_asymmetric_entries=" << duplicate_or_asym << '\n';
  if (layout.weighted) {
    std::cout << "nonpositive_weight_entries_seen=" << stats.bad_weights << '\n';
  }
  if (options.keep_temp) std::cout << "temporary_directory=" << temp.path << '\n';
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    return Run(ParseOptions(argc, argv));
  } catch (const std::exception& e) {
    std::cerr << "Error: " << e.what() << '\n';
    return 1;
  }
}

