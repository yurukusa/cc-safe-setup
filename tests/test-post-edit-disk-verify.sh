#!/bin/bash
# test-post-edit-disk-verify.sh — Test suite for the post-edit-disk-verify hook.
#
# Covers:
#   Group 1: Tool / file gating (skip non-Edit/Write, missing file, etc.)
#   Group 2: Write size-shortfall detection (the #61303 shape)
#   Group 3: Edit content-not-in-file detection
#   Group 4: Configuration env vars (disable, quiet mode)
#   Group 5: Receipt log behavior

set -u

HOOK="$(dirname "$0")/../examples/post-edit-disk-verify.sh"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Override receipt dir into the tmpdir so we don't pollute ~/.claude.
export CC_POST_EDIT_VERIFY_RECEIPT_DIR="$TMPDIR/receipts"

# Helpers
_assert_exit() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual" == "$expected" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILURES+=("$label: expected exit $expected, got $actual")
        echo "  ✗ $label: expected exit $expected, got $actual"
    fi
}

_run_hook() {
    local input="$1"
    printf '%s' "$input" | "$HOOK" 2>/dev/null
    echo "$?"
}

_run_hook_stderr() {
    local input="$1"
    printf '%s' "$input" | "$HOOK" 2>&1 >/dev/null
}

# ============================================================
echo "Group 1: tool / file gating"
# ============================================================

# 1. Non-Edit/Write tool → exit 0
input='{"tool_name":"Read","tool_input":{"file_path":"/tmp/whatever"}}'
_assert_exit "skip non-Edit/Write tool" "0" "$(_run_hook "$input")"

# 2. Empty tool name → exit 0
input='{"tool_name":"","tool_input":{}}'
_assert_exit "skip empty tool name" "0" "$(_run_hook "$input")"

# 3. Edit with missing file_path → exit 0
input='{"tool_name":"Edit","tool_input":{}}'
_assert_exit "skip Edit with missing file_path" "0" "$(_run_hook "$input")"

# 4. Edit on non-existent file (Edit needs existing file) → exit 0
input='{"tool_name":"Edit","tool_input":{"file_path":"/nonexistent/path","new_string":"x","old_string":"y"}}'
_assert_exit "skip Edit on non-existent file" "0" "$(_run_hook "$input")"

# 5. Write on existing well-formed file → exit 0 (file exists, content matches)
f="$TMPDIR/match.txt"
content="$(printf 'A%.0s' $(seq 1 200))"
echo -n "$content" > "$f"
input="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"$content\"}}"
_assert_exit "pass Write where claimed matches actual" "0" "$(_run_hook "$input")"

# 6. CC_POST_EDIT_VERIFY_DISABLE=1 → exit 0 even on bad input
input='{"tool_name":"Write","tool_input":{"file_path":"/nonexistent","content":"abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnopqrstuvwxyz1234567890"}}'
result=$(CC_POST_EDIT_VERIFY_DISABLE=1 bash -c "printf '%s' '$input' | '$HOOK'"; echo $?)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$result" == "0" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ disable env var bypasses checks"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("disable env var: got $result")
    echo "  ✗ disable env var: got $result"
fi

# 7. Tool input with extra fields → exit 0
input='{"tool_name":"Read","tool_input":{"file_path":"/tmp/whatever","extra_field":"ignored"}}'
_assert_exit "ignore extra fields in tool_input" "0" "$(_run_hook "$input")"

# ============================================================
echo "Group 2: Write size-shortfall detection (the #61303 shape)"
# ============================================================

# 8. Write claimed 200 chars but disk shows 50 → divergence detected, exit 2
f="$TMPDIR/shortfall.txt"
echo -n "tiny content" > "$f"  # 12 bytes
big_content="$(printf 'A%.0s' $(seq 1 200))"  # 200 bytes
input="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"$big_content\"}}"
_assert_exit "detect Write size shortfall (200 claimed, 12 actual)" "2" "$(_run_hook "$input")"

# 9. Stderr message references #61303 on the shortfall
err=$(_run_hook_stderr "$input")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$err" | grep -q "61303"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ stderr references anthropics/claude-code#61303"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("stderr missing #61303 reference")
    echo "  ✗ stderr missing #61303 reference (got: $err)"
fi

# 10. Write of small content (< 100 bytes claimed) → skip check, exit 0
f="$TMPDIR/small.txt"
echo -n "x" > "$f"
input="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"tiny\"}}"
_assert_exit "skip size check for small writes (<100 bytes)" "0" "$(_run_hook "$input")"

# 11. Write where actual size matches → exit 0
f="$TMPDIR/match2.txt"
content="$(printf 'B%.0s' $(seq 1 200))"
echo -n "$content" > "$f"
input="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"$content\"}}"
_assert_exit "pass Write where size matches" "0" "$(_run_hook "$input")"

# 12. Write where actual size is within 2x slack (just barely OK) → exit 0
f="$TMPDIR/slack.txt"
echo -n "$(printf 'C%.0s' $(seq 1 130))" > "$f"  # 130 bytes
content="$(printf 'C%.0s' $(seq 1 200))"  # 200 bytes claimed
input="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"$content\"}}"
_assert_exit "pass Write within 2x slack for CRLF/encoding diffs" "0" "$(_run_hook "$input")"

# ============================================================
echo "Group 3: Edit content-not-in-file detection"
# ============================================================

# 13. Edit on git-tracked file where new_string IS in file → exit 0
GITDIR="$TMPDIR/gitrepo"
mkdir -p "$GITDIR"
git -C "$GITDIR" init -q 2>/dev/null
git -C "$GITDIR" config user.email "test@test" 2>/dev/null
git -C "$GITDIR" config user.name "Test" 2>/dev/null
f="$GITDIR/edited.txt"
echo "new content here" > "$f"
git -C "$GITDIR" add . 2>/dev/null
git -C "$GITDIR" commit -q -m "initial" 2>/dev/null
input="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"old\",\"new_string\":\"new content here\"}}"
_assert_exit "pass Edit where new_string IS in file" "0" "$(_run_hook "$input")"

# 14. Edit on git-tracked file where new_string is NOT in file → exit 2
f="$GITDIR/missing.txt"
echo "totally different content" > "$f"
git -C "$GITDIR" add . 2>/dev/null
git -C "$GITDIR" commit -q -m "add" 2>/dev/null
input="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"diff\",\"new_string\":\"UNIQUE_STRING_NOT_IN_FILE_xyz123\"}}"
_assert_exit "detect Edit where new_string missing from file" "2" "$(_run_hook "$input")"

# 15. Stderr message references #61303 on Edit miss
err=$(_run_hook_stderr "$input")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$err" | grep -q "61303"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ Edit miss stderr references #61303"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("Edit miss stderr missing #61303")
    echo "  ✗ Edit miss stderr missing #61303"
fi

# 16. Edit where old_string == new_string (no-op) → exit 0
f="$GITDIR/noop.txt"
echo "noop content" > "$f"
git -C "$GITDIR" add . 2>/dev/null
git -C "$GITDIR" commit -q -m "noop" 2>/dev/null
input="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"noop\",\"new_string\":\"noop\"}}"
_assert_exit "skip Edit where old_string == new_string" "0" "$(_run_hook "$input")"

# 17. Edit on non-git file (Edit doesn't check disk for non-git) → exit 0
f="$TMPDIR/notgit.txt"
echo "non-git content" > "$f"
input="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"non\",\"new_string\":\"updated\"}}"
_assert_exit "skip Edit check on non-git file" "0" "$(_run_hook "$input")"

# 18. Edit with empty new_string → exit 0 (deletion, not insertion)
f="$GITDIR/empty-new.txt"
echo "to be cleared" > "$f"
git -C "$GITDIR" add . 2>/dev/null
git -C "$GITDIR" commit -q -m "clear" 2>/dev/null
input="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"to be cleared\",\"new_string\":\"\"}}"
_assert_exit "skip Edit with empty new_string (deletion)" "0" "$(_run_hook "$input")"

# ============================================================
echo "Group 4: Configuration env vars"
# ============================================================

# 19. Quiet mode: divergence still detected but exit 0
f="$TMPDIR/quiet-shortfall.txt"
echo -n "tiny" > "$f"
big_content="$(printf 'D%.0s' $(seq 1 200))"
input="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"$big_content\"}}"
result=$(CC_POST_EDIT_VERIFY_QUIET=1 CC_POST_EDIT_VERIFY_RECEIPT_DIR="$TMPDIR/receipts-quiet" bash -c "printf '%s' '$input' | '$HOOK'"; echo $?)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$result" == "0" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ quiet mode exits 0 on divergence"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("quiet mode: expected 0, got $result")
    echo "  ✗ quiet mode: expected 0, got $result"
fi

# 20. Quiet mode still writes divergence receipt
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$TMPDIR/receipts-quiet/post-edit-divergence.jsonl" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ quiet mode writes divergence receipt"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("quiet mode: receipt file not written")
    echo "  ✗ quiet mode: receipt file not written"
fi

# ============================================================
echo "Group 5: Receipt log behavior"
# ============================================================

# 21. Receipt records the file path, tool, kind, and size
TESTS_RUN=$((TESTS_RUN + 1))
receipt_content=$(cat "$TMPDIR/receipts-quiet/post-edit-divergence.jsonl" 2>/dev/null)
if echo "$receipt_content" | jq -e '.tool == "Write" and .kind == "size-shortfall" and .file_size' >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ receipt is well-formed JSONL with tool/kind/file_size fields"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("receipt JSONL malformed: $receipt_content")
    echo "  ✗ receipt JSONL malformed"
fi

# 22. Multiple divergences append (not overwrite)
input2="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\",\"content\":\"$big_content\"}}"
CC_POST_EDIT_VERIFY_QUIET=1 CC_POST_EDIT_VERIFY_RECEIPT_DIR="$TMPDIR/receipts-quiet" bash -c "printf '%s' '$input2' | '$HOOK'" >/dev/null
TESTS_RUN=$((TESTS_RUN + 1))
line_count=$(wc -l < "$TMPDIR/receipts-quiet/post-edit-divergence.jsonl" 2>/dev/null || echo 0)
if [[ "$line_count" -ge 2 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ receipt appends (not overwrites)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("receipt did not append (line count: $line_count)")
    echo "  ✗ receipt did not append (line count: $line_count)"
fi

# 23. ISO 8601 UTC timestamp in receipt
TESTS_RUN=$((TESTS_RUN + 1))
ts=$(jq -r '.ts' < "$TMPDIR/receipts-quiet/post-edit-divergence.jsonl" 2>/dev/null | head -1)
if [[ "$ts" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ receipt timestamp is ISO 8601 UTC ($ts)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("receipt timestamp malformed: $ts")
    echo "  ✗ receipt timestamp malformed: $ts"
fi

# 24. Audit query: count divergences per file
TESTS_RUN=$((TESTS_RUN + 1))
divergence_count=$(jq -r --arg f "$f" 'select(.file == $f) | .file' "$TMPDIR/receipts-quiet/post-edit-divergence.jsonl" 2>/dev/null | wc -l)
if [[ "$divergence_count" -ge 1 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ audit query returns divergences for file ($divergence_count records)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("audit query returned no records for file")
    echo "  ✗ audit query returned no records"
fi

# ============================================================
echo ""
echo "----------------------------------------"
echo "Total: $TESTS_RUN tests, $TESTS_PASSED passed, $TESTS_FAILED failed"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
echo "All tests passed."
