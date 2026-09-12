#!/usr/bin/env python3
"""Self-contained regression test for hierarchical median aggregation."""

from __future__ import annotations

import csv
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGG = ROOT / "artifact/scripts/aggregate_results.py"

HEADER = [
    "experiment_id","description","graph","graph_type","algorithm","k","mode",
    "threads","delta","epsilon","rpp_token","rpp_value","repetition","seed",
    "runtime_s","num_centers","max_dist_to_centers","unreachable_vertices",
    "fallback_calls","status","log"
]

def row(graph, rep, runtime, radius, status="OK"):
    return {
        "experiment_id": "p5_parallel_small_synthetic",
        "description": "fixture",
        "graph": graph,
        "graph_type": "unweighted",
        "algorithm": "gonzalez",
        "k": "20",
        "mode": "parallel",
        "threads": "8",
        "delta": "",
        "epsilon": "",
        "rpp_token": "",
        "rpp_value": "",
        "repetition": str(rep),
        "seed": str(41 + rep),
        "runtime_s": "" if status != "OK" else str(runtime),
        "num_centers": "" if status != "OK" else "20",
        "max_dist_to_centers": "" if status != "OK" else str(radius),
        "unreachable_vertices": "" if status != "OK" else "0",
        "fallback_calls": "",
        "status": status,
        "log": f"/tmp/fixture-{rep}.log",
    }

with tempfile.TemporaryDirectory(prefix="ae-aggregation-") as td:
    td = Path(td)
    inp = td / "runs.tsv"
    out = td / "out"

    rows = [
        row("Snap_unweighted/ER_small/er_n100000_d4_seed0.adj", 1, 1, 10),
        row("Snap_unweighted/ER_small/er_n100000_d4_seed0.adj", 2, 100, 30),
        row("Snap_unweighted/ER_small/er_n100000_d4_seed0.adj", 3, 3, 20),
        row("Snap_unweighted/ER_small/er_n100000_d4_seed1.adj", 1, 7, 40),
        row("Snap_unweighted/ER_small/er_n100000_d4_seed1.adj", 2, 8, 50),
        row("Snap_unweighted/ER_small/er_n100000_d4_seed1.adj", 3, 100, 60),
    ]

    with inp.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=HEADER, delimiter="\t", lineterminator="\n")
        w.writeheader()
        w.writerows(rows)

    subprocess.run(
        [sys.executable, str(AGG), "--input", str(inp), "--output-dir", str(out)],
        check=True,
    )

    with (out / "per_graph.tsv").open(newline="", encoding="utf-8") as f:
        pg = list(csv.DictReader(f, delimiter="\t"))
    assert len(pg) == 2, pg
    by_seed = {r["graph_instance_seed"]: r for r in pg}
    assert float(by_seed["0"]["median_runtime_s"]) == 3.0
    assert float(by_seed["0"]["median_max_dist_to_centers"]) == 20.0
    assert float(by_seed["1"]["median_runtime_s"]) == 8.0
    assert float(by_seed["1"]["median_max_dist_to_centers"]) == 50.0
    assert all(r["status"] == "OK" for r in pg)

    with (out / "aggregated.tsv").open(newline="", encoding="utf-8") as f:
        final = list(csv.DictReader(f, delimiter="\t"))
    assert len(final) == 1, final
    r = final[0]
    # median([median(1,100,3), median(7,8,100)]) = median([3,8]) = 5.5
    assert float(r["median_runtime_s"]) == 5.5, r
    # median([20,50]) = 35
    assert float(r["median_max_dist_to_centers"]) == 35.0, r
    assert r["graph_instances"] == "2"
    assert r["graph_instance_seeds"] == "0,1"
    assert r["complete_graph_instances"] == "2"
    assert r["status"] == "OK"

    print("PASS: repetition medians are correct")
    print("PASS: graph-seed medians are hierarchical, not flattened")
    print("PASS: runtime hierarchy  -> median([3, 8]) = 5.5")
    print("PASS: quality hierarchy  -> median([20, 50]) = 35")
    print("PASS: graph seed metadata/counts are retained")
    print()
    print("Aggregation validation PASSED.")
