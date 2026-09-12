#!/usr/bin/env python3
"""
Reconstruct parameter-choice Figures A.1--A.4.

Inputs:
  P1, P4: summary/aggregated.tsv
  P2, P3: summary/paper_results.tsv (for Gonzalez-relative quality)

This plotting layer does not recompute experiment statistics.
"""

from __future__ import annotations

import argparse
import csv
import math
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


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument(
        "--experiment-id",
        required=True,
        choices=[
            "p1_delta",
            "p2_approx_epsilon_synthetic",
            "p3_approx_epsilon_real",
            "p4_thorup_rpp",
        ],
    )
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output-dir", required=True, type=Path)
    return p.parse_args()


def read_rows(path: Path, experiment_id: str) -> List[Dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"ERROR: input TSV not found: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    rows = [r for r in rows if r.get("experiment_id") == experiment_id]
    if not rows:
        raise SystemExit(f"ERROR: no {experiment_id} rows in {path}")
    return rows


def graph_name(row: Dict[str, str]) -> str:
    return row.get("graph_group") or row.get("graph") or ""


def finite_float(raw: str) -> Optional[float]:
    if raw in ("", None):
        return None
    try:
        x = float(raw)
    except ValueError:
        return None
    return x if math.isfinite(x) else None


def save(fig, outdir: Path, stem: str):
    outdir.mkdir(parents=True, exist_ok=True)
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.94))
    pdf = outdir / f"{stem}.pdf"
    png = outdir / f"{stem}.png"
    fig.savefig(pdf, bbox_inches="tight")
    fig.savefig(png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return pdf, png


def shared_legend(fig, axes, ncol=4):
    seen = set()
    handles, labels = [], []
    for ax in axes:
        hs, ls = ax.get_legend_handles_labels()
        for h, l in zip(hs, ls):
            if l and l not in seen:
                seen.add(l)
                handles.append(h)
                labels.append(l)
    if handles:
        fig.legend(handles, labels, loc="upper center", ncol=ncol, fontsize=8)


def rows_for(rows, *, token=None, k=None, algo=None):
    out = []
    for r in rows:
        if token is not None and token not in graph_name(r):
            continue
        if k is not None and r.get("k") != str(k):
            continue
        if algo is not None and r.get("algorithm") != algo:
            continue
        out.append(r)
    return out


# ---------------------------------------------------------------------------
# P1 / Figure A.1
# ---------------------------------------------------------------------------

P1_PANELS = [
    ("er_n100000_d4_seed2_w.adj", 20,  r"$n=10^5,\ \rho=4,\ k=20$"),
    ("er_n100000_d8_seed2_w.adj", 20,  r"$n=10^5,\ \rho=8,\ k=20$"),
    ("er_n100000_d16_seed2_w.adj",20,  r"$n=10^5,\ \rho=16,\ k=20$"),
    ("er_n100000_d4_seed2_w.adj", 200, r"$n=10^5,\ \rho=4,\ k=200$"),
    ("er_n100000_d8_seed2_w.adj", 200, r"$n=10^5,\ \rho=8,\ k=200$"),
    ("er_n100000_d16_seed2_w.adj",200, r"$n=10^5,\ \rho=16,\ k=200$"),
    ("er_n10000000_d4_seed0_w.adj",200, r"$n=10^7,\ \rho=4,\ k=200$"),
    ("er_n10000000_d8_seed0_w.adj",200, r"$n=10^7,\ \rho=8,\ k=200$"),
    ("er_n10000000_d16_seed0_w.adj",200,r"$n=10^7,\ \rho=16,\ k=200$"),
    ("er_n10000000_d4_seed0_w.adj",2000,r"$n=10^7,\ \rho=4,\ k=2000$"),
    ("er_n10000000_d8_seed0_w.adj",2000,r"$n=10^7,\ \rho=8,\ k=2000$"),
    ("er_n10000000_d16_seed0_w.adj",2000,r"$n=10^7,\ \rho=16,\ k=2000$"),
]


def plot_p1(rows, outdir):
    fig, grid = plt.subplots(6, 2, figsize=(7.2, 11.0), squeeze=False)
    axes = list(grid.flat)
    deltas = [2, 4, 8, 16]

    for ax, (token, k, title) in zip(axes, P1_PANELS):
        subset = rows_for(rows, token=token, k=k)
        for algo in ("gonzalez", "approximategonzalez", "abboud"):
            by_delta = {int(r["delta"]): r for r in subset
                        if r.get("algorithm") == algo and r.get("delta")}
            xs, ys = [], []
            for d in deltas:
                r = by_delta.get(d)
                if not r:
                    continue
                y = finite_float(r.get("median_runtime_s", ""))
                if y is not None and r.get("status") in {"OK", "PARTIAL"}:
                    xs.append(d); ys.append(y)
            if xs:
                ax.plot(xs, ys, marker=ALGO_MARKERS[algo], label=ALGO_LABELS[algo])
        ax.set_xticks(deltas)
        ax.set_xlabel(r"$\Delta$")
        ax.set_ylabel("Running time [s]")
        ax.set_title(title, fontsize=9)
        ax.grid(True, alpha=0.25)

    shared_legend(fig, axes, ncol=3)
    return save(fig, outdir, "figure_A_1_delta")


# ---------------------------------------------------------------------------
# P2 / Figure A.2 and P3 / Figure A.3
# ---------------------------------------------------------------------------

EPS_VALUES_P2 = ["0.001", "0.01", "0.1", "0.5"]
EPS_VALUES_P3 = ["0.001", "0.5"]


def epsilon_label(eps):
    return rf"$\epsilon={eps}$"


def plot_epsilon_runtime(ax, subset, ks, eps_values, title=None):
    # Vanilla Gonzalez baseline.
    g_rows = {int(r["k"]): r for r in subset if r.get("algorithm") == "gonzalez"}
    xs, ys = [], []
    for i, k in enumerate(ks):
        r = g_rows.get(k)
        if r:
            y = finite_float(r.get("median_runtime_s", ""))
            if y is not None and r.get("status") in {"OK", "PARTIAL"}:
                xs.append(i); ys.append(y)
    if xs:
        ax.plot(xs, ys, marker="o", label="Gonzalez")

    for eps, marker in zip(eps_values, ("s", "^", "D", "v")):
        erows = {
            int(r["k"]): r for r in subset
            if r.get("algorithm") == "approximategonzalez"
            and r.get("epsilon") == eps
        }
        xs, ys = [], []
        for i, k in enumerate(ks):
            r = erows.get(k)
            if r:
                y = finite_float(r.get("median_runtime_s", ""))
                if y is not None and r.get("status") in {"OK", "PARTIAL"}:
                    xs.append(i); ys.append(y)
        if xs:
            ax.plot(xs, ys, marker=marker, label=epsilon_label(eps))

    ax.set_xticks(range(len(ks)), [str(k) for k in ks])
    ax.set_xlabel("Number of centers $k$")
    ax.set_ylabel("Running time [s]")
    ax.set_yscale("log")
    if title:
        ax.set_title(title)
    ax.grid(True, which="both", alpha=0.25)


def plot_epsilon_quality(ax, subset, ks, eps_values, title=None):
    for eps, marker in zip(eps_values, ("s", "^", "D", "v")):
        erows = {
            int(r["k"]): r for r in subset
            if r.get("algorithm") == "approximategonzalez"
            and r.get("epsilon") == eps
        }
        xs, ys = [], []
        for i, k in enumerate(ks):
            r = erows.get(k)
            if not r or r.get("quality_status") != "OK":
                continue
            rel = finite_float(r.get("relative_radius", ""))
            if rel is not None:
                xs.append(i); ys.append(100.0 * rel)
        if xs:
            ax.plot(xs, ys, marker=marker, label=epsilon_label(eps))
    ax.axhline(100.0, linestyle="--", linewidth=1)
    ax.set_xticks(range(len(ks)), [str(k) for k in ks])
    ax.set_xlabel("Number of centers $k$")
    ax.set_ylabel("Radius relative to Gonzalez")
    ax.yaxis.set_major_formatter(lambda x, pos: f"{x:g}%")
    if title:
        ax.set_title(title)
    ax.grid(True, alpha=0.25)


def plot_p2(rows, outdir):
    ks = [10, 50, 200, 3000]
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.2), squeeze=False)
    axes = list(axes.flat)
    plot_epsilon_runtime(axes[0], rows, ks, EPS_VALUES_P2, "Running time")
    plot_epsilon_quality(axes[1], rows, ks, EPS_VALUES_P2, "Solution quality")
    shared_legend(fig, axes, ncol=5)
    return save(fig, outdir, "figure_A_2_epsilon_synthetic")


P3_PANELS = [
    ("livejournal.adj", "LiveJournal"),
    ("youtube.adj", "YouTube"),
    ("orkut.adj", "Orkut"),
    ("USA-road-d.CTR.adj", "USA-central"),
]


def plot_p3(rows, outdir):
    ks = [10, 50, 300, 2000]
    fig, grid = plt.subplots(4, 2, figsize=(7.2, 9.0), squeeze=False)
    axes = list(grid.flat)
    for i, (token, title) in enumerate(P3_PANELS):
        subset = rows_for(rows, token=token)
        plot_epsilon_runtime(grid[i][0], subset, ks, EPS_VALUES_P3, f"{title}: time")
        plot_epsilon_quality(grid[i][1], subset, ks, EPS_VALUES_P3, f"{title}: quality")
    shared_legend(fig, axes, ncol=3)
    return save(fig, outdir, "figure_A_3_epsilon_real")


# ---------------------------------------------------------------------------
# P4 / Figure A.4
# ---------------------------------------------------------------------------

P4_PANELS = [
    ("er_n10000000_d16_seed0.adj", 20,   r"$k=20,\ \rho=16$, unw."),
    ("er_n10000000_d16_seed0.adj", 100,  r"$k=100,\ \rho=16$, unw."),
    ("er_n10000000_d16_seed0.adj", 500,  r"$k=500,\ \rho=16$, unw."),
    ("er_n10000000_d16_seed0.adj", 3000, r"$k=3000,\ \rho=16$, unw."),
    ("er_n10000000_d4_seed0_w.adj", 20,  r"$k=20,\ \rho=4$, wgh."),
    ("er_n10000000_d4_seed0_w.adj", 100, r"$k=100,\ \rho=4$, wgh."),
    ("er_n10000000_d16_seed0_w.adj",20,  r"$k=20,\ \rho=16$, wgh."),
    ("er_n10000000_d16_seed0_w.adj",100, r"$k=100,\ \rho=16$, wgh."),
]
RPP_TOKENS = ["2", "4", "8", "16", "log2n", "2log2n"]
RPP_LABELS = ["2", "4", "8", "16", r"$\log_2 n$", r"$2\log_2 n$"]


def plot_p4(rows, outdir):
    fig, grid = plt.subplots(4, 2, figsize=(7.2, 8.5), squeeze=False)
    axes = list(grid.flat)

    for ax, (token, k, title) in zip(axes, P4_PANELS):
        subset = rows_for(rows, token=token, k=k, algo="thorupsimple")
        by_rpp = {r.get("rpp_token"): r for r in subset if r.get("rpp_token")}
        xs, ys = [], []
        timeout_x, timeout_y = [], []
        fallback_x, fallback_y = [], []
        for i, token_name in enumerate(RPP_TOKENS):
            r = by_rpp.get(token_name)
            if not r:
                continue
            status = r.get("status", "")
            y = finite_float(r.get("median_runtime_s", ""))
            if status in {"OK", "PARTIAL"} and y is not None:
                xs.append(i); ys.append(y)
                fb = finite_float(r.get("median_fallback_calls", ""))
                if fb is not None and fb > 0:
                    fallback_x.append(i); fallback_y.append(y)
            elif status == "TIMEOUT":
                timeout_x.append(i); timeout_y.append(TIMEOUT_SECONDS)

        if xs:
            ax.plot(xs, ys, marker="o", label="Simplified Thorup")
        if fallback_x:
            # Ring around an existing point; no extra filled marker.
            ax.scatter(
                fallback_x, fallback_y, facecolors="none",
                edgecolors="red", s=90, linewidths=1.5,
                label="Fallback invoked",
            )
        if timeout_x:
            ax.scatter(timeout_x, timeout_y, marker="x", s=55, label="Timeout")

        ax.set_xticks(range(len(RPP_TOKENS)), RPP_LABELS)
        ax.set_xlabel("Rounds per phase")
        ax.set_ylabel("Running time [s]")
        ax.set_title(title, fontsize=9)
        ax.grid(True, alpha=0.25)

    shared_legend(fig, axes, ncol=3)
    return save(fig, outdir, "figure_A_4_thorup_rpp")


def main():
    a = parse_args()
    rows = read_rows(a.input, a.experiment_id)

    if a.experiment_id == "p1_delta":
        outputs = plot_p1(rows, a.output_dir)
    elif a.experiment_id == "p2_approx_epsilon_synthetic":
        outputs = plot_p2(rows, a.output_dir)
    elif a.experiment_id == "p3_approx_epsilon_real":
        outputs = plot_p3(rows, a.output_dir)
    else:
        outputs = plot_p4(rows, a.output_dir)

    print(f"Generated {a.experiment_id} plotting output from supplied result data:")
    for p in outputs:
        print(f"  {p}")


if __name__ == "__main__":
    main()
