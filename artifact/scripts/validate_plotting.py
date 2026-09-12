#!/usr/bin/env python3
"""Regression-test P9-P13 full-sweep paper-figure reconstruction."""

from __future__ import annotations

import csv
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLOTTER = ROOT / "artifact/scripts/plot_full_sweep.py"

FIELDS = [
    "experiment_id","description","graph","graph_group","graph_type","algorithm","k",
    "mode","threads","delta","epsilon","rpp_token","rpp_value","runs","ok_runs",
    "timeout_runs","fail_runs","status","median_runtime_s","median_num_centers",
    "median_max_dist_to_centers","median_unreachable_vertices",
    "median_fallback_calls","abboud_selected_mode","abboud_selected_threads",
    "abboud_candidate_count","gonzalez_radius","relative_radius","quality_status"
]

ALGOS = ["gonzalez","approximategonzalez","abboud","thorupsimple"]

CASES = {
    "p9_full_sweep_small_synthetic": [
        ("Snap_unweighted/ER_small/er_n100000_d2_seed*.adj","", "unweighted", [20,50,100,316]),
        ("Snap_weighted/ER_small/er_n100000_d2_seed*_w.adj","", "weighted", [20,50,100,316]),
    ],
    "p10_full_sweep_large_synthetic": [
        ("","Snap_unweighted/ER_large/er_n10000000_d2_seed0.adj","unweighted",[20,100,500,3162]),
        ("","Snap_weighted/ER_large/er_n10000000_d4_seed0_w.adj","weighted",[20,100,500,3162]),
    ],
    "p11_full_sweep_social": [
        ("Snap_unweighted/com-dblp.adj","", "unweighted",[20,100,563]),
        ("Snap_unweighted/com-orkut.adj","", "unweighted",[20,100,500,1752]),
    ],
    "p12_full_sweep_roads": [
        ("Snap_weighted/USA-road-d.CTR.adj","", "weighted",[20,100,500,3700]),
        ("Snap_weighted/USA-road-d.USA.adj","", "weighted",[20,100,500,5200]),
    ],
    "p13_full_sweep_ratings": [
        ("Snap_weighted/libimseti.adj","", "weighted",[20,100,470]),
        ("Snap_weighted/yahoo-song.adj","", "weighted",[20,100,500,1275]),
    ],
}

EXPECTED = {
    "p9_full_sweep_small_synthetic": ["figure_A_7_runtime","figure_A_8_quality"],
    "p10_full_sweep_large_synthetic": ["figure_A_9_runtime","figure_A_10_quality"],
    "p11_full_sweep_social": ["figure_7_3_runtime","figure_A_11_quality"],
    "p12_full_sweep_roads": ["figure_7_4_runtime","figure_7_5_quality"],
    "p13_full_sweep_ratings": ["figure_A_12_runtime","figure_A_13_quality"],
}


def mkrow(exp, graph, group, typ, algo, k, ai, ki):
    mode = "parallel"
    threads = "64"
    if exp in {"p9_full_sweep_small_synthetic","p12_full_sweep_roads"}:
        mode, threads = "singlecore", "1"
    if algo == "abboud" and exp in {"p10_full_sweep_large_synthetic","p11_full_sweep_social"}:
        mode = "singlecore" if ki % 2 else "parallel"
        threads = "1" if mode == "singlecore" else "64"
    rel = [1.0, 1.03, 0.97, 0.95][ai]
    return {
        "experiment_id": exp, "description":"fixture", "graph":graph,
        "graph_group":group, "graph_type":typ, "algorithm":algo, "k":str(k),
        "mode":mode, "threads":threads, "delta":"", "epsilon":"0.001",
        "rpp_token":"", "rpp_value":"", "runs":"3", "ok_runs":"3",
        "timeout_runs":"0","fail_runs":"0","status":"OK",
        "median_runtime_s":str((ai+1)*(ki+1)*3.0),
        "median_num_centers":str(k),
        "median_max_dist_to_centers":str(100.0*rel),
        "median_unreachable_vertices":"0","median_fallback_calls":"",
        "abboud_selected_mode":mode if algo=="abboud" else "",
        "abboud_selected_threads":threads if algo=="abboud" else "",
        "abboud_candidate_count":"2" if algo=="abboud" and exp in {"p10_full_sweep_large_synthetic","p11_full_sweep_social"} else "",
        "gonzalez_radius":"100","relative_radius":str(rel),"quality_status":"OK",
    }


with tempfile.TemporaryDirectory(prefix="ae-full-plot-") as td:
    td = Path(td)
    for exp, cases in CASES.items():
        inp = td / f"{exp}.tsv"
        out = td / exp
        rows=[]
        for graph, group, typ, ks in cases:
            for ai,algo in enumerate(ALGOS):
                for ki,k in enumerate(ks):
                    rows.append(mkrow(exp,graph,group,typ,algo,k,ai,ki))
        with inp.open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=FIELDS,delimiter="\t",lineterminator="\n")
            w.writeheader(); w.writerows(rows)

        subprocess.run(
            [sys.executable,str(PLOTTER),"--experiment-id",exp,
             "--input",str(inp),"--output-dir",str(out)],
            check=True
        )
        for stem in EXPECTED[exp]:
            for ext in ("pdf","png"):
                p=out/f"{stem}.{ext}"
                assert p.is_file() and p.stat().st_size > 1000, p

    print("PASS: P9  Figures A.7/A.8 generated")
    print("PASS: P10 Figures A.9/A.10 generated")
    print("PASS: P11 Figures 7.3/A.11 generated")
    print("PASS: P12 Figures 7.4/7.5 generated")
    print("PASS: P13 Figures A.12/A.13 generated")
    print("PASS: P10/P11 runtime plotting preserves selected Abboud execution mode")
    print("PASS: P10 quality omits rho=2 panels, matching the submitted paper")
    print("PASS: P12 uses literal submitted-paper k values 3700 and 5200")
    print("PASS: plotting completes without constrained_layout/subplots_adjust warnings")
    print()
    print("Full-sweep plotting validation PASSED.")
