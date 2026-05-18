#!/bin/bash
# Tests for fabricated-command-detector.sh
# Run: bash tests/test-fabricated-command-detector.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/fabricated-command-detector.sh"
PASS=0 FAIL=0

# Helper: build a synthetic jsonl transcript with one assistant message and
# zero-or-more Bash tool calls, then run the hook against it.
# Args:
#   $1 — description
#   $2 — expected exit code
#   $3 — assistant response text (markdown, may contain backtick tokens)
#   $4 — newline-separated list of Bash commands actually invoked (may be empty)
#   $5 — env vars to set for this run (optional)
run_test() {
    local desc="$1" expected_exit="$2" response="$3" invoked="$4" envvars="${5:-}"
    local tmpdir transcript actual_exit input
    tmpdir=$(mktemp -d)
    transcript="${tmpdir}/transcript.jsonl"

    # Build invoked tool-use events (one per command)
    if [ -n "$invoked" ]; then
        while IFS= read -r cmd; do
            [ -z "$cmd" ] && continue
            jq -nc --arg cmd "$cmd" '{
                "role": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {"type": "tool_use", "name": "Bash", "input": {"command": $cmd}}
                    ]
                }
            }' >> "$transcript"
        done <<< "$invoked"
    fi

    # Build the final assistant message
    jq -nc --arg text "$response" '{
        "role": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {"type": "text", "text": $text}
            ]
        }
    }' >> "$transcript"

    input=$(jq -nc --arg t "$transcript" '{"transcript_path": $t}')

    if [ -n "$envvars" ]; then
        actual_exit=$(echo "$input" | env $envvars bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
    else
        echo "$input" | bash "$HOOK" >/dev/null 2>/dev/null
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

# Helper for stderr-content checks: run the hook and grep stderr for a substring.
expect_stderr_contains() {
    local desc="$1" response="$2" invoked="$3" expect_substring="$4" envvars="${5:-}"
    local tmpdir transcript stderr_out input
    tmpdir=$(mktemp -d)
    transcript="${tmpdir}/transcript.jsonl"

    if [ -n "$invoked" ]; then
        while IFS= read -r cmd; do
            [ -z "$cmd" ] && continue
            jq -nc --arg cmd "$cmd" '{
                "role": "assistant",
                "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Bash", "input": {"command": $cmd}}]}
            }' >> "$transcript"
        done <<< "$invoked"
    fi

    jq -nc --arg text "$response" '{
        "role": "assistant",
        "message": {"role": "assistant", "content": [{"type": "text", "text": $text}]}
    }' >> "$transcript"

    input=$(jq -nc --arg t "$transcript" '{"transcript_path": $t}')

    if [ -n "$envvars" ]; then
        stderr_out=$(echo "$input" | env $envvars bash "$HOOK" 2>&1 >/dev/null)
    else
        stderr_out=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null)
    fi

    rm -rf "$tmpdir"

    if echo "$stderr_out" | grep -q -- "$expect_substring"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (stderr did not contain '$expect_substring')"
        echo "       got: $stderr_out"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing fabricated-command-detector.sh"
echo "======================================"

# --- BASELINE: empty / missing inputs do not crash ---
run_test "empty input exits 0" 0 "" "" ""
run_test "missing transcript path exits 0" 0 "" "" ""

# --- CORE: fabrication detection ---
# Case 1: response references ./exploit, operator actually ran ./chage_pwn root
run_test "fabricated ./exploit not invoked → advisory exit 0" \
    0 \
    "I ran the reproduction: \`./exploit\` and observed the failure." \
    "./chage_pwn root" \
    ""

# Case 2: response uses the actual invoked command → no warning
run_test "verified ./chage_pwn appears → exit 0 silently" \
    0 \
    "I ran \`./chage_pwn root\` and observed the failure." \
    "./chage_pwn root" \
    ""

# Case 3: response has no command-shaped tokens → exit 0
run_test "no command tokens in response → exit 0" \
    0 \
    "The reproduction succeeded with expected output." \
    "./chage_pwn root" \
    ""

# Case 4: response has multiple command tokens, mix of verified and fabricated
run_test "mixed verified/fabricated → exit 0 advisory" \
    0 \
    "First I ran \`./chage_pwn root\`, then \`./exploit\` to confirm." \
    "./chage_pwn root" \
    ""

# Case 5: git fabrication
run_test "fabricated git command not invoked → exit 0 advisory" \
    0 \
    "I ran \`git rebase --onto main\` to update the branch." \
    "git status" \
    ""

# Case 6: git verified
run_test "verified git command → exit 0 silently" \
    0 \
    "I ran \`git status\` to check the tree." \
    "git status" \
    ""

# --- BLOCKING MODE ---
run_test "BLOCK=1 with fabrication exits 2" \
    2 \
    "I ran \`./fake_cmd\` to verify." \
    "./real_cmd arg" \
    "CC_FABRICATED_CMD_BLOCK=1"

run_test "BLOCK=1 with verified command exits 0" \
    0 \
    "I ran \`./real_cmd arg\` to verify." \
    "./real_cmd arg" \
    "CC_FABRICATED_CMD_BLOCK=1"

# --- DISABLE FLAG ---
run_test "DISABLE=1 short-circuits with fabrication → exit 0" \
    0 \
    "I ran \`./fake_cmd\` to verify." \
    "./real_cmd arg" \
    "CC_FABRICATED_CMD_DISABLE=1"

# --- ALLOW PATTERN ---
run_test "ALLOW filter suppresses example commands" \
    0 \
    "Run \`./example.sh\` to set up." \
    "" \
    "CC_FABRICATED_CMD_ALLOW=^./example"

# --- STDERR CONTENT CHECKS ---
expect_stderr_contains \
    "stderr names the unverified token" \
    "I ran \`./exploit\` for the reproduction." \
    "./chage_pwn root" \
    "./exploit" \
    ""

expect_stderr_contains \
    "stderr cites issue #60340" \
    "I ran \`./exploit\` for the reproduction." \
    "./chage_pwn root" \
    "#60340" \
    ""

expect_stderr_contains \
    "stderr says fabricated-command-detector header" \
    "I ran \`./exploit\` for the reproduction." \
    "./chage_pwn root" \
    "fabricated-command-detector" \
    ""

# --- LANGUAGE / VOCAB COVERAGE ---
run_test "bash <script> fabrication detected" \
    0 \
    "Run \`bash deploy.sh\` to ship." \
    "" \
    ""

run_test "npm run fabrication detected" \
    0 \
    "Run \`npm run release\` to publish." \
    "" \
    ""

run_test "python <script> fabrication detected" \
    0 \
    "Run \`python build.py\` to compile." \
    "" \
    ""

run_test "node <script> fabrication detected" \
    0 \
    "Run \`node migrate.js\` to migrate." \
    "" \
    ""

# --- EDGE CASES ---
run_test "command in fenced code block (multi-line) is NOT scanned by inline-only regex" \
    0 \
    "Run this:\n\`\`\`\n./fake\n\`\`\`\nDone." \
    "" \
    ""

run_test "backtick-fenced non-command text not flagged as fabrication" \
    0 \
    "Use the \`foo\` variable and \`bar\` setting." \
    "" \
    ""

run_test "substring match: invoked command contains the token" \
    0 \
    "I ran \`git status\` to check." \
    "git status --short" \
    ""

# --- ENVIRONMENT / CAP ---
run_test "MAX=1 with two fabrications still scans (advisory)" \
    0 \
    "Run \`./fake1\` and \`./fake2\` next." \
    "" \
    "CC_FABRICATED_CMD_MAX=1"

# --- LARGE INPUTS ---
run_test "response with no inline backticks → exit 0" \
    0 \
    "Plain text with no backtick spans at all." \
    "" \
    ""

run_test "empty Bash history with one fabrication → exit 0 advisory" \
    0 \
    "I ran \`./script.sh\` to set up." \
    "" \
    ""

run_test "TRANSCRIPT missing file → exit 0" \
    0 \
    "" \
    "" \
    ""

# --- INVOKED-CONFIRMATION: same prefix not enough ---
run_test "prefix-only match does not count as invoked" \
    0 \
    "I ran \`./run_tests --all\` to verify." \
    "./run_tests" \
    ""

# This is correctly an advisory case — `./run_tests --all` is a different
# command from `./run_tests`. The substring-direction guarantees that the
# response's token appears IN an invoked command, not vice versa.
# If the operator invokes `./run_tests`, but the response says `./run_tests --all`,
# the response's claim of running `--all` was not actually invoked.

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
