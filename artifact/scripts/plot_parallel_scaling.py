#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, List, Optional

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ALGO_ORDER = ("gonzalez", "approximategonzalez", "abboud", "thorupsimple")
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

THREAD_ORDER = ["singlecore", "8", "16", "32", "64", "128"]
THREAD_LABELS = ["single-core", "8", "16", "32", "64", "128"]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument(
        "--experiment-id",
        required=True,
        choices=[
            "p5_parallel_small_synthetic",
            "p6_parallel_large_synthetic",
            "p7_parallel_social",
            "p8_parallel_road",
        ],
    )
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output-dir", required=True, type=Path)
    return p.parse_args()


def read_rows(path: Path, experiment_id: str):
    if not path.is_file():
        raise SystemExit(f"ERROR: input TSV not found: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t")
                if r.get("experiment_id") == experiment_id]
    if not rows:
        raise SystemExit(f"ERROR: no {experiment_id} rows in {path}")
    return rows


def finite_float(raw):
    if raw in ("", None):
        return None
    try:
        x = float(raw)
    except ValueError:
        return None
    return x if math.isfinite(x) else None


def graph_name(row):
    return row.get("graph_group") or row.get("graph") or ""


def save(fig, outdir: Path, stem: str):
    outdir.mkdir(parents=True, exist_ok=True)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    pdf = outdir / f"{stem}.pdf"
    png = outdir / f"{stem}.png"
    fig.savefig(pdf, bbox_inches="tight")
    fig.savefig(png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return pdf, png


def shared_legend(fig, axes):
    handles, labels, seen = [], [], set()
    for ax in axes:
        hs, ls = ax.get_legend_handles_labels()
        for h, l in zip(hs, ls):
            if l and l not in seen:
                seen.add(l)
                handles.append(h)
                labels.append(l)
    if handles:
        fig.legend(handles, labels, loc="upper center", ncol=4, fontsize=8)


def thread_token(row):
    mode = row.get("mode", "")
    if mode == "singlecore":
        return "singlecore"
    t = row.get("threads", "")
    return t


def panel(ax, subset, thread_tokens, title):
    for algo in ALGO_ORDER:
        amap = {}
        for r in subset:
            if r.get("algorithm") != algo:
                continue
            amap[thread_token(r)] = r
        xs, ys = [], []
        for i, tok in enumerate(thread_tokens):
            r = amap.get(tok)
            if not r:
                continue
            if r.get("status") not in {"OK", "PARTIAL"}:
                continue
            y = finite_float(r.get("median_runtime_s", ""))
            if y is None:
                continue
            xs.append(i)
            ys.append(y)
        if xs:
            ax.plot(xs, ys, marker=ALGO_MARKERS[algo], label=ALGO_LABELS[algo])
    labels = ["single-core" if x == "singlecore" else x for x in thread_tokens]
    ax.set_xticks(range(len(thread_tokens)), labels)
    ax.set_xlabel("Execution / threads")
    ax.set_ylabel("Running time [s]")
    ax.set_yscale("log")
    ax.set_title(title, fontsize=9)
    ax.grid(True, which="both", alpha=0.25)


# P5: small synthetic, rho 4/16, k 20/200, weighted/unweighted.
P5_CASES = [
    ("er_n100000_d4_",  "unweighted", 20,  r"$\rho=4,\ k=20$, unw."),
    ("er_n100000_d16_", "unweighted", 20,  r"$\rho=16,\ k=20$, unw."),
    ("er_n100000_d4_",  "unweighted", 200, r"$\rho=4,\ k=200$, unw."),
    ("er_n100000_d16_", "unweighted", 200, r"$\rho=16,\ k=200$, unw."),
    ("er_n100000_d4_",  "weighted",   20,  r"$\rho=4,\ k=20$, wgh."),
    ("er_n100000_d16_", "weighted",   20,  r"$\rho=16,\ k=20$, wgh."),
    ("er_n100000_d4_",  "weighted",   200, r"$\rho=4,\ k=200$, wgh."),
    ("er_n100000_d16_", "weighted",   200, r"$\rho=16,\ k=200$, wgh."),
]

# P6: large synthetic panels from the submitted study.
P6_CASES = [
    ("er_n10000000_d4_seed0.adj",   "unweighted", 200,  r"$\rho=4,\ k=200$, unw."),
    ("er_n10000000_d4_seed0.adj",   "unweighted", 2000, r"$\rho=4,\ k=2000$, unw."),
    ("er_n10000000_d4_seed0_w.adj", "weighted",   200,  r"$\rho=4,\ k=200$, wgh."),
    ("er_n10000000_d4_seed0_w.adj", "weighted",   2000, r"$\rho=4,\ k=2000$, wgh."),
    ("er_n10000000_d16_seed0_w.adj","weighted",   200,  r"$\rho=16,\ k=200$, wgh."),
    ("er_n10000000_d16_seed0_w.adj","weighted",   2000, r"$\rho=16,\ k=2000$, wgh."),
]

P7_CASES = [
    ("livejournal.adj", 200,  "LiveJournal, $k=200$"),
    ("livejournal.adj", 2000, "LiveJournal, $k=2000$"),
    ("youtube.adj",     200,  "YouTube, $k=200$"),
    ("youtube.adj",     2000, "YouTube, $k=2000$"),
    ("orkut.adj",       200,  "Orkut, $k=200$"),
    ("orkut.adj",       2000, "Orkut, $k=2000$"),
]

P8_CASES = [
    ("USA-road-d.CTR.adj", 200,  "USA-central, $k=200$"),
    ("USA-road-d.CTR.adj", 2000, "USA-central, $k=2000$"),
]


def subset_token(rows, token, typ=None, k=None):
    out = []
    for r in rows:
        if token not in graph_name(r):
            continue
        if typ is not None and r.get("graph_type") != typ:
            continue
        if k is not None and r.get("k") != str(k):
            continue
        out.append(r)
    return out


def plot_p5(rows, outdir):
    fig, grid = plt.subplots(4, 2, figsize=(7.2, 8.8), squeeze=False)
    axes = list(grid.flat)
    for ax, (tok, typ, k, title) in zip(axes, P5_CASES):
        panel(ax, subset_token(rows, tok, typ, k), THREAD_ORDER, title)
    shared_legend(fig, axes)
    return save(fig, outdir, "figure_A_5_parallel_small_synthetic")


def plot_p6(rows, outdir):
    fig, grid = plt.subplots(3, 2, figsize=(7.2, 7.0), squeeze=False)
    axes = list(grid.flat)
    for ax, (tok, typ, k, title) in zip(axes, P6_CASES):
        panel(ax, subset_token(rows, tok, typ, k), THREAD_ORDER, title)
    shared_legend(fig, axes)
    return save(fig, outdir, "figure_A_6_parallel_large_synthetic")


def plot_p7(rows, outdir):
    fig, grid = plt.subplots(3, 2, figsize=(7.2, 7.0), squeeze=False)
    axes = list(grid.flat)
    for ax, (tok, k, title) in zip(axes, P7_CASES):
        panel(ax, subset_token(rows, tok, "unweighted", k), THREAD_ORDER, title)
    shared_legend(fig, axes)
    return save(fig, outdir, "figure_7_1_parallel_social")


def plot_p8(rows, outdir):
    thread_tokens = ["singlecore", "8", "16", "32"]
    fig, grid = plt.subplots(1, 2, figsize=(7.2, 3.2), squeeze=False)
    axes = list(grid.flat)
    for ax, (tok, k, title) in zip(axes, P8_CASES):
        panel(ax, subset_token(rows, tok, "weighted", k), thread_tokens, title)
    shared_legend(fig, axes)
    return save(fig, outdir, "figure_7_2_parallel_road")


def main():
    a = parse_args()
    rows = read_rows(a.input, a.experiment_id)
    if a.experiment_id == "p5_parallel_small_synthetic":
        outputs = plot_p5(rows, a.output_dir)
    elif a.experiment_id == "p6_parallel_large_synthetic":
        outputs = plot_p6(rows, a.output_dir)
    elif a.experiment_id == "p7_parallel_social":
        outputs = plot_p7(rows, a.output_dir)
    else:
        outputs = plot_p8(rows, a.output_dir)

    print(f"Generated {a.experiment_id} plotting output from supplied aggregated result data:")
    for p in outputs:
        print(f"  {p}")


if __name__ == "__main__":
    main()
