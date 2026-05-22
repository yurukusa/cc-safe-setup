#!/bin/bash
# tests/test-dispatch-liveness-watchdog.sh
# Standalone test suite for examples/dispatch-liveness-watchdog.sh

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/../examples/dispatch-liveness-watchdog.sh"

if [ ! -x "$HOOK" ]; then
    echo "FAIL: hook not executable: $HOOK"
    exit 1
fi

PASS=0
FAIL=0

# Per-test isolation: each test gets its own state dir.
STATE_BASE=$(mktemp -d)
trap 'rm -rf "$STATE_BASE"' EXIT

# Helper: invoke hook with given input JSON, return (exit_code, stderr).
# Args:
#   $1  = description
#   $2  = expected exit code
#   $3  = state dir for this test
#   $4  = threshold seconds
#   $5  = mode (advisory or strict)
#   $6  = expected stderr substring ("" to skip)
#   $7  = input JSON
run_case() {
    local desc="$1"
    local expected_exit="$2"
    local state_dir="$3"
    local threshold="$4"
    local mode="$5"
    local expected_stderr="$6"
    local input="$7"

    local stderr_file actual_exit=0
    stderr_file=$(mktemp)

    local env_args=(
        "CC_DISPATCH_WATCHDOG_STATE_DIR=$state_dir"
        "CC_DISPATCH_WATCHDOG_THRESHOLD_SEC=$threshold"
    )
    if [ "$mode" = "strict" ]; then
        env_args+=("CC_DISPATCH_WATCHDOG_MODE=strict")
    fi

    printf '%s' "$input" | env "${env_args[@]}" bash "$HOOK" >/dev/null 2>"$stderr_file" || actual_exit=$?

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

# Convenience: build a PreToolUse Agent input.
pre_agent() {
    local session="$1" subagent="$2" desc="$3"
    jq -nc --arg s "$session" --arg t "$subagent" --arg d "$desc" \
        '{hook_event_name: "PreToolUse", tool_name: "Agent",
          session_id: $s,
          tool_input: {subagent_type: $t, description: $d, prompt: $d}}'
}

# Convenience: build a PostToolUse Agent input.
post_agent() {
    local session="$1"
    jq -nc --arg s "$session" \
        '{hook_event_name: "PostToolUse", tool_name: "Agent",
          session_id: $s,
          tool_response: {result: "done"}}'
}

# Convenience: build a UserPromptSubmit input.
prompt_submit() {
    local session="$1" text="$2"
    jq -nc --arg s "$session" --arg t "$text" \
        '{hook_event_name: "UserPromptSubmit", session_id: $s, prompt: $t}'
}

echo "=== Group 1: basic dispatch lifecycle ==="

S1="$STATE_BASE/s1"
run_case "1.1 PreToolUse Agent creates a state file" \
    0 "$S1" 1800 advisory "" \
    "$(pre_agent "sess-1" "general-purpose" "do thing X")"

# Verify state file was created.
if [ "$(ls -1 "$S1/sess-1" 2>/dev/null | wc -l)" -eq 1 ]; then
    echo "PASS: 1.1b state file present after PreToolUse"
    PASS=$((PASS + 1))
else
    echo "FAIL: 1.1b expected 1 state file, found $(ls -1 "$S1/sess-1" 2>/dev/null | wc -l)"
    FAIL=$((FAIL + 1))
fi

run_case "1.2 PostToolUse Agent removes a state file" \
    0 "$S1" 1800 advisory "" \
    "$(post_agent "sess-1")"

if [ "$(ls -1 "$S1/sess-1" 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "PASS: 1.2b state directory empty after PostToolUse"
    PASS=$((PASS + 1))
else
    echo "FAIL: 1.2b expected 0 state files, found $(ls -1 "$S1/sess-1" 2>/dev/null | wc -l)"
    FAIL=$((FAIL + 1))
fi

echo "=== Group 2: non-Agent tools are ignored ==="

S2="$STATE_BASE/s2"
NON_AGENT=$(jq -nc '{hook_event_name: "PreToolUse", tool_name: "Bash",
    session_id: "sess-2", tool_input: {command: "echo hi"}}')
run_case "2.1 PreToolUse with non-Agent tool does nothing" \
    0 "$S2" 1800 advisory "" \
    "$NON_AGENT"

if [ ! -d "$S2/sess-2" ] || [ "$(ls -1 "$S2/sess-2" 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "PASS: 2.1b no state file for non-Agent tool"
    PASS=$((PASS + 1))
else
    echo "FAIL: 2.1b state file was created for non-Agent tool"
    FAIL=$((FAIL + 1))
fi

echo "=== Group 3: parallel dispatches ==="

S3="$STATE_BASE/s3"
run_case "3.1 first Agent dispatch" 0 "$S3" 1800 advisory "" \
    "$(pre_agent "sess-3" "general-purpose" "task A")"

# Sleep 1s to make sure the second dispatch gets a different timestamp prefix
# (the 6-byte random suffix would disambiguate even at the same second, but
# this makes the FIFO test below deterministic).
sleep 1

run_case "3.2 second Agent dispatch" 0 "$S3" 1800 advisory "" \
    "$(pre_agent "sess-3" "explore" "task B")"

if [ "$(ls -1 "$S3/sess-3" 2>/dev/null | wc -l)" -eq 2 ]; then
    echo "PASS: 3.2b two state files present"
    PASS=$((PASS + 1))
else
    echo "FAIL: 3.2b expected 2 state files, found $(ls -1 "$S3/sess-3" 2>/dev/null | wc -l)"
    FAIL=$((FAIL + 1))
fi

# After one PostToolUse, oldest should be removed (task A).
run_case "3.3 one PostToolUse" 0 "$S3" 1800 advisory "" \
    "$(post_agent "sess-3")"

if [ "$(ls -1 "$S3/sess-3" 2>/dev/null | wc -l)" -eq 1 ]; then
    echo "PASS: 3.3b one state file remaining after PostToolUse"
    PASS=$((PASS + 1))
else
    echo "FAIL: 3.3b expected 1 state file, found $(ls -1 "$S3/sess-3" 2>/dev/null | wc -l)"
    FAIL=$((FAIL + 1))
fi

# Verify the REMAINING file is task B's (more recent).
REMAINING=$(ls -1 "$S3/sess-3" 2>/dev/null | head -1)
if [ -n "$REMAINING" ] && grep -q "task B" "$S3/sess-3/$REMAINING" 2>/dev/null; then
    echo "PASS: 3.3c FIFO retired task A, kept task B"
    PASS=$((PASS + 1))
else
    echo "FAIL: 3.3c FIFO removal did not keep the newer dispatch"
    FAIL=$((FAIL + 1))
fi

echo "=== Group 4: UserPromptSubmit advisory ==="

S4="$STATE_BASE/s4"
mkdir -p "$S4/sess-4"
# Manufacture a stale dispatch: write a state file with a past timestamp.
OLD_TS=$(( $(date +%s) - 3600 ))  # 1 hour ago
echo "general-purpose | this dispatch hung for over an hour" > "$S4/sess-4/${OLD_TS}-deadbeef"

run_case "4.1 prompt submit with stale dispatch → advisory exit 0" \
    0 "$S4" 1800 advisory "STALE SUB-AGENT DISPATCH" \
    "$(prompt_submit "sess-4" "what's next")"

run_case "4.2 advisory mentions the dispatch summary" \
    0 "$S4" 1800 advisory "this dispatch hung for over an hour" \
    "$(prompt_submit "sess-4" "what's next")"

run_case "4.3 advisory mentions wall-clock elapsed (60m)" \
    0 "$S4" 1800 advisory "60m" \
    "$(prompt_submit "sess-4" "what's next")"

run_case "4.4 advisory references #61405" \
    0 "$S4" 1800 advisory "#61405" \
    "$(prompt_submit "sess-4" "what's next")"

# Strict mode → exit 2.
run_case "4.5 strict mode + stale dispatch → exit 2" \
    2 "$S4" 1800 strict "STALE SUB-AGENT DISPATCH" \
    "$(prompt_submit "sess-4" "what's next")"

echo "=== Group 5: UserPromptSubmit silent paths ==="

S5="$STATE_BASE/s5"
# No state dir yet.
run_case "5.1 prompt submit with no state dir → silent exit 0" \
    0 "$S5" 1800 advisory "" \
    "$(prompt_submit "sess-5" "what's next")"

# Empty state dir.
mkdir -p "$S5/sess-5"
run_case "5.2 prompt submit with empty state dir → silent" \
    0 "$S5" 1800 advisory "" \
    "$(prompt_submit "sess-5" "what's next")"

# Fresh dispatch (not yet stale).
FRESH_TS=$(date +%s)
echo "general-purpose | just started" > "$S5/sess-5/${FRESH_TS}-cafebabe"
run_case "5.3 prompt submit with fresh dispatch (below threshold) → silent" \
    0 "$S5" 1800 advisory "" \
    "$(prompt_submit "sess-5" "what's next")"

# Strict mode + below threshold → still exit 0.
run_case "5.4 strict mode + below threshold → exit 0" \
    0 "$S5" 1800 strict "" \
    "$(prompt_submit "sess-5" "what's next")"

echo "=== Group 6: threshold configuration ==="

S6="$STATE_BASE/s6"
mkdir -p "$S6/sess-6"
# 100-second-old dispatch.
TS=$(( $(date +%s) - 100 ))
echo "general-purpose | 100s old dispatch" > "$S6/sess-6/${TS}-feedface"

run_case "6.1 100s old + 60s threshold → advisory fires" \
    0 "$S6" 60 advisory "STALE SUB-AGENT DISPATCH" \
    "$(prompt_submit "sess-6" "ping")"

run_case "6.2 100s old + 200s threshold → silent" \
    0 "$S6" 200 advisory "" \
    "$(prompt_submit "sess-6" "ping")"

echo "=== Group 7: disable switch ==="

S7="$STATE_BASE/s7"
mkdir -p "$S7/sess-7"
TS=$(( $(date +%s) - 3600 ))
echo "general-purpose | hung" > "$S7/sess-7/${TS}-1234abcd"

DISABLE_EXIT=0
printf '%s' "$(prompt_submit "sess-7" "ping")" | \
    CC_DISPATCH_WATCHDOG_STATE_DIR="$S7" \
    CC_DISPATCH_WATCHDOG_THRESHOLD_SEC=60 \
    CC_DISPATCH_WATCHDOG_DISABLE=1 \
    CC_DISPATCH_WATCHDOG_MODE=strict \
    bash "$HOOK" >/dev/null 2>/dev/null || DISABLE_EXIT=$?
if [ "$DISABLE_EXIT" -eq 0 ]; then
    echo "PASS: 7.1 DISABLE=1 bypasses watchdog even in strict mode"
    PASS=$((PASS + 1))
else
    echo "FAIL: 7.1 DISABLE=1 should exit 0 (got $DISABLE_EXIT)"
    FAIL=$((FAIL + 1))
fi

echo "=== Group 8: input handling ==="

run_case "8.1 empty stdin → silent exit 0" \
    0 "$STATE_BASE/s8" 1800 advisory "" ""

run_case "8.2 garbage stdin → silent exit 0" \
    0 "$STATE_BASE/s8" 1800 advisory "" \
    "this is not json at all"

# Session ID containing path separators should be sanitized.
WEIRD_SESSION=$(jq -nc \
    '{hook_event_name: "PreToolUse", tool_name: "Agent",
      session_id: "../../etc/passwd",
      tool_input: {subagent_type: "x", description: "y"}}')
run_case "8.3 path-traversal session id is sanitized" \
    0 "$STATE_BASE/s8b" 1800 advisory "" \
    "$WEIRD_SESSION"
# Verify no escape happened: the state dir under s8b should contain only
# a sanitized session directory (no /etc/passwd or parent escape).
if [ ! -e "$STATE_BASE/s8b/../../etc/passwd" ] && \
   [ "$(ls -1 "$STATE_BASE/s8b" 2>/dev/null | wc -l)" -ge 0 ]; then
    echo "PASS: 8.3b session id sanitized — no escape"
    PASS=$((PASS + 1))
else
    echo "FAIL: 8.3b session id sanitization failed"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================"
echo "RESULTS: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
echo "============================================================"

[ "$FAIL" -eq 0 ]
