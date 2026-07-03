#!/bin/bash
# Tests for stop-transcript-write-health.sh (#73937)
# Run: bash tests/stop-transcript-write-health.test.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/stop-transcript-write-health.sh"

TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT
TP="$TESTHOME/session.jsonl"
SID="t-sid"

run() { HOME="$TESTHOME" bash "$HOOK" <<EOF
{"transcript_path":"$TP","session_id":"$SID"}
EOF
}

assert_warns() { # $1 = expect "warn" or "quiet", $2 = desc
    local out; out=$(run)
    if [ "$1" = "warn" ]; then
        if printf '%s' "$out" | grep -q "systemMessage"; then echo "  PASS: $2"; PASS=$((PASS+1)); else echo "  FAIL: $2 (expected warning, got: ${out:-none})"; FAIL=$((FAIL+1)); fi
    else
        if [ -z "$out" ]; then echo "  PASS: $2"; PASS=$((PASS+1)); else echo "  FAIL: $2 (expected quiet, got: $out)"; FAIL=$((FAIL+1)); fi
    fi
}

echo "stop-transcript-write-health.sh tests"
echo ""

printf 'a\nb\nc\n' > "$TP"
assert_warns quiet "first turn: no prior state -> quiet, records baseline"

printf 'd\ne\n' >> "$TP"; touch "$TP"
assert_warns quiet "normal growth (3->5 lines) -> quiet"

# same lines, same mtime as recorded -> silent save-stop
assert_warns warn "silent stall (line count + mtime unchanged) -> warn"

printf 'x\ny\n' > "$TP"   # shrink: 5 -> 2
assert_warns warn "revert (line count shrank) -> warn"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
