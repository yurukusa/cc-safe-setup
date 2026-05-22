#!/bin/bash
# Tests for askuserquestion-autonomy-gate.sh
HOOK="$(dirname "$0")/../examples/askuserquestion-autonomy-gate.sh"
PASS=0; FAIL=0

# Use a temp receipt dir so we do not pollute the operator's real ~/.claude/receipts
TMP_RECEIPT_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_RECEIPT_DIR"' EXIT

run_test() {
    local desc="$1" input="$2" expect_code="$3" env_var="${4:-}"
    if [[ -n "$env_var" ]]; then
        result_code=$(echo "$input" | env CC_AUTONOMY_MODE_RECEIPT_DIR="$TMP_RECEIPT_DIR" $env_var bash "$HOOK" >/dev/null 2>&1; echo $?)
    else
        result_code=$(echo "$input" | env CC_AUTONOMY_MODE_RECEIPT_DIR="$TMP_RECEIPT_DIR" bash "$HOOK" >/dev/null 2>&1; echo $?)
    fi
    if [ "$result_code" = "$expect_code" ]; then
        echo "PASS: $desc"
        ((PASS++))
    else
        echo "FAIL: $desc (expected $expect_code, got $result_code)"
        ((FAIL++))
    fi
}

# -- Group 1: Tool gating (only AskUserQuestion matters) --

run_test "Allow other tool (Bash) even with autonomy on" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' "0" "CC_AUTONOMY_MODE=1"

run_test "Allow other tool (Edit) even with autonomy on" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x"}}' "0" "CC_AUTONOMY_MODE=1"

run_test "Allow other tool (Read) even with autonomy on" \
    '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' "0" "CC_AUTONOMY_MODE=1"

run_test "Empty input passes through" '{}' "0"

run_test "Empty tool_name passes through" \
    '{"tool_name":""}' "0" "CC_AUTONOMY_MODE=1"

# -- Group 2: Default mode (advisory) --

run_test "AskUserQuestion allowed when CC_AUTONOMY_MODE unset" \
    '{"tool_name":"AskUserQuestion","tool_input":{"question":"Continue?"}}' "0"

run_test "AskUserQuestion allowed when CC_AUTONOMY_MODE=0" \
    '{"tool_name":"AskUserQuestion","tool_input":{"question":"Continue?"}}' "0" "CC_AUTONOMY_MODE=0"

run_test "AskUserQuestion allowed when CC_AUTONOMY_MODE=anything-else" \
    '{"tool_name":"AskUserQuestion","tool_input":{"question":"Continue?"}}' "0" "CC_AUTONOMY_MODE=foo"

# -- Group 3: Blocking mode (CC_AUTONOMY_MODE=1) --

run_test "AskUserQuestion blocked when CC_AUTONOMY_MODE=1" \
    '{"tool_name":"AskUserQuestion","tool_input":{"question":"Continue?"}}' "2" "CC_AUTONOMY_MODE=1"

run_test "AskUserQuestion blocked with prompt field" \
    '{"tool_name":"AskUserQuestion","tool_input":{"prompt":"Should I proceed?"}}' "2" "CC_AUTONOMY_MODE=1"

run_test "AskUserQuestion blocked with neither question nor prompt" \
    '{"tool_name":"AskUserQuestion","tool_input":{}}' "2" "CC_AUTONOMY_MODE=1"

run_test "AskUserQuestion blocked with no tool_input at all" \
    '{"tool_name":"AskUserQuestion"}' "2" "CC_AUTONOMY_MODE=1"

# -- Group 4: Receipt writing --

# Reset receipt dir for this group
rm -rf "$TMP_RECEIPT_DIR" && mkdir -p "$TMP_RECEIPT_DIR"

echo '{"tool_name":"AskUserQuestion","tool_input":{"question":"hello world"}}' | \
    env CC_AUTONOMY_MODE_RECEIPT_DIR="$TMP_RECEIPT_DIR" CC_AUTONOMY_MODE=1 \
    bash "$HOOK" >/dev/null 2>&1

receipt_file=$(ls "$TMP_RECEIPT_DIR"/autonomy-blocked-*.jsonl 2>/dev/null | head -1)
if [[ -n "$receipt_file" ]] && [[ -s "$receipt_file" ]]; then
    echo "PASS: Receipt file is created and non-empty when blocking"
    ((PASS++))
else
    echo "FAIL: Receipt file was not created or is empty"
    ((FAIL++))
fi

if [[ -n "$receipt_file" ]] && grep -q '"event":"askuserquestion_blocked"' "$receipt_file"; then
    echo "PASS: Receipt records event field correctly"
    ((PASS++))
else
    echo "FAIL: Receipt does not contain expected event field"
    ((FAIL++))
fi

if [[ -n "$receipt_file" ]] && grep -q '"question_length":11' "$receipt_file"; then
    echo "PASS: Receipt records question_length matching wc -c (11 for 'hello world')"
    ((PASS++))
else
    echo "FAIL: Receipt question_length does not match expected 11"
    ((FAIL++))
fi

if [[ -n "$receipt_file" ]] && grep -qE '"question_hash":"[a-f0-9]{64}"' "$receipt_file"; then
    echo "PASS: Receipt records 64-hex-char sha256 question_hash"
    ((PASS++))
else
    echo "FAIL: Receipt question_hash is not a 64-char sha256"
    ((FAIL++))
fi

if [[ -n "$receipt_file" ]] && ! grep -q 'hello world' "$receipt_file"; then
    echo "PASS: Receipt does NOT contain raw question text (PHI-safe)"
    ((PASS++))
else
    echo "FAIL: Receipt leaks raw question text"
    ((FAIL++))
fi

# Multiple calls append, do not overwrite
echo '{"tool_name":"AskUserQuestion","tool_input":{"question":"second"}}' | \
    env CC_AUTONOMY_MODE_RECEIPT_DIR="$TMP_RECEIPT_DIR" CC_AUTONOMY_MODE=1 \
    bash "$HOOK" >/dev/null 2>&1

receipt_file=$(ls "$TMP_RECEIPT_DIR"/autonomy-blocked-*.jsonl 2>/dev/null | head -1)
line_count=$(wc -l < "$receipt_file" 2>/dev/null || echo 0)
if [[ "$line_count" = "2" ]]; then
    echo "PASS: Multiple blocked calls append (2 JSONL lines)"
    ((PASS++))
else
    echo "FAIL: Append did not work (expected 2 lines, got $line_count)"
    ((FAIL++))
fi

# -- Group 5: Stderr message content --

stderr=$(echo '{"tool_name":"AskUserQuestion","tool_input":{"question":"go?"}}' | \
    env CC_AUTONOMY_MODE_RECEIPT_DIR="$TMP_RECEIPT_DIR" CC_AUTONOMY_MODE=1 \
    bash "$HOOK" 2>&1 1>/dev/null)

if echo "$stderr" | grep -q "AskUserQuestion is blocked"; then
    echo "PASS: Stderr names AskUserQuestion as blocked"
    ((PASS++))
else
    echo "FAIL: Stderr does not name AskUserQuestion as blocked"
    ((FAIL++))
fi

if echo "$stderr" | grep -q "Do not retry"; then
    echo "PASS: Stderr instructs model not to retry"
    ((PASS++))
else
    echo "FAIL: Stderr does not instruct against retry"
    ((FAIL++))
fi

if echo "$stderr" | grep -q "defensible default choice"; then
    echo "PASS: Stderr suggests defensible default action"
    ((PASS++))
else
    echo "FAIL: Stderr does not suggest defensible default action"
    ((FAIL++))
fi

# -- Group 6: Robustness --

run_test "Malformed JSON input passes through (no jq crash)" \
    'not json' "0" "CC_AUTONOMY_MODE=1"

run_test "Empty tool_input still blocks AskUserQuestion" \
    '{"tool_name":"AskUserQuestion","tool_input":{}}' "2" "CC_AUTONOMY_MODE=1"

# Syntax check
if bash -n "$HOOK"; then
    echo "PASS: bash -n syntax check"
    ((PASS++))
else
    echo "FAIL: bash -n syntax check"
    ((FAIL++))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" = "0" ]
