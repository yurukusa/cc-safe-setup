#!/bin/bash
# Tests for effort-tracking-logger.sh
HOOK="examples/effort-tracking-logger.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

LOG_DIR="${HOME}/.claude/effort-log"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
rm -rf "$LOG_DIR"

# Test 1: Creates log directory
echo '{"tool_name":"Bash","was_error":"false"}' | bash "$HOOK" 2>&1
RC=$?
assert_exit "exit 0" "$RC" 0
if [ -d "$LOG_DIR" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: log dir not created"; fi

# Test 2: Log file created with valid JSONL
if [ -f "$LOG_FILE" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: log file not created"; fi
ENTRY=$(cat "$LOG_FILE")
assert_contains "has timestamp" "$ENTRY" "timestamp"
assert_contains "has tool name" "$ENTRY" "Bash"
assert_contains "has error field" "$ENTRY" "error"

# Test 3: Valid JSON
python3 -c "import json; json.loads(open('$LOG_FILE').read().strip())" 2>/dev/null
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: invalid JSON"; fi

# Test 4: Multiple entries appended
echo '{"tool_name":"Read","was_error":"false"}' | bash "$HOOK" 2>&1
echo '{"tool_name":"Edit","was_error":"true"}' | bash "$HOOK" 2>&1
LINES=$(wc -l < "$LOG_FILE")
if [ "$LINES" -eq 3 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 3 lines, got $LINES"; fi

# Test 5: Error field correctly parsed
LAST=$(tail -1 "$LOG_FILE")
assert_contains "error=true parsed" "$LAST" '"error": true'

# Test 6: Tool name correctly parsed
SECOND=$(sed -n '2p' "$LOG_FILE")
assert_contains "Read tool name" "$SECOND" '"tool": "Read"'

# Test 7: Unknown tool handled
echo '{}' | bash "$HOOK" 2>&1
RC=$?
assert_exit "unknown tool exit 0" "$RC" 0
LAST=$(tail -1 "$LOG_FILE")
assert_contains "unknown tool logged" "$LAST" "unknown"

# Cleanup
rm -rf "$LOG_DIR"

echo "effort-tracking-logger: $PASS passed, $FAIL failed"
exit $FAIL
