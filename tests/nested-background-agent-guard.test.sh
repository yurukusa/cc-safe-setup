#!/bin/bash
# Tests for nested-background-agent-guard.sh
#
# The guard refuses ONE shape: a background agent dispatched from inside a sub-agent
# (issue #73829). Everything else must pass. Half of these cases exist to prove the
# hook is not simply blocking everything — a guard that blocks all dispatches would
# also stop the runaway, and would be useless.
HOOK="$(dirname "$0")/../examples/nested-background-agent-guard.sh"
PASS=0; FAIL=0

run_test() {
    local desc="$1" input="$2" expect_code="$3"
    shift 3
    result_code=$(printf '%s' "$input" | env "$@" bash "$HOOK" >/dev/null 2>&1; echo $?)
    if [ "$result_code" = "$expect_code" ]; then
        echo "PASS: $desc"
        PASS=$((PASS+1))
    else
        echo "FAIL: $desc (expected $expect_code, got $result_code)"
        FAIL=$((FAIL+1))
    fi
}

BG_AGENT='{"tool_name":"Task","tool_input":{"run_in_background":true,"prompt":"research"}}'
FG_AGENT='{"tool_name":"Task","tool_input":{"run_in_background":false,"prompt":"research"}}'
NO_FLAG='{"tool_name":"Task","tool_input":{"prompt":"research"}}'
BG_BASH='{"tool_name":"Bash","tool_input":{"run_in_background":true,"command":"npm run dev"}}'

echo "--- the one shape that must be blocked ---"
run_test "background agent from inside a sub-agent is blocked" \
    "$BG_AGENT" 2 CLAUDE_CODE_CHILD_SESSION=1
run_test "same via the Agent tool name" \
    '{"tool_name":"Agent","tool_input":{"run_in_background":true}}' 2 CLAUDE_CODE_CHILD_SESSION=1
run_test "same via SendMessage" \
    '{"tool_name":"SendMessage","tool_input":{"run_in_background":true}}' 2 CLAUDE_CODE_CHILD_SESSION=1

echo "--- controls: these must all pass (or the guard is just blocking everything) ---"
run_test "background agent from the TOP level is allowed" \
    "$BG_AGENT" 0 CLAUDE_CODE_CHILD_SESSION=
run_test "FOREGROUND agent inside a sub-agent is allowed" \
    "$FG_AGENT" 0 CLAUDE_CODE_CHILD_SESSION=1
run_test "agent with no run_in_background key is allowed" \
    "$NO_FLAG" 0 CLAUDE_CODE_CHILD_SESSION=1
run_test "a background Bash launch is not this hook's business" \
    "$BG_BASH" 0 CLAUDE_CODE_CHILD_SESSION=1
run_test "unrelated tool is untouched" \
    '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' 0 CLAUDE_CODE_CHILD_SESSION=1
run_test "opt-out disables the guard" \
    "$BG_AGENT" 0 CLAUDE_CODE_CHILD_SESSION=1 CC_NESTED_BG_AGENT_GUARD_DISABLE=1

echo "--- malformed input must not crash or block ---"
run_test "empty input" "" 0 CLAUDE_CODE_CHILD_SESSION=1
run_test "not JSON" "not json at all" 0 CLAUDE_CODE_CHILD_SESSION=1
run_test "JSON without tool_name" '{"tool_input":{"run_in_background":true}}' 0 CLAUDE_CODE_CHILD_SESSION=1

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
