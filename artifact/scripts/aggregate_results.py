#!/usr/bin/env python3
"""
Aggregate artifact experiment runs.

Paper rule:
  1. Repeated executions of one fixed graph/configuration are summarized by
     the median.
  2. For small synthetic experiments P5/P9, which use 10 independently
     generated graph instances per density, first compute the per-graph
     median over repetitions and then take the median of those per-graph
     medians.

Only rows with status=OK contribute numeric measurements. TIMEOUT/FAIL rows
remain visible through explicit status/count columns and are never converted
to numeric values.
"""

from __future__ import annotations

import argparse
import csv
import re
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

INPUT_COLUMNS = [
    "experiment_id",
    "description",
    "graph",
    "graph_type",
    "algorithm",
    "k",
    "mode",
    "threads",
    "delta",
    "epsilon",
    "rpp_token",
    "rpp_value",
    "repetition",
    "seed",
    "runtime_s",
    "num_centers",
    "max_dist_to_centers",
    "unreachable_vertices",
    "fallback_calls",
    "status",
    "log",
]

CONFIG_COLUMNS = [
    "experiment_id",
    "description",
    "graph",
    "graph_type",
    "algorithm",
    "k",
    "mode",
    "threads",
    "delta",
    "epsilon",
    "rpp_token",
    "rpp_value",
]

SECOND_STAGE_CONFIG_COLUMNS = [
    "experiment_id",
    "description",
    "graph_group",
    "graph_type",
    "algorithm",
    "k",
    "mode",
    "threads",
    "delta",
    "epsilon",
    "rpp_token",
    "rpp_value",
]

METRICS = [
    "runtime_s",
    "num_centers",
    "max_dist_to_centers",
    "unreachable_vertices",
    "fallback_calls",
]

HIERARCHICAL_EXPERIMENTS = {
    "p5_parallel_small_synthetic",
    "p9_full_sweep_small_synthetic",
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path, help="runner runs.tsv")
    p.add_argument("--output-dir", required=True, type=Path)
    p.add_argument(
        "--hierarchical",
        choices=("auto", "none", "graph-seed"),
        default="auto",
        help=(
            "auto: graph-seed hierarchy for P5/P9; none: only repetition "
            "medians; graph-seed: force a second median across graph seeds"
        ),
    )
    return p.parse_args()


def read_rows(path: Path) -> List[Dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"ERROR: input TSV not found: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if reader.fieldnames is None:
            raise SystemExit(f"ERROR: no TSV header in {path}")
        missing = [c for c in INPUT_COLUMNS if c not in reader.fieldnames]
        if missing:
            raise SystemExit(
                "ERROR: input TSV is missing required columns: " + ", ".join(missing)
            )
        return list(reader)


def graph_seed(graph: str) -> str:
    m = re.search(r"_seed(\d+)(?=(?:_w)?\.adj$)", graph)
    return m.group(1) if m else ""


def graph_group(graph: str) -> str:
    return re.sub(r"_seed\d+(?=(?:_w)?\.adj$)", "_seed*", graph)


def key_for(row: Dict[str, str], columns: Sequence[str]) -> tuple:
    return tuple(row.get(c, "") for c in columns)


def median_numeric(rows: Iterable[Dict[str, str]], metric: str) -> str:
    values = []
    for row in rows:
        if row.get("status") != "OK":
            continue
        raw = row.get(metric, "")
        if raw == "":
            continue
        try:
            values.append(float(raw))
        except ValueError:
            raise SystemExit(
                f"ERROR: non-numeric value for {metric}: {raw!r}"
            )
    if not values:
        return ""
    value = statistics.median(values)
    # Stable human-readable TSV; enough precision for measured runtimes.
    return f"{value:.12g}"


def outcome_status(rows: Sequence[Dict[str, str]]) -> str:
    statuses = [r.get("status", "") for r in rows]
    ok = statuses.count("OK")
    if ok == len(statuses) and statuses:
        return "OK"
    if ok > 0:
        return "PARTIAL"
    if statuses and all(s == "TIMEOUT" for s in statuses):
        return "TIMEOUT"
    if "FAIL" in statuses:
        return "FAIL"
    if "TIMEOUT" in statuses:
        return "TIMEOUT"
    return "NO_OK"


def aggregate_repetitions(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    groups: Dict[tuple, List[Dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[key_for(row, CONFIG_COLUMNS)].append(row)

    out = []
    for key in sorted(groups):
        group = groups[key]
        base = {c: group[0].get(c, "") for c in CONFIG_COLUMNS}
        base["graph_instance_seed"] = graph_seed(base["graph"])
        base["graph_group"] = graph_group(base["graph"])
        base["runs"] = str(len(group))
        base["ok_runs"] = str(sum(r.get("status") == "OK" for r in group))
        base["timeout_runs"] = str(sum(r.get("status") == "TIMEOUT" for r in group))
        base["fail_runs"] = str(sum(r.get("status") == "FAIL" for r in group))
        base["status"] = outcome_status(group)
        for metric in METRICS:
            base[f"median_{metric}"] = median_numeric(group, metric)
        out.append(base)
    return out


def second_stage_status(rows: Sequence[Dict[str, str]]) -> str:
    statuses = [r["status"] for r in rows]
    if statuses and all(s == "OK" for s in statuses):
        return "OK"
    usable = sum(int(r["ok_runs"]) > 0 for r in rows)
    if usable > 0:
        return "PARTIAL"
    if statuses and all(s == "TIMEOUT" for s in statuses):
        return "TIMEOUT"
    if "FAIL" in statuses:
        return "FAIL"
    return "NO_OK"


def median_of_per_graph(rows: Sequence[Dict[str, str]], metric: str) -> str:
    vals = []
    field = f"median_{metric}"
    for row in rows:
        # A graph instance contributes if at least one repetition succeeded.
        # The completeness counters make partial graph instances explicit.
        if int(row["ok_runs"]) <= 0:
            continue
        raw = row.get(field, "")
        if raw == "":
            continue
        vals.append(float(raw))
    if not vals:
        return ""
    return f"{statistics.median(vals):.12g}"


def aggregate_graph_instances(
    per_graph: List[Dict[str, str]]
) -> List[Dict[str, str]]:
    groups: Dict[tuple, List[Dict[str, str]]] = defaultdict(list)
    for row in per_graph:
        groups[key_for(row, SECOND_STAGE_CONFIG_COLUMNS)].append(row)

    out = []
    for key in sorted(groups):
        group = groups[key]
        base = {c: group[0].get(c, "") for c in SECOND_STAGE_CONFIG_COLUMNS}
        seeds = sorted(
            (r["graph_instance_seed"] for r in group if r["graph_instance_seed"]),
            key=lambda x: int(x),
        )
        base["graph_instances"] = str(len(group))
        base["graph_instance_seeds"] = ",".join(seeds)
        base["complete_graph_instances"] = str(
            sum(r["status"] == "OK" for r in group)
        )
        base["usable_graph_instances"] = str(
            sum(int(r["ok_runs"]) > 0 for r in group)
        )
        base["partial_graph_instances"] = str(
            sum(r["status"] == "PARTIAL" for r in group)
        )
        base["timeout_graph_instances"] = str(
            sum(r["status"] == "TIMEOUT" for r in group)
        )
        base["fail_graph_instances"] = str(
            sum(r["status"] == "FAIL" for r in group)
        )
        base["status"] = second_stage_status(group)
        for metric in METRICS:
            base[f"median_{metric}"] = median_of_per_graph(group, metric)
        out.append(base)
    return out


def write_tsv(path: Path, rows: List[Dict[str, str]], columns: Sequence[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f, fieldnames=list(columns), delimiter="\t", lineterminator="\n"
        )
        writer.writeheader()
        for row in rows:
            writer.writerow({c: row.get(c, "") for c in columns})


def main() -> None:
    args = parse_args()
    rows = read_rows(args.input)
    if not rows:
        raise SystemExit("ERROR: input TSV contains no runs")

    experiment_ids = sorted(set(r["experiment_id"] for r in rows))
    if args.hierarchical == "auto":
        do_hierarchical = (
            len(experiment_ids) == 1
            and experiment_ids[0] in HIERARCHICAL_EXPERIMENTS
        )
    else:
        do_hierarchical = args.hierarchical == "graph-seed"

    per_graph = aggregate_repetitions(rows)

    per_graph_columns = (
        CONFIG_COLUMNS
        + [
            "graph_instance_seed",
            "graph_group",
            "runs",
            "ok_runs",
            "timeout_runs",
            "fail_runs",
            "status",
        ]
        + [f"median_{m}" for m in METRICS]
    )
    per_graph_path = args.output_dir / "per_graph.tsv"
    write_tsv(per_graph_path, per_graph, per_graph_columns)

    print(f"Wrote repetition medians: {per_graph_path}")
    print("Rule: median over successful repetitions of each fixed graph/configuration.")

    if do_hierarchical:
        missing_seed = [
            r["graph"] for r in per_graph if not r["graph_instance_seed"]
        ]
        if missing_seed:
            preview = ", ".join(missing_seed[:3])
            raise SystemExit(
                "ERROR: graph-seed aggregation requested but graph seed could "
                f"not be parsed from: {preview}"
            )
        final = aggregate_graph_instances(per_graph)
        final_columns = (
            SECOND_STAGE_CONFIG_COLUMNS
            + [
                "graph_instances",
                "graph_instance_seeds",
                "complete_graph_instances",
                "usable_graph_instances",
                "partial_graph_instances",
                "timeout_graph_instances",
                "fail_graph_instances",
                "status",
            ]
            + [f"median_{m}" for m in METRICS]
        )
        final_path = args.output_dir / "aggregated.tsv"
        write_tsv(final_path, final, final_columns)
        print(f"Wrote graph-instance medians: {final_path}")
        print(
            "Rule: median of the per-graph medians across independent graph seeds."
        )
    else:
        final_path = args.output_dir / "aggregated.tsv"
        write_tsv(final_path, per_graph, per_graph_columns)
        print(f"Wrote final aggregation: {final_path}")
        print("No second graph-instance aggregation was requested.")


if __name__ == "__main__":
    main()
