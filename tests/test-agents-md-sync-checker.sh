set -u
HOOK="$(dirname "$0")/../examples/agents-md-sync-checker.sh"
PASS=0
FAIL=0
TMP=$(mktemp -d /tmp/test-agents-sync.XXXXXX)
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
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/missing-agents.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/missing-claude.md" bash "$HOOK")
assert_no_output "neither file present produces no output" "$output"
echo "claude only" > "$TMP/claude-only.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/missing-agents.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/claude-only.md" bash "$HOOK")
assert_no_output "only CLAUDE.md produces no output" "$output"
echo "agents only content" > "$TMP/agents-only.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/agents-only.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/no-claude.md" bash "$HOOK")
assert_contains "only AGENTS.md surfaces missing CLAUDE.md" "$output" "no CLAUDE.md found"
echo "shared content here" > "$TMP/both-identical-a.md"
cp "$TMP/both-identical-a.md" "$TMP/both-identical-c.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/both-identical-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/both-identical-c.md" bash "$HOOK")
assert_contains "identical content suggests symlink" "$output" "Consider replacing one with a symlink"
echo "linked content" > "$TMP/source-a.md"
ln -sf "$TMP/source-a.md" "$TMP/source-c.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/source-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/source-c.md" bash "$HOOK")
assert_no_output "symlinked files produce no output" "$output"
echo "short" > "$TMP/drift-a.md"
python3 -c "print('long ' * 100)" > "$TMP/drift-c.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/drift-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/drift-c.md" bash "$HOOK")
assert_contains "size delta drift detected" "$output" "differ by"
assert_contains "drift warning includes percentage" "$output" "%"
echo "content one" > "$TMP/close-a.md"
echo "content two" > "$TMP/close-c.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/close-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/close-c.md" bash "$HOOK")
assert_contains "close-size different content surfaces" "$output" "content differs"
echo "content one" > "$TMP/delta-a.md"
echo "longer different content for testing" > "$TMP/delta-c.md"
output_default=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/delta-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/delta-c.md" bash "$HOOK")
output_high=$(echo '{}' | CC_AGENTS_MD_SIZE_DELTA_PCT=90 CC_AGENTS_MD_FILES="$TMP/delta-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/delta-c.md" bash "$HOOK")
if echo "$output_default" | grep -q "differ by" && echo "$output_high" | grep -q "content differs"; then
    echo "  PASS: DELTA_PCT threshold affects drift vs close-size classification"
    PASS=$((PASS + 1))
else
    echo "  FAIL: DELTA_PCT threshold did not affect classification"
    FAIL=$((FAIL + 1))
fi
echo "x" > "$TMP/exit-a.md"
echo '{}' | CC_AGENTS_MD_FILES="$TMP/exit-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/missing.md" bash "$HOOK" > /dev/null
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    echo "  PASS: hook exits 0 even with findings"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook should exit 0, got $exit_code"
    FAIL=$((FAIL + 1))
fi
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/exit-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/missing.md" bash "$HOOK")
if echo "$output" | jq empty 2>/dev/null; then
    echo "  PASS: output is valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output should be valid JSON: $output"
    FAIL=$((FAIL + 1))
fi
event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // empty')
if [ "$event" = "SessionStart" ]; then
    echo "  PASS: hookEventName is SessionStart"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hookEventName should be SessionStart, got '$event'"
    FAIL=$((FAIL + 1))
fi
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/exit-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/missing.md" bash "$HOOK")
assert_contains "warning references #6235" "$output" "#6235"
assert_contains "warning lists mitigation patterns" "$output" "Mitigation patterns"
assert_contains "warning includes reaction count" "$output" "5,196 reactions"
mkdir -p "$TMP/agents-dir"
echo "first match" > "$TMP/agents-dir/agents-first.md"
echo "second" > "$TMP/agents-second.md"
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/agents-dir/agents-first.md:$TMP/agents-second.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/no-claude.md" bash "$HOOK")
assert_contains "first matching AGENTS.md is selected" "$output" "agents-first.md"
echo "unreadable" > "$TMP/unread-a.md"
chmod 000 "$TMP/unread-a.md" 2>/dev/null
output=$(echo '{}' | CC_AGENTS_MD_FILES="$TMP/unread-a.md" CC_CLAUDE_MD_FILES_FOR_SYNC="$TMP/no-claude.md" bash "$HOOK" 2>/dev/null)
chmod 644 "$TMP/unread-a.md" 2>/dev/null
assert_no_output "unreadable file skipped" "$output"
echo ""
echo "=============================="
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
