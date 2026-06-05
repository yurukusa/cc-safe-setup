#!/bin/bash
# Tests for halt-signal-detector.sh (Issue #55909 prevention)
HOOK="examples/halt-signal-detector.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Setup: write fake transcripts
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Helper: build a minimal transcript line for a user message
make_user_msg() {
    local TEXT="$1"
    printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(printf '%s' "$TEXT" | jq -Rsa .)"
}

# Test 1: No transcript path, silent pass
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no transcript no warning" "$OUT" "halt-signal-detector"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Empty transcript file, silent pass
TR="$TMPDIR/empty.jsonl"
: > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty transcript no warning" "$OUT" "halt-signal-detector"
assert_exit "empty transcript exit 0" "$RC" "0"

# Test 3: User message without halt signal, silent pass
TR="$TMPDIR/normal.jsonl"
make_user_msg "please continue refactoring the auth module" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "normal message no warning" "$OUT" "halt-signal-detector"
assert_exit "normal message exit 0" "$RC" "0"

# Test 4: User says "stop" in English, warn but advisory
TR="$TMPDIR/stop-en.jsonl"
make_user_msg "stop, do not continue with that approach" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "stop en warns" "$OUT" "halt-signal-detector"
assert_contains "stop en references issue" "$OUT" "55909"
assert_exit "stop en advisory exit 0" "$RC" "0"

# Test 5: User says "やめて" in Japanese (the #55909 phrase), warn
TR="$TMPDIR/yamete.jsonl"
make_user_msg "やめて、 違うブラウザを使って" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "yamete warns" "$OUT" "halt-signal-detector"
assert_contains "yamete shows context" "$OUT" "やめて"
assert_exit "yamete advisory exit 0" "$RC" "0"

# Test 6: User says "止めて" (formal Japanese stop), warn
TR="$TMPDIR/tomete.jsonl"
make_user_msg "そこは触らないで、 止めて" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "tomete warns" "$OUT" "halt-signal-detector"
assert_exit "tomete advisory exit 0" "$RC" "0"

# Test 7: Block mode (CC_HALT_SIGNAL_BLOCK=1), exit 2
TR="$TMPDIR/block.jsonl"
make_user_msg "stop right now" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_HALT_SIGNAL_BLOCK=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "block mode warns" "$OUT" "halt-signal-detector"
assert_exit "block mode exit 2" "$RC" "2"

# Test 8: Idle nudge (system-generated) is ignored
TR="$TMPDIR/idle.jsonl"
make_user_msg "[idle 180s / 2026-05-06 08:18 JST] please continue" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "idle nudge ignored" "$OUT" "halt-signal-detector"
assert_exit "idle nudge exit 0" "$RC" "0"

# Test 9: Most recent message wins (only last user msg checked)
TR="$TMPDIR/multi.jsonl"
{
    make_user_msg "stop everything"
    make_user_msg "ok continue with the new approach"
} > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "latest message wins (no halt in latest)" "$OUT" "halt-signal-detector"
assert_exit "latest message wins exit 0" "$RC" "0"

# Test 10: Content as array of blocks (Claude API format)
TR="$TMPDIR/array.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"please halt the deployment"}]}}\n' > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "array content warns" "$OUT" "halt-signal-detector"
assert_exit "array content advisory exit 0" "$RC" "0"

# Test 11: CC_HALT_SIGNAL_EXTRA env adds custom tokens
TR="$TMPDIR/extra.jsonl"
make_user_msg "kill the process now" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_HALT_SIGNAL_EXTRA="kill,terminate" bash "$HOOK" 2>&1)
RC=$?
assert_contains "extra token warns" "$OUT" "halt-signal-detector"
assert_exit "extra token advisory exit 0" "$RC" "0"

# Test 12: Without extra env, "kill" alone is not a halt token
TR="$TMPDIR/kill-no-extra.jsonl"
make_user_msg "kill the process now" > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "kill alone no warning" "$OUT" "halt-signal-detector"
assert_exit "kill alone exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
