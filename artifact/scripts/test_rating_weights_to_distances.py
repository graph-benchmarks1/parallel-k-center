#!/usr/bin/env python3
"""Regression tests for scripts/rating_weights_to_distances.py."""

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "rating_weights_to_distances.py"


def run(inp, out, *args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(inp), str(out), *args],
        text=True,
        capture_output=True,
    )


def expect_file(path, expected):
    actual = path.read_text()
    if actual != expected:
        raise AssertionError(
            f"{path}: expected {expected!r}, got {actual!r}"
        )


with tempfile.TemporaryDirectory() as td:
    d = Path(td)

    # libimseti: rating 1..10 -> distance 10..1
    inp = d / "lib.tsv"
    out = d / "lib.out"
    inp.write_text("1\t2\t1\n2\t3\t5\n3\t4\t10\n")

    r = run(
        inp,
        out,
        "--scale", "1",
        "--max-scaled-rating", "10",
        "--delimiter", "tab",
    )
    assert r.returncode == 0, r.stderr
    expect_file(
        out,
        "1\t2\t10\n"
        "2\t3\t6\n"
        "3\t4\t1\n",
    )
    assert "average weight:     5.666667" in r.stdout

    # MovieLens: 0.5-star increments -> integer distances 10..1.
    inp = d / "ml.csv"
    out = d / "ml.out"
    inp.write_text(
        "userId,movieId,rating,timestamp\n"
        "1,10,0.5,0\n"
        "2,20,3.5,0\n"
        "3,30,5.0,0\n"
    )

    r = run(
        inp,
        out,
        "--scale", "2",
        "--max-scaled-rating", "10",
        "--delimiter", "comma",
        "--header",
    )
    assert r.returncode == 0, r.stderr
    expect_file(
        out,
        "1\t10\t10\n"
        "2\t20\t4\n"
        "3\t30\t1\n",
    )
    assert "average weight:     5.000000" in r.stdout

    # Yahoo: rating 0..100 -> distance 101..1.
    inp = d / "yahoo.txt"
    out = d / "yahoo.out"
    inp.write_text("1 2 0\n2 3 50\n3 4 100\n")

    r = run(
        inp,
        out,
        "--scale", "1",
        "--max-scaled-rating", "100",
    )
    assert r.returncode == 0, r.stderr
    expect_file(
        out,
        "1\t2\t101\n"
        "2\t3\t51\n"
        "3\t4\t1\n",
    )
    assert "average weight:     51.000000" in r.stdout

    # A MovieLens rating that is not a half-star increment must fail.
    inp = d / "bad_increment.csv"
    out = d / "bad_increment.out"
    inp.write_text("1,2,3.7\n")

    r = run(
        inp,
        out,
        "--scale", "2",
        "--max-scaled-rating", "10",
        "--delimiter", "comma",
    )
    assert r.returncode != 0
    assert not out.exists()

    # A rating outside the configured scale must also fail.
    inp = d / "bad_range.tsv"
    out = d / "bad_range.out"
    inp.write_text("1\t2\t11\n")

    r = run(
        inp,
        out,
        "--scale", "1",
        "--max-scaled-rating", "10",
        "--delimiter", "tab",
    )
    assert r.returncode != 0
    assert not out.exists()

print("PASS: rating-to-distance transformer regression tests passed.")

