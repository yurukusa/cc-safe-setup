#!/bin/bash
# autonomy-blocked-summary.sh — Summarise AskUserQuestion blocks recorded by
# askuserquestion-autonomy-gate.sh over the past N hours.
#
# Companion script for the operator who runs /goal overnight or autonomous
# tasks with CC_AUTONOMY_MODE=1. After the agent runs, this script prints
# a quick "how many AskUserQuestion calls were blocked, and when?" summary
# so the operator can decide whether to relax the autonomy mode for some
# legitimate question topics in future runs.
#
# Usage:
#   ./autonomy-blocked-summary.sh                    # past 24 hours
#   ./autonomy-blocked-summary.sh --hours 12         # past 12 hours
#   ./autonomy-blocked-summary.sh --hours 24 --json  # past 24 hours, JSON
#
# Reads from $CC_AUTONOMY_MODE_RECEIPT_DIR (default: ~/.claude/receipts).
# Returns exit 0 always; this is read-only reporting, not gating.

set -u

HOURS=24
FORMAT=text

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hours) HOURS="$2"; shift 2 ;;
        --json) FORMAT=json; shift ;;
        -h|--help)
            cat <<EOF
autonomy-blocked-summary.sh — summarise blocked AskUserQuestion calls

Usage: $0 [--hours N] [--json]

Reads JSONL receipts from \$CC_AUTONOMY_MODE_RECEIPT_DIR (default ~/.claude/receipts)
and prints how many AskUserQuestion calls were blocked in the past N hours.
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

RECEIPT_DIR="${CC_AUTONOMY_MODE_RECEIPT_DIR:-$HOME/.claude/receipts}"
if [[ ! -d "$RECEIPT_DIR" ]]; then
    if [[ "$FORMAT" = json ]]; then
        echo '{"error":"receipt_dir_not_found","path":"'"$RECEIPT_DIR"'"}'
    else
        echo "No receipt directory at $RECEIPT_DIR. Has the hook fired yet?" >&2
    fi
    exit 0
fi

# Cutoff: now - HOURS hours, as ISO 8601 UTC
CUTOFF=$(python3 -c "
import datetime
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=$HOURS)
print(cutoff.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null) || {
    echo "python3 required for time calculation" >&2
    exit 1
}

# Gather receipts. The hook writes one file per UTC date:
# autonomy-blocked-YYYY-MM-DD.jsonl
RECEIPTS=$(find "$RECEIPT_DIR" -maxdepth 1 -type f -name 'autonomy-blocked-*.jsonl' 2>/dev/null)
if [[ -z "$RECEIPTS" ]]; then
    if [[ "$FORMAT" = json ]]; then
        echo '{"hours":'"$HOURS"',"blocked_count":0,"earliest":null,"latest":null}'
    else
        echo "No autonomy-block receipts found in $RECEIPT_DIR."
        echo "Either no AskUserQuestion was blocked, or CC_AUTONOMY_MODE was never set."
    fi
    exit 0
fi

# Filter and summarise via python (stdlib only)
echo "$RECEIPTS" | python3 -c "
import sys
import json
import os

cutoff = '$CUTOFF'
hours = $HOURS
fmt = '$FORMAT'

files = [line.strip() for line in sys.stdin if line.strip()]
records = []
for path in files:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = rec.get('ts', '')
                if ts and ts >= cutoff:
                    records.append(rec)
    except (IOError, OSError):
        continue

records.sort(key=lambda r: r.get('ts', ''))

count = len(records)
earliest = records[0].get('ts') if records else None
latest = records[-1].get('ts') if records else None

# Distribution of question lengths
lengths = [r.get('question_length', 0) for r in records if r.get('question_length')]
if lengths:
    avg_len = sum(lengths) / len(lengths)
    max_len = max(lengths)
    min_len = min(lengths)
else:
    avg_len = max_len = min_len = 0

if fmt == 'json':
    out = {
        'hours': hours,
        'blocked_count': count,
        'earliest': earliest,
        'latest': latest,
        'question_length_stats': {
            'avg': round(avg_len, 1),
            'max': max_len,
            'min': min_len,
        },
    }
    print(json.dumps(out))
else:
    print(f'AskUserQuestion blocks in the past {hours} hours: {count}')
    if count > 0:
        print(f'  Earliest: {earliest}')
        print(f'  Latest:   {latest}')
        print(f'  Question length stats (bytes): avg {avg_len:.1f}, min {min_len}, max {max_len}')
        if count >= 10:
            print('')
            print('  10 or more blocks suggests the autonomy rule is colliding with')
            print('  a genuine need for the model to ask. Consider whether some')
            print('  question topics (e.g. \"destructive operation? y/N\") deserve')
            print('  a narrower allowlist rather than a blanket block.')
    else:
        print('  (No blocks recorded. Either the hook was not configured, or the')
        print('  model never tried to ask a question during the window.)')
"
