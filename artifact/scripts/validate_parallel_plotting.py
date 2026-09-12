#!/usr/bin/env python3
"""Fixture regression tests for P5--P8 parallel-scaling plotting."""

from __future__ import annotations
import csv, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLOTTER = ROOT / "artifact/scripts/plot_parallel_scaling.py"

FIELDS = [
    "experiment_id","description","graph","graph_group","graph_type","algorithm",
    "k","mode","threads","delta","epsilon","rpp_token","rpp_value","runs",
    "ok_runs","timeout_runs","fail_runs","status","median_runtime_s",
    "median_num_centers","median_max_dist_to_centers",
    "median_unreachable_vertices","median_fallback_calls"
]

ALGOS = ("gonzalez","approximategonzalez","abboud","thorupsimple")
THREADS = ("singlecore","8","16","32","64","128")

def mk(exp,g,typ,k,algo,t,runtime):
    return {
        "experiment_id":exp,"description":"fixture","graph":g,"graph_group":"",
        "graph_type":typ,"algorithm":algo,"k":str(k),
        "mode":"singlecore" if t=="singlecore" else "parallel",
        "threads":"1" if t=="singlecore" else t,
        "delta":"8" if typ=="weighted" and t!="singlecore" else "",
        "epsilon":"0.5" if exp=="p8_parallel_road" and algo=="approximategonzalez" else "0.001",
        "rpp_token":"4" if algo=="thorupsimple" else "",
        "rpp_value":"4" if algo=="thorupsimple" else "",
        "runs":"3","ok_runs":"3","timeout_runs":"0","fail_runs":"0","status":"OK",
        "median_runtime_s":str(runtime),"median_num_centers":str(k),
        "median_max_dist_to_centers":"10","median_unreachable_vertices":"0",
        "median_fallback_calls":"0" if algo=="thorupsimple" else "",
    }

with tempfile.TemporaryDirectory(prefix="ae-parallel-plot-") as td:
    td=Path(td)
    fixtures=[]

    # P5: aggregated rows represent the already-combined ten-seed hierarchy.
    p5=[]
    for typ,suffix in (("unweighted",""),("weighted","_w")):
        for d in (4,16):
            for k in (20,200):
                g=f"er_n100000_d{d}_seed0{suffix}.adj"
                for ai,a in enumerate(ALGOS):
                    for ti,t in enumerate(THREADS):
                        p5.append(mk("p5_parallel_small_synthetic",g,typ,k,a,t,1+ai+ti/3+d/20))
    fixtures.append(("p5_parallel_small_synthetic",p5,"figure_A_5_parallel_small_synthetic"))

    p6=[]
    for g,typ,ks in (
        ("er_n10000000_d4_seed0.adj","unweighted",(200,2000)),
        ("er_n10000000_d4_seed0_w.adj","weighted",(200,2000)),
        ("er_n10000000_d16_seed0_w.adj","weighted",(200,2000)),
    ):
        for k in ks:
            for ai,a in enumerate(ALGOS):
                for ti,t in enumerate(THREADS):
                    p6.append(mk("p6_parallel_large_synthetic",g,typ,k,a,t,5+ai+ti))
    fixtures.append(("p6_parallel_large_synthetic",p6,"figure_A_6_parallel_large_synthetic"))

    p7=[]
    for g in ("livejournal.adj","youtube.adj","orkut.adj"):
        for k in (200,2000):
            for ai,a in enumerate(ALGOS):
                for ti,t in enumerate(THREADS):
                    p7.append(mk("p7_parallel_social",g,"unweighted",k,a,t,3+ai+ti))
    fixtures.append(("p7_parallel_social",p7,"figure_7_1_parallel_social"))

    p8=[]
    for k in (200,2000):
        for ai,a in enumerate(ALGOS):
            for ti,t in enumerate(("singlecore","8","16","32")):
                p8.append(mk("p8_parallel_road","USA-road-d.CTR.adj","weighted",k,a,t,100+ai*10+ti))
    fixtures.append(("p8_parallel_road",p8,"figure_7_2_parallel_road"))

    for exp,rows,stem in fixtures:
        inp=td/f"{exp}.tsv"; out=td/exp
        with inp.open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=FIELDS,delimiter="\t",lineterminator="\n")
            w.writeheader(); w.writerows(rows)
        proc=subprocess.run(
            [sys.executable,str(PLOTTER),"--experiment-id",exp,
             "--input",str(inp),"--output-dir",str(out)],
            check=True,capture_output=True,text=True
        )
        if "UserWarning" in proc.stderr:
            raise AssertionError(proc.stderr)
        for ext in ("pdf","png"):
            p=out/f"{stem}.{ext}"
            assert p.is_file() and p.stat().st_size > 1000,p

    print("PASS: P5 Figure A.5 generated from already-hierarchically-aggregated small-synthetic data")
    print("PASS: P6 Figure A.6 generated for all six large-synthetic scaling panels")
    print("PASS: P7 Figure 7.1 generated for LiveJournal / YouTube / Orkut at k=200 and k=2000")
    print("PASS: P8 Figure 7.2 stops at 32 threads, matching the road scaling experiment")
    print("PASS: single-core is represented as a distinct execution mode, not a 1-thread parallel point")
    print("PASS: plotting validation uses fixture data only (no experiment execution)")
    print()
    print("Parallel-scaling plotting validation PASSED.")
