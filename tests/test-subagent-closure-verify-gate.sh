#!/bin/bash
# tests/test-subagent-closure-verify-gate.sh

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/../examples/subagent-closure-verify-gate.sh"

if [ ! -x "$HOOK" ]; then
    echo "FAIL: hook not executable: $HOOK"
    exit 1
fi

PASS=0
FAIL=0

# Helper to run one case and compare exit + stderr substring.
run_case() {
    local desc="$1"
    local expected_exit="$2"
    local mode="$3"
    local expected_stderr="$4"
    local input="$5"

    local stderr_file actual_exit=0
    stderr_file=$(mktemp)

    local env_args=()
    if [ "$mode" = "strict" ]; then
        env_args+=("CC_SUBAGENT_CLOSURE_MODE=strict")
    fi

    if [ ${#env_args[@]} -gt 0 ]; then
        printf '%s' "$input" | env "${env_args[@]}" bash "$HOOK" >/dev/null 2>"$stderr_file" || actual_exit=$?
    else
        printf '%s' "$input" | bash "$HOOK" >/dev/null 2>"$stderr_file" || actual_exit=$?
    fi

    local ok=1
    if [ "$actual_exit" -ne "$expected_exit" ]; then
        ok=0
    fi
    if [ -n "$expected_stderr" ]; then
        if ! grep -Fq "$expected_stderr" "$stderr_file"; then
            ok=0
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        if [ -n "$expected_stderr" ]; then
            echo "  expected stderr substring: $expected_stderr"
        fi
        echo "  stderr was:"
        sed 's/^/    /' "$stderr_file"
        FAIL=$((FAIL + 1))
    fi

    rm -f "$stderr_file"
}

# Convenience helpers to build Stop-event inputs.
stop_with_text() {
    local text="$1"
    jq -nc --arg t "$text" '{transcript:[{content:$t}]}'
}

stop_with_text_and_agent() {
    local text="$1"
    jq -nc --arg t "$text" \
        '{transcript:[{content:$t, tool_calls:[{name:"Agent", input:{prompt:"do thing"}}]}]}'
}

stop_with_text_and_bash() {
    local text="$1"
    jq -nc --arg t "$text" \
        '{transcript:[{content:$t, tool_calls:[{name:"Bash", input:{command:"ls"}}]}]}'
}

echo "=== Group 1: input handling ==="

run_case "1.1 empty stdin → silent exit 0" \
    0 advisory "" ""

run_case "1.2 garbage stdin → silent exit 0" \
    0 advisory "" "not json"

run_case "1.3 empty assistant text → silent exit 0" \
    0 advisory "" "$(jq -nc '{transcript:[{content:""}]}')"

echo "=== Group 2: disable switch ==="

DISABLE_PAYLOAD=$(stop_with_text "all sub-agents have completed and returned summaries")
DISABLE_EXIT=0
printf '%s' "$DISABLE_PAYLOAD" | \
    CC_SUBAGENT_CLOSURE_DISABLE=1 \
    CC_SUBAGENT_CLOSURE_MODE=strict \
    bash "$HOOK" >/dev/null 2>/dev/null || DISABLE_EXIT=$?
if [ "$DISABLE_EXIT" -eq 0 ]; then
    echo "PASS: 2.1 DISABLE=1 bypasses gate even in strict mode"
    PASS=$((PASS + 1))
else
    echo "FAIL: 2.1 DISABLE=1 should exit 0 (got $DISABLE_EXIT)"
    FAIL=$((FAIL + 1))
fi

echo "=== Group 3: non-matching turns (silent) ==="

run_case "3.1 turn with no sub-agent narration exits 0" \
    0 advisory "" \
    "$(stop_with_text "I read the file and edited line 5. Anything else?")"

run_case "3.2 turn about sub-agents but not completion exits 0" \
    0 advisory "" \
    "$(stop_with_text "Sub-agents in Claude Code are spawned via the Agent tool.")"

run_case "3.3 turn with 'done' (main-agent closure) exits 0" \
    0 advisory "" \
    "$(stop_with_text "Done. The file is updated.")"

echo "=== Group 4: closure narration WITH Agent call (grounded, silent) ==="

run_case "4.1 'the sub-agent completed' + Agent call → silent" \
    0 advisory "" \
    "$(stop_with_text_and_agent "The sub-agent completed and returned a summary.")"

run_case "4.2 'all sub-agents have returned' + Agent call → silent" \
    0 advisory "" \
    "$(stop_with_text_and_agent "All sub-agents have returned with their findings.")"

run_case "4.3 'I dispatched 3 sub-agents' + Agent call → silent" \
    0 advisory "" \
    "$(stop_with_text_and_agent "I dispatched 3 sub-agents and they all reported.")"

echo "=== Group 5: closure narration WITHOUT Agent call (advisory) ==="

run_case "5.1 'the sub-agent completed' alone → advisory exit 0" \
    0 advisory "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text "The sub-agent completed the analysis successfully.")"

run_case "5.2 'all sub-agents have returned' alone → advisory" \
    0 advisory "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text "All sub-agents have returned with their findings.")"

run_case "5.3 'I dispatched 5 sub-agents' alone → advisory" \
    0 advisory "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text "I dispatched 5 sub-agents and they all reported back.")"

run_case "5.4 'both sub-agents reported' alone → advisory" \
    0 advisory "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text "Both sub-agents reported their results clearly.")"

run_case "5.5 'the parallel work is complete' alone → advisory" \
    0 advisory "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text "The parallel work is complete and integrated.")"

run_case "5.6 advisory references #61167" \
    0 advisory "#61167" \
    "$(stop_with_text "The sub-agent completed.")"

run_case "5.7 advisory mentions PR #250 sibling" \
    0 advisory "PR #250" \
    "$(stop_with_text "All sub-agents have completed.")"

echo "=== Group 6: narration WITH only non-Agent tool calls (still advisory) ==="

run_case "6.1 closure narration + Bash call (no Agent) → advisory" \
    0 advisory "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text_and_bash "The sub-agent completed the analysis.")"

echo "=== Group 7: strict mode ==="

run_case "7.1 strict + narration without Agent → exit 2" \
    2 strict "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE" \
    "$(stop_with_text "The sub-agent completed the analysis.")"

run_case "7.2 strict + narration WITH Agent → exit 0" \
    0 strict "" \
    "$(stop_with_text_and_agent "The sub-agent completed the analysis.")"

run_case "7.3 strict + no narration → exit 0" \
    0 strict "" \
    "$(stop_with_text "Done. File updated.")"

echo ""
echo "============================================================"
echo "RESULTS: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
echo "============================================================"

[ "$FAIL" -eq 0 ]
