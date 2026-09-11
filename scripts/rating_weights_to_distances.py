#!/usr/bin/env python3
"""
Transform recommendation ratings into positive integer shortest-path weights.

Transformation:
    weight = (max_scaled_rating + 1) - scale * rating

The script is streaming and does not load the full graph into memory.

Known paper dataset configurations:
  libimseti:
      scale = 1
      max_scaled_rating = 10
      weight = 11 - rating

  MovieLens ml-latest (2023-07-20):
      scale = 2
      max_scaled_rating = 10
      weight = 11 - 2 * rating

  Yahoo! Song:
      scale = 1
      max_scaled_rating = 100
      weight = 101 - rating
"""

import argparse
import csv
import math
import os
import tempfile
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert recommendation ratings to positive integer distance weights."
    )
    parser.add_argument("input", type=Path, help="Input edge/rating file.")
    parser.add_argument("output", type=Path, help="Output weighted edge list.")

    parser.add_argument(
        "--scale",
        type=int,
        required=True,
        help="Positive integer multiplier applied to ratings before reversing the scale.",
    )
    parser.add_argument(
        "--max-scaled-rating",
        type=int,
        required=True,
        help="Maximum possible rating after scaling.",
    )

    parser.add_argument(
        "--delimiter",
        choices=("whitespace", "tab", "comma"),
        default="whitespace",
        help="Input delimiter (default: whitespace).",
    )
    parser.add_argument(
        "--header",
        action="store_true",
        help="Skip the first non-empty, non-comment input row.",
    )

    parser.add_argument(
        "--src-column",
        type=int,
        default=1,
        help="1-based source column (default: 1).",
    )
    parser.add_argument(
        "--dst-column",
        type=int,
        default=2,
        help="1-based destination column (default: 2).",
    )
    parser.add_argument(
        "--rating-column",
        type=int,
        default=3,
        help="1-based rating column (default: 3).",
    )
    parser.add_argument(
        "--comment-prefix",
        default="#",
        help="Ignore lines whose stripped form starts with this prefix (default: #).",
    )

    return parser.parse_args()


def split_fields(line, delimiter):
    if delimiter == "whitespace":
        return line.split()
    if delimiter == "tab":
        return next(csv.reader([line], delimiter="\t"))
    return next(csv.reader([line], delimiter=","))


def main():
    args = parse_args()

    if args.scale <= 0:
        raise SystemExit("ERROR: --scale must be positive.")
    if args.max_scaled_rating <= 0:
        raise SystemExit("ERROR: --max-scaled-rating must be positive.")

    src_col = args.src_column - 1
    dst_col = args.dst_column - 1
    rating_col = args.rating_column - 1

    if min(src_col, dst_col, rating_col) < 0:
        raise SystemExit("ERROR: column numbers are 1-based and must be positive.")

    required_columns = max(src_col, dst_col, rating_col) + 1

    if not args.input.is_file():
        raise SystemExit(f"ERROR: input file not found: {args.input}")

    if args.input.resolve() == args.output.resolve():
        raise SystemExit("ERROR: input and output must be different files.")

    args.output.parent.mkdir(parents=True, exist_ok=True)

    # Atomic output: malformed input never leaves a partial result under the
    # requested output filename.
    fd, tmp_name = tempfile.mkstemp(
        prefix=args.output.name + ".tmp.",
        dir=str(args.output.parent),
    )
    os.close(fd)
    tmp_path = Path(tmp_name)

    rows = 0
    min_rating = None
    max_rating = None
    min_weight = None
    max_weight = None
    sum_weight = 0
    header_pending = args.header

    try:
        with args.input.open("r", encoding="utf-8", newline="") as fin, \
             tmp_path.open("w", encoding="utf-8", newline="") as fout:

            for line_number, raw_line in enumerate(fin, start=1):
                stripped = raw_line.strip()

                if not stripped:
                    continue

                if args.comment_prefix and stripped.startswith(args.comment_prefix):
                    continue

                if header_pending:
                    header_pending = False
                    continue

                try:
                    fields = split_fields(stripped, args.delimiter)
                except Exception as exc:
                    raise ValueError(
                        f"line {line_number}: could not parse row: {exc}"
                    ) from exc

                if len(fields) < required_columns:
                    raise ValueError(
                        f"line {line_number}: expected at least "
                        f"{required_columns} columns, found {len(fields)}"
                    )

                src = fields[src_col].strip()
                dst = fields[dst_col].strip()
                rating_text = fields[rating_col].strip()

                try:
                    rating = float(rating_text)
                except ValueError as exc:
                    raise ValueError(
                        f"line {line_number}: invalid rating {rating_text!r}"
                    ) from exc

                if not math.isfinite(rating):
                    raise ValueError(
                        f"line {line_number}: rating must be finite"
                    )

                scaled_float = args.scale * rating
                scaled_rating = round(scaled_float)

                if not math.isclose(
                    scaled_float,
                    scaled_rating,
                    rel_tol=0.0,
                    abs_tol=1e-9,
                ):
                    raise ValueError(
                        f"line {line_number}: rating {rating_text} with "
                        f"scale {args.scale} does not map to an integer "
                        f"scaled rating"
                    )

                if scaled_rating < 0 or scaled_rating > args.max_scaled_rating:
                    raise ValueError(
                        f"line {line_number}: scaled rating {scaled_rating} "
                        f"is outside [0, {args.max_scaled_rating}]"
                    )

                weight = (
                    args.max_scaled_rating
                    + 1
                    - scaled_rating
                )

                if weight <= 0:
                    raise ValueError(
                        f"line {line_number}: transformation produced "
                        f"non-positive weight {weight}"
                    )

                fout.write(f"{src}\t{dst}\t{weight}\n")

                rows += 1
                sum_weight += weight

                min_rating = (
                    rating
                    if min_rating is None
                    else min(min_rating, rating)
                )
                max_rating = (
                    rating
                    if max_rating is None
                    else max(max_rating, rating)
                )
                min_weight = (
                    weight
                    if min_weight is None
                    else min(min_weight, weight)
                )
                max_weight = (
                    weight
                    if max_weight is None
                    else max(max_weight, weight)
                )

        if header_pending:
            raise ValueError("input contained no data/header row")

        os.replace(tmp_path, args.output)

    except Exception as exc:
        tmp_path.unlink(missing_ok=True)
        raise SystemExit(f"ERROR: {exc}")

    print("Rating-to-distance transformation complete.")
    print(f"  input:              {args.input}")
    print(f"  output:             {args.output}")
    print(f"  rows transformed:   {rows}")

    if rows:
        print(f"  observed ratings:   [{min_rating:g}, {max_rating:g}]")
        print(f"  output weights:     [{min_weight}, {max_weight}]")
        print(f"  average weight:     {sum_weight / rows:.6f}")

    print(f"  scale:              {args.scale}")
    print(f"  max scaled rating:  {args.max_scaled_rating}")
    print(
        "  formula:            "
        f"weight = {args.max_scaled_rating + 1} "
        f"- {args.scale} * rating"
    )


if __name__ == "__main__":
    main()

