#!/bin/bash
# Tests for account-billing-log.sh
HOOK="examples/account-billing-log.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_file_contains() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (file $2 missing '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }
assert_eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3', got '$2')"; fi; }

HOOK_ABS="$PWD/$HOOK"
LOG_DIR="$TMPDIR/billing"
LOG_FILE="$LOG_DIR/sessions.log"

# Test 1: Basic logging with all metadata
OUT=$(CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=client-a \
    echo '{"session_id":"abc123","turn_count":47}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" ANTHROPIC_ACCOUNT_LABEL=client-a bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "basic exit 0" "$RC" "0"
assert_file_contains "log has account" "$LOG_FILE" "client-a"
assert_file_contains "log has session id" "$LOG_FILE" "session:abc123"
assert_file_contains "log has turns" "$LOG_FILE" "turns:47"

# Test 2: Missing metadata defaults to unknown / 0
rm -f "$LOG_FILE"
OUT=$(echo '{}' | CC_BILLING_LOG_DIR="$LOG_DIR" ANTHROPIC_ACCOUNT_LABEL=work bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "empty meta exit 0" "$RC" "0"
assert_file_contains "empty meta logs account" "$LOG_FILE" "| work |"
assert_file_contains "empty meta session unknown" "$LOG_FILE" "session:unknown"
assert_file_contains "empty meta turns zero" "$LOG_FILE" "turns:0"

# Test 3: Missing ANTHROPIC_ACCOUNT_LABEL defaults to unknown
rm -f "$LOG_FILE"
OUT=$(echo '{"session_id":"xyz"}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    bash -c "unset ANTHROPIC_ACCOUNT_LABEL; bash $HOOK_ABS" 2>&1); RC=$?
assert_exit "no label exit 0" "$RC" "0"
assert_file_contains "no label logs unknown" "$LOG_FILE" "| unknown |"

# Test 4: Alternative session field names accepted
rm -f "$LOG_FILE"
OUT=$(echo '{"sessionId":"camelCase123","turns":12}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=personal bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "alt fields exit 0" "$RC" "0"
assert_file_contains "alt sessionId accepted" "$LOG_FILE" "session:camelCase123"
assert_file_contains "alt turns accepted" "$LOG_FILE" "turns:12"

# Test 5: Disable env var skips logging entirely
rm -f "$LOG_FILE"
OUT=$(echo '{"session_id":"willnotlog"}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=personal \
    CC_BILLING_LOG_DISABLE=1 bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "disable exit 0" "$RC" "0"
if [ -f "$LOG_FILE" ] && grep -q "willnotlog" "$LOG_FILE"; then
    FAIL=$((FAIL+1)); echo "FAIL: disable should not write"
else
    PASS=$((PASS+1))
fi

# Test 6: Pipe characters in PWD are sanitized
rm -f "$LOG_FILE"
WEIRD_DIR="$TMPDIR/has|pipe|chars"
mkdir -p "$WEIRD_DIR"
OUT=$(cd "$WEIRD_DIR" && echo '{"session_id":"piped"}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=work bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "pipe sanitized exit 0" "$RC" "0"
# Path in log line should have pipes replaced with underscores
LINE=$(cat "$LOG_FILE")
PIPE_COUNT=$(printf '%s' "$LINE" | tr -cd '|' | wc -c | tr -d ' ')
assert_eq "log line has exactly 4 pipes (delimiters only)" "$PIPE_COUNT" "4"

# Test 7: Multiple sessions append (do not overwrite)
rm -f "$LOG_FILE"
echo '{"session_id":"first"}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=work bash "$HOOK_ABS" 2>/dev/null
echo '{"session_id":"second"}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=work bash "$HOOK_ABS" 2>/dev/null
LINE_COUNT=$(wc -l < "$LOG_FILE")
assert_eq "two sessions append (2 lines)" "$LINE_COUNT" "2"
assert_file_contains "first session preserved" "$LOG_FILE" "session:first"
assert_file_contains "second session appended" "$LOG_FILE" "session:second"

# Test 8: Log line is parseable (5 fields, pipe-separated)
rm -f "$LOG_FILE"
echo '{"session_id":"parse-me","turn_count":7}' | \
    CC_BILLING_LOG_DIR="$LOG_DIR" \
    ANTHROPIC_ACCOUNT_LABEL=client-b bash "$HOOK_ABS" 2>/dev/null
FIELD_COUNT=$(awk -F' \\| ' 'END{print NF}' "$LOG_FILE")
assert_eq "log line has 5 pipe-separated fields" "$FIELD_COUNT" "5"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
