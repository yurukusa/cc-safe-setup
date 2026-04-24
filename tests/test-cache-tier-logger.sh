#!/bin/bash
# Tests for cache-tier-logger.sh
HOOK="examples/cache-tier-logger.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }
assert_file_contains() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in $2)"; fi; }

LOG="${HOME}/.claude/logs/cache-tier.log"
mkdir -p "${HOME}/.claude/logs"
: > "$LOG"

# Test 1: cache_hit tier logged when cache_read_input_tokens present
PAYLOAD='{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":5000,"cache_creation_input_tokens":0}}}'
OUT=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "cache_hit path exits 0" "$RC" 0
assert_file_contains "cache_hit logged" "$LOG" "cache_hit"
assert_file_contains "session_id logged" "$LOG" "s1"
assert_file_contains "tool_name logged" "$LOG" "Read"
assert_file_contains "cache_read value logged" "$LOG" "5000"

# Test 2: cache_miss tier when only cache_creation_input_tokens present
: > "$LOG"
PAYLOAD='{"session_id":"s2","tool_name":"Edit","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":12000}}}'
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_file_contains "cache_miss logged" "$LOG" "cache_miss"
assert_file_contains "creation value logged" "$LOG" "12000"

# Test 3: no_cache_data when neither field is present
: > "$LOG"
PAYLOAD='{"session_id":"s3","tool_name":"Bash","tool_response":{}}'
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_file_contains "no_cache_data logged" "$LOG" "no_cache_data"

# Test 4: transcript fallback when tool_response.usage is empty
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{"cache_read_input_tokens":9999,"cache_creation_input_tokens":1}}}\n' >> "$TRANS"
: > "$LOG"
PAYLOAD=$(printf '{"session_id":"s4","tool_name":"Read","transcript_path":"%s","tool_response":{}}' "$TRANS")
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_file_contains "fallback reads transcript usage" "$LOG" "9999"
rm -f "$TRANS"

# Test 5: exit 0 even when jq encounters malformed input (robustness)
OUT=$(printf 'not-json' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "malformed input still exits 0" "$RC" 0

# Test 6: TSV format (exactly 6 tab-separated fields)
: > "$LOG"
PAYLOAD='{"session_id":"s6","tool_name":"Grep","tool_response":{"usage":{"cache_read_input_tokens":100,"cache_creation_input_tokens":0}}}'
printf '%s' "$PAYLOAD" | bash "$HOOK"
FIELDS=$(awk -F'\t' '{print NF}' "$LOG" | head -1)
if [ "$FIELDS" = "6" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 6 TSV fields, got $FIELDS"; fi

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
