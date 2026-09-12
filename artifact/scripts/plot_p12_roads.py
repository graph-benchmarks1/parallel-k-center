#!/usr/bin/env python3
"""Reconstruct submitted-paper road-network Figures 7.4 and 7.5."""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

EXPERIMENT_ID = "p12_full_sweep_roads"

ALGORITHMS = [
    ("gonzalez", "Gonzalez", "o"),
    ("approximategonzalez", "Approximate Gonzalez", "s"),
    ("abboud", "Abboud MIS", "^"),
    ("thorupsimple", "Simplified Thorup", "D"),
]

GRAPHS = [
    ("USA-road-d.CTR.adj", "USA-central", [20, 100, 500, 3700]),
    ("USA-road-d.USA.adj", "USA-full", [20, 100, 500, 5200]),
]


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output-dir", required=True, type=Path)
    return p.parse_args()


def read_rows(path):
    if not path.is_file():
        raise SystemExit(f"ERROR: paper_results.tsv not found: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    rows = [r for r in rows if r.get("experiment_id") == EXPERIMENT_ID]
    if not rows:
        raise SystemExit(f"ERROR: no {EXPERIMENT_ID} rows in {path}")
    return rows


def basename(row):
    g = row.get("graph_group") or row.get("graph") or ""
    return Path(g).name


def numeric(raw):
    if raw in ("", None):
        return None
    try:
        x = float(raw)
    except ValueError:
        return None
    return x if math.isfinite(x) else None


def index_rows(rows):
    idx = {}
    for r in rows:
        key = (basename(r), r.get("algorithm"), int(r["k"]))
        if key in idx:
            raise SystemExit(f"ERROR: duplicate paper point: {key}")
        idx[key] = r
    return idx


def plot_runtime(idx, outdir):
    fig, axes = plt.subplots(1, 2, figsize=(7.1, 3.0), constrained_layout=True)
    for ax, (graph, title, ks) in zip(axes, GRAPHS):
        xpos = list(range(len(ks)))
        for algo, label, marker in ALGORITHMS:
            ys = []
            xs = []
            for x, k in zip(xpos, ks):
                r = idx.get((graph, algo, k))
                y = numeric(r.get("median_runtime_s", "")) if r else None
                if y is not None and r.get("status") in {"OK", "PARTIAL"}:
                    xs.append(x)
                    ys.append(y)
            if xs:
                ax.plot(xs, ys, marker=marker, label=label)
        ax.set_yscale("log")
        ax.set_xticks(xpos, [str(k) for k in ks])
        ax.set_xlabel("$k$")
        ax.set_ylabel("Running time [s]")
        ax.set_title(title)
        ax.grid(True, which="both", alpha=0.25)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=4, fontsize=8)
    fig.subplots_adjust(top=0.80)
    pdf = outdir / "figure_7_4_runtime.pdf"
    png = outdir / "figure_7_4_runtime.png"
    fig.savefig(pdf, bbox_inches="tight")
    fig.savefig(png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return pdf, png


def plot_quality(idx, outdir):
    fig, axes = plt.subplots(1, 2, figsize=(7.1, 3.0), constrained_layout=True)
    for ax, (graph, title, ks) in zip(axes, GRAPHS):
        xpos = list(range(len(ks)))
        for algo, label, marker in ALGORITHMS:
            xs = []
            ys = []
            for x, k in zip(xpos, ks):
                r = idx.get((graph, algo, k))
                if not r or r.get("quality_status") != "OK":
                    continue
                rel = numeric(r.get("relative_radius", ""))
                if rel is not None:
                    xs.append(x)
                    ys.append(100.0 * rel)
            if xs:
                ax.plot(xs, ys, marker=marker, label=label)
        ax.axhline(100.0, linestyle="--", linewidth=1)
        ax.set_xticks(xpos, [str(k) for k in ks])
        ax.set_xlabel("$k$")
        ax.set_ylabel("Relative solution quality [%]")
        ax.set_title(title)
        ax.grid(True, alpha=0.25)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=4, fontsize=8)
    fig.subplots_adjust(top=0.80)
    pdf = outdir / "figure_7_5_quality.pdf"
    png = outdir / "figure_7_5_quality.png"
    fig.savefig(pdf, bbox_inches="tight")
    fig.savefig(png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return pdf, png


def main():
    a = args()
    rows = read_rows(a.input)
    idx = index_rows(rows)
    a.output_dir.mkdir(parents=True, exist_ok=True)

    runtime = plot_runtime(idx, a.output_dir)
    quality = plot_quality(idx, a.output_dir)

    print("Reconstructed road-network paper figures:")
    for p in runtime + quality:
        print(f"  {p}")


if __name__ == "__main__":
    main()
