#!/usr/bin/env python3
"""receipts-aggregate — aggregate ~/.claude/receipts/*.jsonl into a denormalized table.

Schema source: yurukusa schema-v2 sketch at
  https://github.com/anthropics/claude-code/issues/61102#issuecomment-4514215413
which proposes one-row-per-receipt denormalized columns wide enough to host all
five boundary types' fields, sparse where a given boundary doesn't have a column.

Consumed receipt sources:
  - examples/scope-expansion-receipt.sh (PR #282, destructive-bash boundary)
  - examples/dispatch-receipt.sh        (PR #283, agent-dispatch boundary)
  - examples/dispatch-allowlist-preflight.sh (PR #286)
  - examples/articulated-scope-capture.sh    (this PR, UserPromptSubmit companion)
  - any future sibling boundary-type hook that writes ~/.claude/receipts/*.jsonl

Output: CSV to stdout by default; --format json available.

Filter: --boundary <type> restricts output to one boundary class.

The aggregated table is the operator-side measurement substrate for §6.2 of
ianymu/recognition-without-arrest — the empirical Mode 2.6 + Mode 3.3 question
answerable from receipt corpora rather than from LLM-judge labels:

    effective_arrest_rate = gate_installation_rate × gate_recall

where gate_installation_rate is read from the receipt corpus directly, joined
across boundary types on session_id + articulated_scope_hash.

Stdlib-only per PR #280 precedent (no eval, no network, no pandas/polars dep);
Python 3.10+. Output JSON/CSV is downstream-consumable by pandas, polars, jq,
or duckdb without this script reaching beyond stdlib.

Example usage:

    # Aggregate all receipts, CSV to stdout
    receipts-aggregate.py

    # Filter to one boundary class, JSON output
    receipts-aggregate.py --boundary destructive_bash --format json

    # Explicit paths
    receipts-aggregate.py ~/.claude/receipts/*.jsonl
"""

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Iterator

# Denormalized columns per yurukusa schema sketch.
# Wide row, sparse columns: a given boundary type populates only the relevant
# fields. Sparse data is empty string in CSV / null in JSON.
COLUMNS = [
    "ts",
    "boundary_type",
    "session_id",
    "subagent_type",
    "prompt_hash",
    "prompt_length",
    "articulated_scope_hash",
    "articulated_scope_length",
    "paths",
    "scope_match",
    "allowlist_match",
    "mcp_tools_referenced",
    "parent_covered_count",
    "decision",
    "additional_fields",
]

BOUNDARY_CHOICES = (
    "destructive_bash",
    "dispatch_start",
    "dispatch_end",
    "user_prompt_submit",
    "post_tool_use_disk",
    "all",
)


def iter_receipts(paths: list[Path]) -> Iterator[dict]:
    """Yield one parsed receipt dict per JSONL line across all input files.

    Malformed lines produce a warning to stderr and are skipped; valid lines
    in the same file continue to be processed.
    """
    for path in paths:
        try:
            with path.open("r", encoding="utf-8") as f:
                for line_no, raw in enumerate(f, start=1):
                    raw = raw.strip()
                    if not raw:
                        continue
                    try:
                        yield json.loads(raw)
                    except json.JSONDecodeError as e:
                        print(
                            f"warning: {path}:{line_no}: invalid JSON skipped ({e})",
                            file=sys.stderr,
                        )
        except OSError as e:
            print(f"warning: cannot read {path}: {e}", file=sys.stderr)


def normalize(receipt: dict) -> dict:
    """Project a parsed receipt to the denormalized COLUMNS schema.

    Known fields land in their named column. Unknown fields land in
    `additional_fields` as a JSON-encoded sub-object so no source data is
    dropped — this preserves forward compatibility with future receipt
    fields (e.g. schema v3) without requiring a code change here.
    """
    row = {}
    extras = {}
    for k, v in receipt.items():
        if k in COLUMNS and k != "additional_fields":
            # Coerce nested objects/lists to JSON string for CSV-safety
            if isinstance(v, (dict, list)):
                row[k] = json.dumps(v, sort_keys=True)
            else:
                row[k] = v
        else:
            extras[k] = v
    for col in COLUMNS:
        if col not in row and col != "additional_fields":
            row[col] = ""
    row["additional_fields"] = json.dumps(extras, sort_keys=True) if extras else ""
    return row


def emit_csv(rows: Iterator[dict]) -> None:
    writer = csv.DictWriter(sys.stdout, fieldnames=COLUMNS)
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


def emit_json(rows: Iterator[dict]) -> None:
    json.dump(list(rows), sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Aggregate ~/.claude/receipts/*.jsonl into a denormalized table.",
        epilog=(
            "Schema source: yurukusa #61102#issuecomment-4514215413. "
            "Output is downstream-consumable by pandas, polars, jq, or duckdb."
        ),
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="JSONL receipt files (default: ~/.claude/receipts/*.jsonl)",
    )
    parser.add_argument(
        "--format",
        choices=("csv", "json"),
        default="csv",
        help="output format (default: csv)",
    )
    parser.add_argument(
        "--boundary",
        choices=BOUNDARY_CHOICES,
        default="all",
        help="filter to a single boundary type (default: all)",
    )
    args = parser.parse_args(argv)

    if args.paths:
        paths = [Path(p) for p in args.paths]
    else:
        default = Path.home() / ".claude" / "receipts"
        paths = sorted(default.glob("*.jsonl"))
        if not paths:
            print(
                f"warning: no JSONL files in {default}",
                file=sys.stderr,
            )
            return 0

    receipts = iter_receipts(paths)
    normalized = (normalize(r) for r in receipts)

    if args.boundary != "all":
        normalized = (r for r in normalized if r.get("boundary_type") == args.boundary)

    if args.format == "csv":
        emit_csv(normalized)
    else:
        emit_json(normalized)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
