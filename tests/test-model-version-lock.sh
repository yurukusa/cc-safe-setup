#!/bin/bash
# Tests for model-version-lock.sh
HOOK="examples/model-version-lock.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

LOCK_DIR="${HOME}/.claude/logs/model-locks"
mkdir -p "$LOCK_DIR"

# Test 1: First call writes lock, no banner
SESS="test-session-$(date +%s%N)-1"
LOCK_FILE="${LOCK_DIR}/${SESS}.model"
rm -f "$LOCK_FILE"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"model":"opus-4.7","usage":{}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "first call exits 0" "$RC" 0
assert_not_contains "no banner on first call" "$OUT" "model-version-lock"
if [ "$(cat "$LOCK_FILE" 2>/dev/null)" = "opus-4.7" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: lock not written (got '$(cat "$LOCK_FILE" 2>/dev/null)')"; fi
rm -f "$TRANS" "$LOCK_FILE"

# Test 2: Same model on second call → no banner
SESS="test-session-$(date +%s%N)-2"
LOCK_FILE="${LOCK_DIR}/${SESS}.model"
printf 'opus-4.7\n' > "$LOCK_FILE"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"model":"opus-4.7","usage":{}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
assert_not_contains "same model no banner" "$OUT" "model-version-lock"
rm -f "$TRANS" "$LOCK_FILE"

# Test 3: Model changed → banner with both names
SESS="test-session-$(date +%s%N)-3"
LOCK_FILE="${LOCK_DIR}/${SESS}.model"
printf 'opus-4.7\n' > "$LOCK_FILE"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"model":"opus-4.6","usage":{}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "mismatch exits 0" "$RC" 0
assert_contains "banner contains lock→model" "$OUT" "opus-4.7 → opus-4.6"
assert_contains "banner references #49541" "$OUT" "#49541"
assert_contains "banner mentions /model switch path" "$OUT" "/model"
# Lock file should now reflect the new model (we do not re-alert on the same transition)
if [ "$(cat "$LOCK_FILE")" = "opus-4.6" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: lock should update after alert"; fi
rm -f "$TRANS" "$LOCK_FILE"

# Test 4: CLAUDE_MODEL env fallback when transcript has no model
SESS="test-session-$(date +%s%N)-4"
LOCK_FILE="${LOCK_DIR}/${SESS}.model"
rm -f "$LOCK_FILE"
TRANS=$(mktemp)
printf '{"type":"user","message":{"content":"hello"}}\n' >> "$TRANS"
OUT=$(CLAUDE_MODEL="sonnet-4.6" printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
# Note: `env VAR=x printf ...` runs printf with VAR but doesn't pipe; rewrite as shell export
rm -f "$LOCK_FILE"
export CLAUDE_MODEL="sonnet-4.6"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
unset CLAUDE_MODEL
if [ "$(cat "$LOCK_FILE" 2>/dev/null)" = "sonnet-4.6" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: env fallback should write lock (got '$(cat "$LOCK_FILE" 2>/dev/null)')"; fi
rm -f "$TRANS" "$LOCK_FILE"

# Test 5: Missing session_id → no-op exit 0
OUT=$(printf '{"tool_name":"x"}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing session_id exits 0" "$RC" 0

# Test 6: No transcript and no env fallback → no lock written, exit 0
SESS="test-session-$(date +%s%N)-6"
LOCK_FILE="${LOCK_DIR}/${SESS}.model"
rm -f "$LOCK_FILE"
OUT=$(printf '{"session_id":"%s"}' "$SESS" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no signal exits 0" "$RC" 0
if [ ! -e "$LOCK_FILE" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: no-signal path should not write lock"; fi
rm -f "$LOCK_FILE"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
