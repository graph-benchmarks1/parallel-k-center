#!/usr/bin/env python3
import csv
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DERIVE = ROOT / "artifact/scripts/derive_paper_results.py"

FIELDS = [
    "experiment_id","description","graph","graph_type","algorithm","k","mode",
    "threads","delta","epsilon","rpp_token","rpp_value","runs","ok_runs",
    "timeout_runs","fail_runs","status","median_runtime_s","median_num_centers",
    "median_max_dist_to_centers","median_unreachable_vertices",
    "median_fallback_calls"
]

def row(exp, graph, algo, k, mode, threads, runtime, radius, status="OK", eps=""):
    return {
        "experiment_id":exp, "description":"fixture", "graph":graph,
        "graph_type":"unweighted", "algorithm":algo, "k":str(k), "mode":mode,
        "threads":str(threads), "delta":"", "epsilon":eps, "rpp_token":"",
        "rpp_value":"", "runs":"3", "ok_runs":"3" if status=="OK" else "0",
        "timeout_runs":"3" if status=="TIMEOUT" else "0",
        "fail_runs":"3" if status=="FAIL" else "0", "status":status,
        "median_runtime_s":"" if status!="OK" else str(runtime),
        "median_num_centers":"" if status!="OK" else "20",
        "median_max_dist_to_centers":"" if status!="OK" else str(radius),
        "median_unreachable_vertices":"" if status!="OK" else "0",
        "median_fallback_calls":"",
    }

with tempfile.TemporaryDirectory(prefix="ae-derived-") as td:
    td=Path(td); inp=td/"aggregated.tsv"; out=td/"paper_results.tsv"
    rows=[
        # P10: Gonzalez baseline, plus both Abboud modes. Single-core is faster.
        row("p10_full_sweep_large_synthetic","g.adj","gonzalez",20,"parallel",64,10,100),
        row("p10_full_sweep_large_synthetic","g.adj","abboud",20,"parallel",64,8,90),
        row("p10_full_sweep_large_synthetic","g.adj","abboud",20,"singlecore",1,5,90),
        row("p10_full_sweep_large_synthetic","g.adj","thorupsimple",20,"parallel",64,12,110),
        # Second P10 point: parallel Abboud succeeds while single-core times out.
        row("p10_full_sweep_large_synthetic","g.adj","gonzalez",100,"parallel",64,20,50),
        row("p10_full_sweep_large_synthetic","g.adj","abboud",100,"parallel",64,7,45),
        row("p10_full_sweep_large_synthetic","g.adj","abboud",100,"singlecore",1,0,0,"TIMEOUT"),
        # P3: epsilon is deliberately ignored when matching Gonzalez baseline.
        row("p3_approx_epsilon_real","road.adj","gonzalez",20,"parallel",64,9,200),
        row("p3_approx_epsilon_real","road.adj","approximategonzalez",20,"parallel",64,8,190,eps="0.5"),
    ]
    with inp.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=FIELDS,delimiter="\t",lineterminator="\n")
        w.writeheader(); w.writerows(rows)

    subprocess.run([sys.executable,str(DERIVE),"--input",str(inp),"--output",str(out)],check=True)

    with out.open(newline="",encoding="utf-8") as f:
        got=list(csv.DictReader(f,delimiter="\t"))

    p10k20=[r for r in got if r["experiment_id"].startswith("p10_") and r["k"]=="20"]
    abb=[r for r in p10k20 if r["algorithm"]=="abboud"]
    assert len(abb)==1, abb
    assert abb[0]["mode"]=="singlecore"
    assert abb[0]["abboud_selected_mode"]=="singlecore"
    assert abb[0]["abboud_candidate_count"]=="2"
    assert float(abb[0]["relative_radius"])==0.9

    abb100=[r for r in got if r["experiment_id"].startswith("p10_") and r["algorithm"]=="abboud" and r["k"]=="100"]
    assert len(abb100)==1
    assert abb100[0]["mode"]=="parallel"
    assert float(abb100[0]["relative_radius"])==0.9

    g=[r for r in p10k20 if r["algorithm"]=="gonzalez"][0]
    assert float(g["relative_radius"])==1.0

    th=[r for r in p10k20 if r["algorithm"]=="thorupsimple"][0]
    assert float(th["relative_radius"])==1.1

    p3=[r for r in got if r["experiment_id"].startswith("p3_") and r["algorithm"]=="approximategonzalez"][0]
    assert float(p3["relative_radius"])==0.95
    assert p3["quality_status"]=="OK"

    print("PASS: P10 Abboud selects the faster single-core median")
    print("PASS: P10 Abboud selects parallel when single-core timed out")
    print("PASS: selected Abboud quality is normalized to Gonzalez")
    print("PASS: Gonzalez relative radius is exactly 1.0")
    print("PASS: other algorithms are normalized correctly")
    print("PASS: P3 epsilon sweep shares the correct Gonzalez baseline")
    print()
    print("Paper-derived-results validation PASSED.")
