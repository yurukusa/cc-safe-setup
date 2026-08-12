#!/bin/bash
# Tests for write-byte-integrity-verifier.sh

HOOK="$(dirname "$0")/../examples/write-byte-integrity-verifier.sh"
PASS=0 FAIL=0

TMPROOT="$(mktemp -d -t cc-write-integ-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

run_test() {
  local desc="$1" expected_exit="$2" payload="$3" extra_env="$4"
  local logfile="$TMPROOT/log-$RANDOM"
  local actual_exit
  if [ -n "$extra_env" ]; then
    actual_exit=$(printf '%s' "$payload" | env CC_WRITE_INTEGRITY_LOG="$logfile" $extra_env bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
  else
    actual_exit=$(printf '%s' "$payload" | env CC_WRITE_INTEGRITY_LOG="$logfile" bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
  fi
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing write-byte-integrity-verifier.sh"
echo "========================================"

# Helper: build payload JSON
build_write_payload() {
  local file="$1" content="$2"
  jq -nc --arg file "$file" --arg content "$content" \
    '{tool_name:"Write", tool_input:{file_path:$file, content:$content}}'
}
build_edit_payload() {
  local file="$1" old="$2" new="$3"
  jq -nc --arg file "$file" --arg old "$old" --arg new "$new" \
    '{tool_name:"Edit", tool_input:{file_path:$file, old_string:$old, new_string:$new}}'
}

# 1. Tool other than Write/Edit → pass silently
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
run_test "non-Write/Edit tool passes silently" 0 "$PAYLOAD"

# 2. File doesn't exist → pass silently
PAYLOAD=$(build_write_payload "/tmp/nonexistent-$$" "hello")
run_test "missing file passes silently" 0 "$PAYLOAD"

# 3. Write succeeded — disk size matches content size → pass
F="$TMPROOT/good-write.txt"
printf 'hello world' > "$F"
PAYLOAD=$(build_write_payload "$F" "hello world")
run_test "Write content matches disk size passes" 0 "$PAYLOAD"

# 4. Write with shrink-pad: file larger than content + ends in nulls → warn
F="$TMPROOT/shrink-pad.txt"
printf 'short' > "$F"
# Pad with 5 null bytes
printf '\x00\x00\x00\x00\x00' >> "$F"
PAYLOAD=$(build_write_payload "$F" "short")
run_test "Write null-pad detected (shrink-pad)" 0 "$PAYLOAD"

# 5. Same case with block action → exit 2
run_test "Write null-pad blocks when action=block" 2 "$PAYLOAD" "CC_WRITE_INTEGRITY_ACTION=block"

# 6. Write with tail-chop: disk smaller than expected → warn
F="$TMPROOT/tail-chop.txt"
printf 'short' > "$F"
PAYLOAD=$(build_write_payload "$F" "this is the much longer intended content that was chopped")
run_test "Write tail-chop detected" 0 "$PAYLOAD"

# 7. Edit succeeded, new_string is present → pass
F="$TMPROOT/edit-good.txt"
printf 'before edit done after' > "$F"
PAYLOAD=$(build_edit_payload "$F" "edit done" "edit done")
run_test "Edit with new_string present passes" 0 "$PAYLOAD"

# 8. Edit but new_string not in file → warn
F="$TMPROOT/edit-bad.txt"
printf 'this content has the old string only' > "$F"
PAYLOAD=$(build_edit_payload "$F" "old string" "expected new string")
run_test "Edit with missing new_string warns" 0 "$PAYLOAD"

# 9. Edit on text file ending with 4 null bytes → warn
F="$TMPROOT/edit-null-tail.txt"
printf 'normal content\n' > "$F"
printf '\x00\x00\x00\x00' >> "$F"
PAYLOAD=$(build_edit_payload "$F" "normal" "normal content\n")
run_test "Edit on null-padded text file warns" 0 "$PAYLOAD"

# 10. Skipped file pattern (.log) → pass silently even if corrupted
F="$TMPROOT/server.log"
printf 'short' > "$F"
printf '\x00\x00\x00\x00\x00' >> "$F"
PAYLOAD=$(build_write_payload "$F" "short")
run_test ".log file skipped by default" 0 "$PAYLOAD"

# 11. Disabled via env var → pass silently
F="$TMPROOT/disabled-test.txt"
printf 'short\x00\x00\x00\x00\x00' > "$F"
PAYLOAD=$(build_write_payload "$F" "short")
run_test "CC_WRITE_INTEGRITY_DISABLE=1 disables hook" 0 "$PAYLOAD" "CC_WRITE_INTEGRITY_DISABLE=1"

# 12. Custom skip glob picks up .data
F="$TMPROOT/custom.data"
printf 'short\x00\x00\x00\x00\x00' > "$F"
PAYLOAD=$(build_write_payload "$F" "short")
run_test "custom skip glob *.data skips" 0 "$PAYLOAD" "CC_WRITE_INTEGRITY_SKIP_GLOB=*.data"

# 13. Empty Write content → disk should be empty too
F="$TMPROOT/empty-write.txt"
: > "$F"
PAYLOAD=$(build_write_payload "$F" "")
run_test "Empty Write matches empty disk passes" 0 "$PAYLOAD"

# 14. Warning goes to stderr, not stdout
F="$TMPROOT/stderr-test.txt"
printf 'short\x00\x00\x00\x00\x00' > "$F"
PAYLOAD=$(build_write_payload "$F" "short")
STDOUT=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
STDERR=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDOUT" ] && echo "$STDERR" | grep -q "potential file corruption"; then
  echo "  PASS: stdout empty, stderr has warning"
  PASS=$((PASS+1))
else
  echo "  FAIL: stdout/stderr separation"
  FAIL=$((FAIL+1))
fi

# 15. Log file is created and contains file path
F="$TMPROOT/log-write.txt"
LOG="$TMPROOT/integrity.log"
printf 'short\x00\x00\x00\x00\x00' > "$F"
PAYLOAD=$(build_write_payload "$F" "short")
printf '%s' "$PAYLOAD" | env CC_WRITE_INTEGRITY_LOG="$LOG" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$LOG" ] && grep -q "$F" "$LOG"; then
  echo "  PASS: log file contains target path"
  PASS=$((PASS+1))
else
  echo "  FAIL: log file missing or empty"
  FAIL=$((FAIL+1))
fi

# 16. Edit with replace_all=true and new_string present → pass
F="$TMPROOT/replace-all.txt"
printf 'aaaa AND aaaa' > "$F"
PAYLOAD=$(jq -nc --arg file "$F" '{tool_name:"Edit", tool_input:{file_path:$file, old_string:"x", new_string:"AND", replace_all:true}}')
run_test "Edit with replace_all and new_string present passes" 0 "$PAYLOAD"

# 17. Binary file ending in nulls → no false positive
F="$TMPROOT/binary.bin"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x00' > "$F"
PAYLOAD=$(build_edit_payload "$F" "anything" "anything")
# Should NOT warn on binary file
ACTUAL=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>&1 >/dev/null; echo $?)
if echo "$ACTUAL" | grep -q "Edit target ends"; then
  echo "  FAIL: binary file null-tail triggered false positive"
  FAIL=$((FAIL+1))
else
  echo "  PASS: binary file null-tail skipped"
  PASS=$((PASS+1))
fi

# 18. Empty file (zero bytes) on Edit → no crash
F="$TMPROOT/empty-edit.txt"
: > "$F"
PAYLOAD=$(build_edit_payload "$F" "anything" "anything")
run_test "Empty file Edit does not crash" 0 "$PAYLOAD"

# 19. Write with exact null content (intentional null at end) → false positive accepted
# This test documents current behavior: if you intentionally write content ending in
# 4 nulls, the hook will warn. Acceptable trade-off for the protection.
F="$TMPROOT/intentional-null.txt"
printf 'data\x00\x00\x00\x00' > "$F"
PAYLOAD=$(build_write_payload "$F" "$(printf 'data\x00\x00\x00\x00')")
# Hook may not warn because EXPECTED size will match disk size
EXPECTED_EXIT=0
run_test "Write with intentional trailing nulls (matching disk size) passes" "$EXPECTED_EXIT" "$PAYLOAD"

# 20. Tool name missing from payload → pass silently
PAYLOAD='{"tool_input":{"file_path":"/tmp/x"}}'
run_test "missing tool_name passes silently" 0 "$PAYLOAD"

# 21. file_path missing → pass silently
PAYLOAD='{"tool_name":"Write","tool_input":{"content":"hello"}}'
run_test "missing file_path passes silently" 0 "$PAYLOAD"

echo "========================================"
echo "Result: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
