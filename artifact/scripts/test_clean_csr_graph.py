#!/usr/bin/env python3
"""Regression test: C++ cleaner must match scripts/clean_csr_graph.py byte-for-byte."""

from pathlib import Path
import argparse
import random
import subprocess
import tempfile


def write_graph(path: Path, weighted: bool, n: int, adjacency):
    offsets, neighbors, weights = [], [], []
    for edges in adjacency:
        offsets.append(len(neighbors))
        for v, w in edges:
            neighbors.append(v)
            weights.append(w)

    with path.open("w") as out:
        out.write(("WeightedAdjacencyGraph" if weighted else "AdjacencyGraph") + "\n")
        out.write(f"{n}\n{len(neighbors)}\n")
        out.writelines(f"{x}\n" for x in offsets)
        out.writelines(f"{x}\n" for x in neighbors)
        if weighted:
            out.writelines(f"{x}\n" for x in weights)


def run_case(repo: Path, binary: Path, work: Path, weighted: bool, seed: int):
    rng = random.Random(seed + (100000 if weighted else 0))
    n = rng.randint(8, 60)
    adjacency = [[] for _ in range(n)]

    # Arbitrary directed entries intentionally exercise asymmetric input,
    # duplicates, self-loops, isolates, and (for weighted graphs) different
    # weights on duplicate copies of the same undirected edge.
    for _ in range(rng.randint(100, 500)):
        u = rng.randrange(n)
        v = rng.randrange(n)
        w = rng.randint(1, 10000)
        adjacency[u].append((v, w))

    input_path = work / f"input_{weighted}_{seed}.adj"
    py_path = work / f"python_{weighted}_{seed}.adj"
    cpp_path = work / f"cpp_{weighted}_{seed}.adj"
    write_graph(input_path, weighted, n, adjacency)

    subprocess.run(
        ["python3", str(repo / "scripts/clean_csr_graph.py"), str(input_path), str(py_path)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(
        [str(binary), str(input_path), str(cpp_path), "--memory-mb", "16", "--shards", "2"],
        check=True,
        stdout=subprocess.DEVNULL,
    )

    if py_path.read_bytes() != cpp_path.read_bytes():
        raise RuntimeError(f"Mismatch for weighted={weighted}, seed={seed}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--binary", type=Path, default=None)
    parser.add_argument("--cases", type=int, default=8)
    args = parser.parse_args()

    repo = args.repo.resolve()
    binary = (args.binary or (repo / "artifact/bin/clean-csr-graph")).resolve()
    if not binary.is_file():
        raise SystemExit(f"Cleaner binary not found: {binary}")

    with tempfile.TemporaryDirectory(prefix="clean-csr-equivalence-") as tmp:
        work = Path(tmp)
        for weighted in (False, True):
            for seed in range(args.cases):
                run_case(repo, binary, work, weighted, seed)

    print(f"PASS: C++ cleaner matched Python byte-for-byte on {2 * args.cases} randomized cases.")


if __name__ == "__main__":
    main()

