#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ABBOUD_SELECT_EXPERIMENTS = {
    "p10_full_sweep_large_synthetic",
    "p11_full_sweep_social",
}

RELATIVE_QUALITY_EXPERIMENTS = {
    "p2_approx_epsilon_synthetic",
    "p3_approx_epsilon_real",
    "p9_full_sweep_small_synthetic",
    "p10_full_sweep_large_synthetic",
    "p11_full_sweep_social",
    "p12_full_sweep_roads",
    "p13_full_sweep_ratings",
}

USABLE_STATUSES = {"OK", "PARTIAL"}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    return p.parse_args()


def read_tsv(path: Path):
    if not path.is_file():
        raise SystemExit(f"ERROR: input TSV not found: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if reader.fieldnames is None:
            raise SystemExit(f"ERROR: no TSV header in {path}")
        rows = list(reader)
        return reader.fieldnames, rows


def graph_key(row: Dict[str, str]) -> str:
    # Hierarchical P9 uses graph_group; other experiments use graph.
    return row.get("graph_group") or row.get("graph") or ""


def finite_float(raw: str):
    if raw == "":
        return None
    try:
        x = float(raw)
    except ValueError:
        raise SystemExit(f"ERROR: expected numeric value, got {raw!r}")
    return x


def usable(row: Dict[str, str]) -> bool:
    return row.get("status", "") in USABLE_STATUSES and finite_float(
        row.get("median_runtime_s", "")
    ) is not None


def abboud_point_key(row: Dict[str, str]) -> Tuple[str, ...]:
    # Ignore execution mode/thread count when comparing Abboud's two versions.
    # Preserve all graph/problem and algorithm-parameter dimensions that can
    # define a paper point.
    return (
        row.get("experiment_id", ""),
        graph_key(row),
        row.get("graph_type", ""),
        row.get("k", ""),
        row.get("delta", ""),
        row.get("epsilon", ""),
        row.get("rpp_token", ""),
        row.get("rpp_value", ""),
    )


def choose_abboud(rows: Sequence[Dict[str, str]]) -> Dict[str, str]:
    usable_rows = [r for r in rows if usable(r)]
    if usable_rows:
        # Lowest aggregated median runtime wins.  Deterministic tie-break:
        # parallel before single-core, then lower numeric thread count.
        def key(r):
            rt = float(r["median_runtime_s"])
            mode_rank = 0 if r.get("mode") == "parallel" else 1
            try:
                threads = int(r.get("threads") or "999999")
            except ValueError:
                threads = 999999
            return (rt, mode_rank, threads)
        chosen = min(usable_rows, key=key)
    else:
        # Neither mode produced a usable timing. Keep one deterministic row so
        # the missing paper point remains explicit rather than disappearing.
        def failure_rank(r):
            status_rank = {
                "TIMEOUT": 0,
                "FAIL": 1,
                "NO_OK": 2,
                "": 3,
            }.get(r.get("status", ""), 4)
            mode_rank = 0 if r.get("mode") == "parallel" else 1
            return (status_rank, mode_rank)
        chosen = min(rows, key=failure_rank)

    out = dict(chosen)
    out["abboud_selected_mode"] = chosen.get("mode", "")
    out["abboud_selected_threads"] = chosen.get("threads", "")
    out["abboud_candidate_count"] = str(len(rows))
    return out


def select_abboud_modes(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    passthrough = []
    groups = defaultdict(list)

    for row in rows:
        if (
            row.get("experiment_id") in ABBOUD_SELECT_EXPERIMENTS
            and row.get("algorithm") == "abboud"
        ):
            groups[abboud_point_key(row)].append(row)
        else:
            out = dict(row)
            out.setdefault("abboud_selected_mode", "")
            out.setdefault("abboud_selected_threads", "")
            out.setdefault("abboud_candidate_count", "")
            passthrough.append(out)

    for key in sorted(groups):
        passthrough.append(choose_abboud(groups[key]))

    return passthrough


def baseline_key(row: Dict[str, str]) -> Tuple[str, ...]:
    # Relative solution quality is defined by graph and k in the paper.
    # For P2/P3 the Approximate-Gonzalez epsilon varies but the Gonzalez
    # baseline does not, so epsilon must intentionally not be part of this key.
    return (
        row.get("experiment_id", ""),
        graph_key(row),
        row.get("graph_type", ""),
        row.get("k", ""),
    )


def add_relative_radius(rows: List[Dict[str, str]]) -> None:
    baselines = defaultdict(list)
    for row in rows:
        if (
            row.get("experiment_id") in RELATIVE_QUALITY_EXPERIMENTS
            and row.get("algorithm") == "gonzalez"
        ):
            baselines[baseline_key(row)].append(row)

    for row in rows:
        row["gonzalez_radius"] = ""
        row["relative_radius"] = ""
        row["quality_status"] = "NOT_APPLICABLE"

        if row.get("experiment_id") not in RELATIVE_QUALITY_EXPERIMENTS:
            continue

        key = baseline_key(row)
        candidates = baselines.get(key, [])
        usable_baselines = [
            b for b in candidates
            if b.get("status") in USABLE_STATUSES
            and finite_float(b.get("median_max_dist_to_centers", "")) is not None
        ]

        # Full-sweep/parameter specs should provide one Gonzalez baseline per
        # graph/k point. Ambiguity is a data/spec error and must not be hidden.
        if len(usable_baselines) > 1:
            raise SystemExit(
                "ERROR: multiple usable Gonzalez baselines for "
                f"experiment={key[0]} graph={key[1]} type={key[2]} k={key[3]}"
            )
        if not usable_baselines:
            row["quality_status"] = "NO_GONZALEZ_BASELINE"
            continue

        baseline = usable_baselines[0]
        g_radius = finite_float(baseline["median_max_dist_to_centers"])
        a_radius = finite_float(row.get("median_max_dist_to_centers", ""))

        row["gonzalez_radius"] = f"{g_radius:.12g}"

        if row.get("status") not in USABLE_STATUSES or a_radius is None:
            row["quality_status"] = "NO_ALGORITHM_RADIUS"
            continue
        if g_radius == 0:
            row["quality_status"] = "ZERO_GONZALEZ_RADIUS"
            continue
        if not math.isfinite(g_radius) or not math.isfinite(a_radius):
            row["quality_status"] = "NONFINITE_RADIUS"
            continue

        row["relative_radius"] = f"{a_radius / g_radius:.12g}"
        row["quality_status"] = "OK"


def main():
    args = parse_args()
    fields, rows = read_tsv(args.input)
    if not rows:
        raise SystemExit("ERROR: input contains no rows")

    rows = select_abboud_modes(rows)
    add_relative_radius(rows)

    extra = [
        "abboud_selected_mode",
        "abboud_selected_threads",
        "abboud_candidate_count",
        "gonzalez_radius",
        "relative_radius",
        "quality_status",
    ]
    output_fields = list(fields)
    for field in extra:
        if field not in output_fields:
            output_fields.append(field)

    # Stable order for reviewer-readable diffs.
    rows.sort(key=lambda r: (
        r.get("experiment_id", ""),
        graph_key(r),
        r.get("graph_type", ""),
        int(r.get("k") or 0),
        r.get("algorithm", ""),
        r.get("epsilon", ""),
        r.get("mode", ""),
        r.get("threads", ""),
    ))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(
            f, fieldnames=output_fields, delimiter="\t", lineterminator="\n"
        )
        w.writeheader()
        w.writerows(rows)

    print(f"Wrote paper-facing derived results: {args.output}")
    exps = sorted(set(r.get("experiment_id", "") for r in rows))
    if any(e in ABBOUD_SELECT_EXPERIMENTS for e in exps):
        print("Applied Abboud faster-mode selection for P10/P11.")
    if any(e in RELATIVE_QUALITY_EXPERIMENTS for e in exps):
        print("Computed solution radius relative to Gonzalez where defined.")


if __name__ == "__main__":
    main()
