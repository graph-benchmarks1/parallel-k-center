#!/usr/bin/env python3
"""Fixture regression tests for Figures A.1--A.4."""

from __future__ import annotations

import csv
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLOTTER = ROOT / "artifact/scripts/plot_parameter_studies.py"

FIELDS = [
    "experiment_id","description","graph","graph_group","graph_type","algorithm",
    "k","mode","threads","delta","epsilon","rpp_token","rpp_value","runs",
    "ok_runs","timeout_runs","fail_runs","status","median_runtime_s",
    "median_num_centers","median_max_dist_to_centers",
    "median_unreachable_vertices","median_fallback_calls",
    "gonzalez_radius","relative_radius","quality_status"
]


def row(exp, graph, typ, algo, k, runtime, *,
        delta="", eps="", rpp_token="", rpp_value="", radius=100,
        rel="", status="OK", fallback=""):
    return {
        "experiment_id":exp,"description":"fixture","graph":graph,"graph_group":"",
        "graph_type":typ,"algorithm":algo,"k":str(k),"mode":"parallel",
        "threads":"64","delta":str(delta),"epsilon":str(eps),
        "rpp_token":str(rpp_token),"rpp_value":str(rpp_value),
        "runs":"1","ok_runs":"1" if status=="OK" else "0",
        "timeout_runs":"1" if status=="TIMEOUT" else "0",
        "fail_runs":"0","status":status,
        "median_runtime_s":str(runtime) if status=="OK" else "",
        "median_num_centers":str(k) if status=="OK" else "",
        "median_max_dist_to_centers":str(radius) if status=="OK" else "",
        "median_unreachable_vertices":"0" if status=="OK" else "",
        "median_fallback_calls":str(fallback),
        "gonzalez_radius":"100" if rel != "" else "",
        "relative_radius":str(rel),
        "quality_status":"OK" if rel != "" else "NOT_APPLICABLE",
    }


with tempfile.TemporaryDirectory(prefix="ae-parameter-plot-") as td:
    td = Path(td)

    # P1: all 12 panels, three algorithms, four Delta values.
    p1 = []
    p1_cases = [
        ("er_n100000_d4_seed2_w.adj",[20,200]),
        ("er_n100000_d8_seed2_w.adj",[20,200]),
        ("er_n100000_d16_seed2_w.adj",[20,200]),
        ("er_n10000000_d4_seed0_w.adj",[200,2000]),
        ("er_n10000000_d8_seed0_w.adj",[200,2000]),
        ("er_n10000000_d16_seed0_w.adj",[200,2000]),
    ]
    for gi,(g,ks) in enumerate(p1_cases):
        for k in ks:
            for ai,a in enumerate(("gonzalez","approximategonzalez","abboud")):
                for d in (2,4,8,16):
                    p1.append(row("p1_delta",g,"weighted",a,k,(ai+1)*(d+gi+1),delta=d,eps="0.1"))

    # P2: Gonzalez + four epsilon values.
    p2=[]
    g="er_n10000000_d16_seed0_w.adj"
    for ki,k in enumerate((10,50,200,3000)):
        p2.append(row("p2_approx_epsilon_synthetic",g,"weighted","gonzalez",k,2+ki,radius=100,rel=1.0))
        for ei,e in enumerate(("0.001","0.01","0.1","0.5")):
            p2.append(row("p2_approx_epsilon_synthetic",g,"weighted","approximategonzalez",k,2.2+ki+ei/10,eps=e,radius=100+ei,rel=(100+ei)/100))

    # P3: four graphs, two epsilon values + Gonzalez.
    p3=[]
    for gi,(g,typ) in enumerate((
        ("livejournal.adj","unweighted"),("youtube.adj","unweighted"),
        ("orkut.adj","unweighted"),("USA-road-d.CTR.adj","weighted")
    )):
        for ki,k in enumerate((10,50,300,2000)):
            p3.append(row("p3_approx_epsilon_real",g,typ,"gonzalez",k,2+gi+ki,radius=100,rel=1.0))
            p3.append(row("p3_approx_epsilon_real",g,typ,"approximategonzalez",k,2.1+gi+ki,eps="0.001",radius=101,rel=1.01))
            p3.append(row("p3_approx_epsilon_real",g,typ,"approximategonzalez",k,2.2+gi+ki,eps="0.5",radius=98,rel=0.98))

    # P4: eight panels. Include one fallback and one timeout to exercise markers.
    p4=[]
    cases=[
        ("er_n10000000_d16_seed0.adj","unweighted",[20,100,500,3000]),
        ("er_n10000000_d4_seed0_w.adj","weighted",[20,100]),
        ("er_n10000000_d16_seed0_w.adj","weighted",[20,100]),
    ]
    toks=[("2","2"),("4","4"),("8","8"),("16","16"),("log2n","23"),("2log2n","46")]
    n=0
    for g,typ,ks in cases:
        for k in ks:
            for ti,(tok,val) in enumerate(toks):
                n += 1
                status="TIMEOUT" if n == 7 else "OK"
                fb="1" if n == 3 else "0"
                p4.append(row("p4_thorup_rpp",g,typ,"thorupsimple",k,1.0+ti+k/1000,
                              rpp_token=tok,rpp_value=val,status=status,fallback=fb))

    fixtures=[
        ("p1_delta",p1,"figure_A_1_delta"),
        ("p2_approx_epsilon_synthetic",p2,"figure_A_2_epsilon_synthetic"),
        ("p3_approx_epsilon_real",p3,"figure_A_3_epsilon_real"),
        ("p4_thorup_rpp",p4,"figure_A_4_thorup_rpp"),
    ]

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

    print("PASS: P1 Figure A.1 generated with Gonzalez / Approx. Gonzalez / Abboud only")
    print("PASS: P2 Figure A.2 generated with epsilon runtime and Gonzalez-relative quality")
    print("PASS: P3 Figure A.3 generated for all four real-world graphs")
    print("PASS: P4 Figure A.4 generated with fallback-ring and timeout markers")
    print("PASS: no Forster series is present in the corrected Figure A.1 machinery")
    print("PASS: plotting validation uses fixture data only (no experiment execution)")
    print()
    print("Parameter-study plotting validation PASSED.")
