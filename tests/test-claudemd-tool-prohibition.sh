#!/bin/bash
# Tests for claudemd-tool-prohibition.sh
# Run: bash tests/test-claudemd-tool-prohibition.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/claudemd-tool-prohibition.sh"
PASS=0 FAIL=0

# Helper: run hook with a temp CLAUDE.md
# Args:
#   $1 — description
#   $2 — expected exit code
#   $3 — tool name (sent in tool_name field)
#   $4 — CLAUDE.md content
#   $5 — env vars (optional)
run_test() {
    local desc="$1" expected_exit="$2" tool="$3" claudemd_content="$4" envvars="${5:-}"
    local tmpdir claudemd actual_exit input
    tmpdir=$(mktemp -d)
    claudemd="${tmpdir}/CLAUDE.md"
    printf '%s' "$claudemd_content" > "$claudemd"

    input=$(jq -nc --arg name "$tool" '{"tool_name": $name, "tool_input": {}}')

    if [ -n "$envvars" ]; then
        actual_exit=$(echo "$input" | env CC_CLAUDEMD_PATH="$claudemd" $envvars bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
    else
        echo "$input" | CC_CLAUDEMD_PATH="$claudemd" bash "$HOOK" >/dev/null 2>/dev/null
        actual_exit=$?
    fi

    rm -rf "$tmpdir"

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# Stderr-content check
expect_stderr_contains() {
    local desc="$1" tool="$2" claudemd_content="$3" expect="$4" envvars="${5:-}"
    local tmpdir claudemd stderr_out input
    tmpdir=$(mktemp -d)
    claudemd="${tmpdir}/CLAUDE.md"
    printf '%s' "$claudemd_content" > "$claudemd"

    input=$(jq -nc --arg name "$tool" '{"tool_name": $name, "tool_input": {}}')

    if [ -n "$envvars" ]; then
        stderr_out=$(echo "$input" | env CC_CLAUDEMD_PATH="$claudemd" $envvars bash "$HOOK" 2>&1 >/dev/null)
    else
        stderr_out=$(echo "$input" | CC_CLAUDEMD_PATH="$claudemd" bash "$HOOK" 2>&1 >/dev/null)
    fi

    rm -rf "$tmpdir"

    if echo "$stderr_out" | grep -q -- "$expect"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (stderr missing '$expect')"
        echo "       got: $stderr_out"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing claudemd-tool-prohibition.sh"
echo "===================================="

# --- BASELINE: empty / safe cases ---
run_test "empty input exits 0" 0 "" ""
run_test "no CLAUDE.md → exit 0" 0 "TaskCreate" ""
run_test "CLAUDE.md without prohibitions → exit 0" 0 "TaskCreate" "# project notes\nuse anything you like"

# --- PROSE PROHIBITIONS ---
run_test "Do NOT use TaskCreate blocks TaskCreate" \
    2 "TaskCreate" \
    "Do NOT use \`TaskCreate\` for session-local work."

run_test "Do not use TaskCreate (lowercase) blocks TaskCreate" \
    2 "TaskCreate" \
    "Do not use \`TaskCreate\` here."

run_test "never use TaskUpdate blocks TaskUpdate" \
    2 "TaskUpdate" \
    "never use \`TaskUpdate\` in this project."

run_test "do not call TaskList blocks TaskList" \
    2 "TaskList" \
    "Please do not call \`TaskList\` ever."

# --- JAPANESE PROHIBITIONS ---
run_test "Japanese: TaskCreate を使うな blocks TaskCreate" \
    2 "TaskCreate" \
    "\`TaskCreate\` を使うな。"

run_test "Japanese: TaskList の使用は禁止 blocks TaskList" \
    2 "TaskList" \
    "\`TaskList\` の使用は禁止。"

run_test "Japanese: 禁止する道具 header with list blocks TaskCreate" \
    2 "TaskCreate" \
    "## 禁止する道具

- \`TaskCreate\`
- \`TaskList\`"

# --- LIST-UNDER-HEADER FORMAT ---
run_test "Forbidden Tools header with list blocks TaskCreate" \
    2 "TaskCreate" \
    "# Project Rules

## Forbidden Tools

- \`TaskCreate\`
- \`TaskList\`
- \`TaskUpdate\`

## Other Notes
Anything else is fine."

run_test "Prohibited Tools header with list blocks TaskUpdate" \
    2 "TaskUpdate" \
    "## Prohibited Tools

- \`TaskCreate\`
- \`TaskUpdate\`"

# --- NEGATIVE CASES: tool NOT in prohibition list ---
run_test "Other tool not in prohibition → exit 0" \
    0 "Bash" \
    "Do NOT use \`TaskCreate\` for session-local work."

run_test "Prohibitions for TaskList only → TaskCreate allowed" \
    0 "TaskCreate" \
    "Do NOT use \`TaskList\` only."

# --- ADVISORY MODE ---
run_test "WARN=1 advisory mode exits 0" \
    0 "TaskCreate" \
    "Do NOT use \`TaskCreate\`." \
    "CC_TOOL_PROHIBITION_WARN=1"

# --- DISABLE FLAG ---
run_test "DISABLE=1 short-circuits regardless" \
    0 "TaskCreate" \
    "Do NOT use \`TaskCreate\`." \
    "CC_TOOL_PROHIBITION_DISABLE=1"

# --- STDERR CONTENT ---
expect_stderr_contains \
    "BLOCKED message names the tool" \
    "TaskCreate" \
    "Do NOT use \`TaskCreate\`." \
    "TaskCreate"

expect_stderr_contains \
    "BLOCKED message cites issue #60323" \
    "TaskCreate" \
    "Do NOT use \`TaskCreate\`." \
    "#60323"

expect_stderr_contains \
    "WARN mode message says advisory" \
    "TaskCreate" \
    "Do NOT use \`TaskCreate\`." \
    "advisory" \
    "CC_TOOL_PROHIBITION_WARN=1"

# --- EDGE CASES ---
run_test "header without backticks in list items → not parsed → exit 0" \
    0 "TaskCreate" \
    "## Forbidden Tools

- TaskCreate (no backticks)
- TaskList"

run_test "tool name without backticks in prose → not parsed → exit 0" \
    0 "TaskCreate" \
    "Do NOT use TaskCreate (no backticks)."

run_test "case sensitivity: lowercase tool not matched to uppercase prohibition" \
    0 "taskcreate" \
    "Do NOT use \`TaskCreate\`."

run_test "case sensitivity: uppercase tool matches exact case prohibition" \
    2 "TaskCreate" \
    "Do NOT use \`TaskCreate\`."

# --- COMBINED FORMATS ---
run_test "both prose and header list work together" \
    2 "TaskCreate" \
    "## Forbidden Tools
- \`TaskList\`

Also do not call \`TaskCreate\` separately."

run_test "second tool only in header" \
    2 "TaskList" \
    "## Forbidden Tools
- \`TaskList\`

Also do not call \`TaskCreate\` separately."

# --- REAL-WORLD: #60323 reporter's CLAUDE.md ---
REAL_CLAUDEMD='## Task System Isolation (MANDATORY)

`TaskCreate`/`TaskList` stores tasks globally — every session sees every task, causing cross-talk.

- Do NOT use `TaskCreate` for session-local work. Track progress via `## Progress` blocks in responses.
- `TaskCreate` only for intentionally shared cross-session coordination items.'

run_test "real-world #60323 CLAUDE.md blocks TaskCreate" \
    2 "TaskCreate" "$REAL_CLAUDEMD"

# Note: The reporter's CLAUDE.md says TaskCreate is blocked but TaskList is
# only mentioned descriptively (not via "do not use"). The hook is strict —
# it only blocks tools that match prohibition patterns, not tools merely
# mentioned in context. This is the correct behaviour (precision matters
# in this rule space).
run_test "real-world: TaskList is only described, not prohibited → exit 0" \
    0 "TaskList" "$REAL_CLAUDEMD"

# --- TOOLS NOT MATCHED ---
run_test "Bash always allowed when only TaskCreate prohibited" \
    0 "Bash" \
    "Do NOT use \`TaskCreate\`."

run_test "Read always allowed when only TaskList prohibited" \
    0 "Read" \
    "Do NOT use \`TaskList\`."

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
