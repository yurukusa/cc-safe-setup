set -u
HOOK="$(dirname "$0")/../examples/claude-md-size-monitor.sh"
PASS=0
FAIL=0
TMP=$(mktemp -d /tmp/test-md-size.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
assert_no_output() {
    local desc="$1"
    local output="$2"
    if [ -z "$output" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — unexpected output: $output"
        FAIL=$((FAIL + 1))
    fi
}
assert_contains() {
    local desc="$1"
    local output="$2"
    local needle="$3"
    if echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output: $output"
        FAIL=$((FAIL + 1))
    fi
}
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/missing.md" bash "$HOOK")
assert_no_output "missing file produces no output" "$output"
> "$TMP/empty.md"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/empty.md" bash "$HOOK")
assert_no_output "empty file produces no output" "$output"
echo "Hello, this is a short CLAUDE.md" > "$TMP/small.md"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/small.md" bash "$HOOK")
assert_no_output "small file under budget produces no output" "$output"
python3 -c "print('x' * 30000)" > "$TMP/large.md"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
assert_contains "large file over budget triggers warning" "$output" "budget exceeded"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
assert_contains "warning includes character count" "$output" "30001 chars"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
assert_contains "warning includes tokens" "$output" "tokens"
printf 'a%.0s' {1..4000} > "$TMP/multi-a.md"
printf 'b%.0s' {1..5000} > "$TMP/multi-b.md"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/multi-a.md:$TMP/multi-b.md" CC_CLAUDE_MD_TOKEN_BUDGET=2000 bash "$HOOK")
assert_contains "combined files trigger warning" "$output" "budget exceeded"
assert_contains "breakdown lists first file" "$output" "multi-a.md"
assert_contains "breakdown lists second file" "$output" "multi-b.md"
printf 'a%.0s' {1..500} > "$TMP/tiny-a.md"
printf 'b%.0s' {1..500} > "$TMP/tiny-b.md"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/tiny-a.md:$TMP/tiny-b.md" CC_CLAUDE_MD_TOKEN_BUDGET=2000 bash "$HOOK")
assert_no_output "small combined files produce no output" "$output"
python3 -c "print('y' * 10000)" > "$TMP/cpt.md"
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/cpt.md" CC_CLAUDE_MD_CHARS_PER_TOKEN=100 bash "$HOOK")
assert_no_output "high chars-per-token override avoids warning" "$output"
echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK" > /dev/null
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    echo "  PASS: hook exits 0 even with findings"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook should exit 0, got $exit_code"
    FAIL=$((FAIL + 1))
fi
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
if echo "$output" | jq empty 2>/dev/null; then
    echo "  PASS: output is valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output should be valid JSON: $output"
    FAIL=$((FAIL + 1))
fi
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // empty')
if [ -n "$ctx" ]; then
    echo "  PASS: JSON has hookSpecificOutput.additionalContext"
    PASS=$((PASS + 1))
else
    echo "  FAIL: JSON should have additionalContext: $output"
    FAIL=$((FAIL + 1))
fi
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // empty')
if [ "$event" = "SessionStart" ]; then
    echo "  PASS: hookEventName is SessionStart"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hookEventName should be SessionStart, got '$event'"
    FAIL=$((FAIL + 1))
fi
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
assert_contains "warning includes self-tuning suggestion" "$output" "CC_CLAUDE_MD_TOKEN_BUDGET="
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/large.md" CC_CLAUDE_MD_TOKEN_BUDGET=1000 bash "$HOOK")
assert_contains "warning links to issue 42796" "$output" "42796"
echo "content" > "$TMP/unreadable.md"
chmod 000 "$TMP/unreadable.md" 2>/dev/null
output=$(echo '{}' | CC_CLAUDE_MD_FILES="$TMP/unreadable.md" CC_CLAUDE_MD_TOKEN_BUDGET=1 bash "$HOOK" 2>/dev/null)
chmod 644 "$TMP/unreadable.md" 2>/dev/null
assert_no_output "unreadable file is skipped" "$output"
echo ""
echo "=============================="
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
