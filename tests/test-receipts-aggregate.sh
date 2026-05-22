#!/bin/bash
# Tests for receipts-aggregate.py
#
# Verifies the JSONL-to-denormalized-table aggregation:
#   - Multiple receipt files → unified CSV/JSON output
#   - --format csv / json work
#   - --boundary filter restricts rows
#   - Malformed JSON lines warned + skipped (not fatal)
#   - Unknown fields land in additional_fields (forward-compat)
#   - Nested objects/lists JSON-encoded for CSV-safety
#   - Empty receipt dir → warning + exit 0 (not error)

set -uo pipefail

CLI="$(dirname "$0")/../scripts/receipts-aggregate.py"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== receipts-aggregate.py tests ==="

# --- Setup: 3 representative receipt files (one per boundary type) ---
cat > "$TMPDIR/destructive-2026-05-21.jsonl" <<'EOF'
{"ts":"2026-05-21T20:00:00Z","boundary_type":"destructive_bash","session_id":"s1","paths":["/tmp/cache"],"scope_match":"cache","decision":"execute"}
{"ts":"2026-05-21T20:05:00Z","boundary_type":"destructive_bash","session_id":"s2","paths":["/home/u/node_modules"],"scope_match":"","decision":"refuse"}
EOF

cat > "$TMPDIR/dispatch-2026-05-21.jsonl" <<'EOF'
{"ts":"2026-05-21T20:10:00Z","boundary_type":"dispatch_end","session_id":"s1","subagent_type":"CLINIC","prompt_hash":"deadbeef","prompt_length":42,"decision":"execute"}
EOF

cat > "$TMPDIR/articulated-scope-2026-05-21.jsonl" <<'EOF'
{"ts":"2026-05-21T19:59:00Z","boundary_type":"user_prompt_submit","session_id":"s1","articulated_scope_hash":"abc123","articulated_scope_length":28}
EOF

# --- Test 1: CSV format, all receipts aggregated ---
OUT=$(python3 "$CLI" "$TMPDIR"/*.jsonl --format csv)
HEADER=$(echo "$OUT" | head -1)
ROW_COUNT=$(echo "$OUT" | tail -n +2 | wc -l)
if echo "$HEADER" | grep -q "boundary_type" && [ "$ROW_COUNT" -eq 4 ]; then
    assert_pass "CSV: header present + 4 rows aggregated across 3 files"
else
    assert_fail "CSV check: header=$HEADER rows=$ROW_COUNT"
fi

# --- Test 2: JSON format, valid JSON array with 4 items ---
OUT_JSON=$(python3 "$CLI" "$TMPDIR"/*.jsonl --format json)
COUNT=$(echo "$OUT_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [ "$COUNT" = "4" ]; then
    assert_pass "JSON: valid array with 4 items"
else
    assert_fail "JSON count expected 4, got $COUNT"
fi

# --- Test 3: --boundary filter restricts rows ---
OUT=$(python3 "$CLI" "$TMPDIR"/*.jsonl --format csv --boundary user_prompt_submit)
ROW_COUNT=$(echo "$OUT" | tail -n +2 | wc -l)
if [ "$ROW_COUNT" -eq 1 ]; then
    assert_pass "--boundary user_prompt_submit → 1 row"
else
    assert_fail "boundary filter row count expected 1, got $ROW_COUNT"
fi

OUT=$(python3 "$CLI" "$TMPDIR"/*.jsonl --format csv --boundary destructive_bash)
ROW_COUNT=$(echo "$OUT" | tail -n +2 | wc -l)
if [ "$ROW_COUNT" -eq 2 ]; then
    assert_pass "--boundary destructive_bash → 2 rows"
else
    assert_fail "boundary filter row count expected 2, got $ROW_COUNT"
fi

# --- Test 4: malformed JSON line warned + skipped (not fatal) ---
echo "this is not valid json" >> "$TMPDIR/destructive-2026-05-21.jsonl"
OUT=$(python3 "$CLI" "$TMPDIR"/*.jsonl --format csv 2>/dev/null)
ROW_COUNT=$(echo "$OUT" | tail -n +2 | wc -l)
if [ "$ROW_COUNT" -eq 4 ]; then
    assert_pass "malformed JSON line skipped; valid rows still emitted (4 total)"
else
    assert_fail "malformed handling failed: row count $ROW_COUNT (expected 4)"
fi

STDERR=$(python3 "$CLI" "$TMPDIR"/*.jsonl --format csv 2>&1 > /dev/null)
if echo "$STDERR" | grep -q "invalid JSON skipped"; then
    assert_pass "malformed JSON warned to stderr"
else
    assert_fail "expected stderr warning for malformed line, got: $STDERR"
fi

# --- Test 5: unknown fields preserved in additional_fields ---
cat > "$TMPDIR/extras-2026-05-21.jsonl" <<'EOF'
{"ts":"2026-05-21T21:00:00Z","boundary_type":"destructive_bash","custom_field":"value123","experimental_v3_field":42}
EOF
OUT=$(python3 "$CLI" "$TMPDIR/extras-2026-05-21.jsonl" --format json)
if echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
extras = json.loads(d[0]['additional_fields'])
assert 'custom_field' in extras, f'custom_field missing from extras'
assert extras['custom_field'] == 'value123', f'wrong value: {extras}'
assert extras['experimental_v3_field'] == 42, f'wrong int: {extras}'
" 2>&1; then
    assert_pass "unknown fields preserved in additional_fields (forward-compat)"
else
    assert_fail "extras preservation failed"
fi

# --- Test 6: nested objects in known fields JSON-encoded for CSV-safety ---
cat > "$TMPDIR/nested-2026-05-21.jsonl" <<'EOF'
{"ts":"2026-05-21T22:00:00Z","boundary_type":"destructive_bash","paths":["a","b","c"],"decision":"refuse"}
EOF
OUT=$(python3 "$CLI" "$TMPDIR/nested-2026-05-21.jsonl" --format csv)
if echo "$OUT" | grep -q '"\[""a"", ""b"", ""c""\]"'; then
    assert_pass "nested list JSON-encoded in CSV cell"
else
    # Alt: CSV quoting may differ; check that list-as-string appears
    DATA_ROW=$(echo "$OUT" | tail -n +2 | head -1)
    if echo "$DATA_ROW" | grep -qE '\["a", "b", "c"\]'; then
        assert_pass "nested list JSON-encoded in CSV (alt quoting)"
    else
        assert_fail "nested list encoding check: $DATA_ROW"
    fi
fi

# --- Test 7: empty paths arg + non-existent default → warning + exit 0 ---
EMPTY_HOME=$(mktemp -d)
OUT=$(HOME="$EMPTY_HOME" python3 "$CLI" --format csv 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$OUT" | grep -q "no JSONL files"; then
    assert_pass "empty default receipts dir → exit 0 + stderr warning"
else
    assert_fail "empty dir handling: rc=$rc out=$OUT"
fi
rm -rf "$EMPTY_HOME"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
