#!/usr/bin/env python3
"""
Reconstruct the full-sweep runtime/quality figures from paper_results.tsv.

Supported experiment families:
  P9  -> Figures A.7 / A.8   (small synthetic)
  P10 -> Figures A.9 / A.10  (large synthetic)
  P11 -> Figures 7.3 / A.11  (social networks)
  P12 -> Figures 7.4 / 7.5   (road networks)
  P13 -> Figures A.12 / A.13 (rating networks)

The plotting stage consumes only paper_results.tsv. It does not recompute
medians or select Abboud modes; those decisions belong to the earlier
aggregation/derivation layers.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

TIMEOUT_SECONDS = 10800.0

ALGO_LABELS = {
    "gonzalez": "Gonzalez",
    "approximategonzalez": "Approx. Gonzalez",
    "abboud": "Abboud MIS",
    "thorupsimple": "Simplified Thorup",
}
ALGO_MARKERS = {
    "gonzalez": "o",
    "approximategonzalez": "s",
    "abboud": "^",
    "thorupsimple": "v",
}

@dataclass(frozen=True)
class Panel:
    title: str
    graph_token: str
    ks: Tuple[int, ...]
    k_labels: Tuple[str, ...]
    include_quality: bool = True

@dataclass(frozen=True)
class FigureSpec:
    experiment_id: str
    runtime_name: str
    quality_name: str
    panels: Tuple[Panel, ...]
    ncols: int
    split_abboud_runtime: bool = False


def synthetic_panels(n: int, ks: Sequence[int], sqrt_k: int, *, omit_quality_rho2: bool) -> Tuple[Panel, ...]:
    out = []
    for weighted in (False, True):
        suffix = "_w.adj" if weighted else ".adj"
        typ = "wgh." if weighted else "unw."
        for rho in (2, 4, 8, 16, 32, 64):
            # graph_token is a regex-like stable substring matched against graph/group.
            token = f"er_n{n}_d{rho}_"
            labels = tuple([str(k) for k in ks[:-1]] + [r"$\sqrt{n}$"])
            out.append(
                Panel(
                    title=rf"$\rho={rho}$, {typ}",
                    graph_token=token + ("weighted" if weighted else "unweighted"),
                    ks=tuple(ks[:-1]) + (sqrt_k,),
                    k_labels=labels,
                    include_quality=not (omit_quality_rho2 and rho == 2),
                )
            )
    return tuple(out)


P9_PANELS = synthetic_panels(100000, (20, 50, 100, 316), 316, omit_quality_rho2=False)
P10_PANELS = synthetic_panels(10000000, (20, 100, 500, 3162), 3162, omit_quality_rho2=True)

SPECS = {
    "p9_full_sweep_small_synthetic": FigureSpec(
        "p9_full_sweep_small_synthetic",
        "figure_A_7_runtime",
        "figure_A_8_quality",
        P9_PANELS,
        ncols=2,
    ),
    "p10_full_sweep_large_synthetic": FigureSpec(
        "p10_full_sweep_large_synthetic",
        "figure_A_9_runtime",
        "figure_A_10_quality",
        P10_PANELS,
        ncols=2,
        split_abboud_runtime=True,
    ),
    "p11_full_sweep_social": FigureSpec(
        "p11_full_sweep_social",
        "figure_7_3_runtime",
        "figure_A_11_quality",
        (
            Panel("DBLP", "com-dblp.adj", (20,100,563), ("20","100",r"$\sqrt{n}$")),
            Panel("YouTube", "com-youtube.adj", (20,100,500,1065), ("20","100","500",r"$\sqrt{n}$")),
            Panel("LiveJournal", "com-lj.adj", (20,100,500,1999), ("20","100","500",r"$\sqrt{n}$")),
            Panel("Orkut", "com-orkut.adj", (20,100,500,1752), ("20","100","500",r"$\sqrt{n}$")),
            Panel("Twitter", "twitter-2010.adj", (20,100,500,2000,6453), ("20","100","500","2000",r"$\sqrt{n}$")),
            Panel("Friendster", "com-friendster.adj", (20,100,500,2000,8099), ("20","100","500","2000",r"$\sqrt{n}$")),
        ),
        ncols=2,
        split_abboud_runtime=True,
    ),
    "p12_full_sweep_roads": FigureSpec(
        "p12_full_sweep_roads",
        "figure_7_4_runtime",
        "figure_7_5_quality",
        (
            Panel("USA-central", "USA-road-d.CTR.adj", (20,100,500,3700), ("20","100","500","3700")),
            Panel("USA-full", "USA-road-d.USA.adj", (20,100,500,5200), ("20","100","500","5200")),
        ),
        ncols=2,
    ),
    "p13_full_sweep_ratings": FigureSpec(
        "p13_full_sweep_ratings",
        "figure_A_12_runtime",
        "figure_A_13_quality",
        (
            Panel("libimseti", "libimseti.adj", (20,100,470), ("20","100",r"$\sqrt{n}$")),
            Panel("MovieLens", "movielens.adj", (20,100,643), ("20","100",r"$\sqrt{n}$")),
            Panel("Yahoo! Song", "yahoo-song.adj", (20,100,500,1275), ("20","100","500",r"$\sqrt{n}$")),
        ),
        ncols=2,
    ),
}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--experiment-id", required=True, choices=sorted(SPECS))
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output-dir", required=True, type=Path)
    return p.parse_args()


def read_rows(path: Path, experiment_id: str) -> List[Dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"ERROR: paper_results.tsv not found: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    rows = [r for r in rows if r.get("experiment_id") == experiment_id]
    if not rows:
        raise SystemExit(f"ERROR: no rows for {experiment_id} in {path}")
    return rows


def graph_name(row: Dict[str, str]) -> str:
    return row.get("graph_group") or row.get("graph") or ""


def matches_panel(row: Dict[str, str], panel: Panel) -> bool:
    g = graph_name(row)
    token = panel.graph_token
    if token.endswith("weighted"):
        base = token[:-8]
        return base in g and g.endswith("_w.adj")
    if token.endswith("unweighted"):
        base = token[:-10]
        return base in g and g.endswith(".adj") and not g.endswith("_w.adj")
    return token in g or Path(g).name == token


def finite_float(raw: str) -> Optional[float]:
    if raw in ("", None):
        return None
    try:
        x = float(raw)
    except ValueError:
        return None
    return x if math.isfinite(x) else None


def point_map(rows, panel):
    result = {}
    for row in rows:
        if not matches_panel(row, panel):
            continue
        try:
            k = int(row.get("k", ""))
        except ValueError:
            continue
        key = (row.get("algorithm", ""), k)
        if key in result:
            raise SystemExit(f"ERROR: duplicate point after derivation: {panel.title} {key}")
        result[key] = row
    return result


def plot_series(ax, xs, ys, *, label, marker):
    if xs:
        ax.plot(xs, ys, marker=marker, label=label)


def runtime_panel(ax, rows, panel: Panel, split_abboud: bool):
    idx = point_map(rows, panel)
    xpos = list(range(len(panel.ks)))

    for algo in ("gonzalez", "approximategonzalez", "thorupsimple"):
        xs, ys = [], []
        tx, ty = [], []
        for x, k in zip(xpos, panel.ks):
            row = idx.get((algo, k))
            if not row:
                continue
            rt = finite_float(row.get("median_runtime_s", ""))
            if row.get("status") in {"OK", "PARTIAL"} and rt is not None:
                xs.append(x); ys.append(rt)
            elif row.get("status") == "TIMEOUT":
                tx.append(x); ty.append(TIMEOUT_SECONDS)
        plot_series(ax, xs, ys, label=ALGO_LABELS[algo], marker=ALGO_MARKERS[algo])
        if tx:
            ax.scatter(tx, ty, marker="x")

    if split_abboud:
        for mode, label, marker in (
            ("parallel", "Abboud MIS (parallel)", "^"),
            ("singlecore", "Abboud MIS (single-core)", "v"),
        ):
            xs, ys, tx, ty = [], [], [], []
            for x, k in zip(xpos, panel.ks):
                row = idx.get(("abboud", k))
                if not row or row.get("mode") != mode:
                    continue
                rt = finite_float(row.get("median_runtime_s", ""))
                if row.get("status") in {"OK", "PARTIAL"} and rt is not None:
                    xs.append(x); ys.append(rt)
                elif row.get("status") == "TIMEOUT":
                    tx.append(x); ty.append(TIMEOUT_SECONDS)
            plot_series(ax, xs, ys, label=label, marker=marker)
            if tx:
                ax.scatter(tx, ty, marker="x")
    else:
        xs, ys, tx, ty = [], [], [], []
        for x, k in zip(xpos, panel.ks):
            row = idx.get(("abboud", k))
            if not row:
                continue
            rt = finite_float(row.get("median_runtime_s", ""))
            if row.get("status") in {"OK", "PARTIAL"} and rt is not None:
                xs.append(x); ys.append(rt)
            elif row.get("status") == "TIMEOUT":
                tx.append(x); ty.append(TIMEOUT_SECONDS)
        plot_series(ax, xs, ys, label="Abboud MIS", marker="^")
        if tx:
            ax.scatter(tx, ty, marker="x")

    ax.set_yscale("log")
    ax.set_xticks(xpos, panel.k_labels)
    ax.set_xlabel("Number of centers $k$")
    ax.set_ylabel("Running time [s]")
    ax.set_title(panel.title)
    ax.grid(True, which="both", alpha=0.25)


def quality_panel(ax, rows, panel: Panel):
    idx = point_map(rows, panel)
    xpos = list(range(len(panel.ks)))
    for algo in ("gonzalez", "approximategonzalez", "abboud", "thorupsimple"):
        xs, ys = [], []
        for x, k in zip(xpos, panel.ks):
            row = idx.get((algo, k))
            if not row or row.get("quality_status") != "OK":
                continue
            rel = finite_float(row.get("relative_radius", ""))
            if rel is not None:
                xs.append(x); ys.append(100.0 * rel)
        plot_series(ax, xs, ys, label=ALGO_LABELS[algo], marker=ALGO_MARKERS[algo])
    ax.axhline(100.0, linestyle="--", linewidth=1)
    ax.set_xticks(xpos, panel.k_labels)
    ax.set_xlabel("Number of centers $k$")
    ax.set_ylabel("Radius relative to Gonzalez")
    ax.yaxis.set_major_formatter(lambda x, pos: f"{x:g}%")
    ax.set_title(panel.title)
    ax.grid(True, alpha=0.25)


def unique_legend(fig, axes, *, ncol):
    handles, labels = [], []
    seen = set()
    for ax in axes:
        h, l = ax.get_legend_handles_labels()
        for hh, ll in zip(h, l):
            if ll not in seen:
                seen.add(ll); handles.append(hh); labels.append(ll)
    if handles:
        fig.legend(handles, labels, loc="upper center", ncol=ncol, fontsize=8)


def make_figure(rows, spec: FigureSpec, *, quality: bool, outbase: Path):
    panels = [p for p in spec.panels if (p.include_quality or not quality)]
    ncols = spec.ncols
    nrows = math.ceil(len(panels) / ncols)
    fig, axes_grid = plt.subplots(
        nrows, ncols,
        figsize=(7.2, max(3.0, 2.35 * nrows)),
        squeeze=False,
    )
    axes = list(axes_grid.flat)
    for ax, panel in zip(axes, panels):
        if quality:
            quality_panel(ax, rows, panel)
        else:
            runtime_panel(ax, rows, panel, spec.split_abboud_runtime)
    for ax in axes[len(panels):]:
        ax.set_visible(False)

    unique_legend(fig, axes[:len(panels)], ncol=5 if spec.split_abboud_runtime and not quality else 4)
    # Avoid mixing constrained_layout with subplots_adjust; reserve a fixed top
    # band for the shared legend, then let tight_layout handle panel spacing.
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.94))

    pdf = outbase.with_suffix(".pdf")
    png = outbase.with_suffix(".png")
    fig.savefig(pdf, bbox_inches="tight")
    fig.savefig(png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return pdf, png


def main():
    a = parse_args()
    spec = SPECS[a.experiment_id]
    rows = read_rows(a.input, a.experiment_id)
    a.output_dir.mkdir(parents=True, exist_ok=True)

    runtime = make_figure(
        rows, spec, quality=False, outbase=a.output_dir / spec.runtime_name
    )
    quality = make_figure(
        rows, spec, quality=True, outbase=a.output_dir / spec.quality_name
    )

    print(f"Generated {a.experiment_id} plotting output from supplied result data:")
    for p in runtime + quality:
        print(f"  {p}")


if __name__ == "__main__":
    main()
