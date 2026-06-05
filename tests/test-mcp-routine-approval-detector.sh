#!/bin/bash
# Test for mcp-routine-approval-detector.sh
#
# Verifies the hook detects the May 2026 routine-approval cluster signature,
# writes a structured receipt, emits an operator-visible warning, and stays
# silent on all the cases that should NOT trigger.

set -u

HOOK="$(dirname "$0")/../examples/mcp-routine-approval-detector.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0

# Per-test temp receipt dir so cases don't bleed into each other
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

run_case() {
    local name="$1"
    local input="$2"
    local expect_receipt="$3"   # "yes" or "no"
    local expect_warning="$4"   # "yes" or "no"
    local extra_env="${5:-}"

    local receipt_dir="$TEST_DIR/$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_')"
    mkdir -p "$receipt_dir"

    local stderr rc
    stderr=$(printf '%s' "$input" | env -i \
        HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" \
        CC_MCP_ROUTINE_BLOCK_DIR="$receipt_dir" \
        $extra_env \
        "$HOOK" 2>&1 >/dev/null)
    rc=$?

    local receipt_count
    receipt_count=$(find "$receipt_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l)

    local got_receipt=no
    [ "$receipt_count" -gt 0 ] && got_receipt=yes

    local got_warning=no
    if echo "$stderr" | grep -q "mcp-routine-approval-detector"; then
        got_warning=yes
    fi

    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL+1))
        echo "FAIL: $name — exit $rc (expected 0)"
        echo "      stderr: $stderr"
        return
    fi

    if [ "$got_receipt" != "$expect_receipt" ]; then
        FAIL=$((FAIL+1))
        echo "FAIL: $name — receipt=$got_receipt (expected $expect_receipt)"
        echo "      stderr: $stderr"
        return
    fi

    if [ "$got_warning" != "$expect_warning" ]; then
        FAIL=$((FAIL+1))
        echo "FAIL: $name — warning=$got_warning (expected $expect_warning)"
        echo "      stderr: $stderr"
        return
    fi

    PASS=$((PASS+1))
}

# Test 1: cluster signature on Gmail connector triggers receipt and warning
INPUT1='{
  "tool_name": "mcp__claude_ai_Gmail__search_threads",
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval",
  "session_id": "test-1"
}'
run_case "cluster hit on Gmail writes receipt and warns" "$INPUT1" yes yes

# Test 2: cluster signature on Slack connector triggers
INPUT2='{
  "tool_name": "mcp__claude_ai_Slack__send_message",
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval",
  "session_id": "test-2"
}'
run_case "cluster hit on Slack writes receipt and warns" "$INPUT2" yes yes

# Test 3: non-MCP tool (Bash) skipped silently
INPUT3='{
  "tool_name": "Bash",
  "tool_result": "MCP tool call requires approval",
  "session_id": "test-3"
}'
run_case "non-MCP tool skipped silently" "$INPUT3" no no

# Test 4: MCP tool but no cluster signature — silent
INPUT4='{
  "tool_name": "mcp__claude_ai_Gmail__search_threads",
  "tool_result": "Found 5 threads",
  "session_id": "test-4"
}'
run_case "successful MCP call stays silent" "$INPUT4" no no

# Test 5: MCP tool with unrelated error — silent
INPUT5='{
  "tool_name": "mcp__claude_ai_Slack__send_message",
  "tool_result": "Channel not found",
  "session_id": "test-5"
}'
run_case "unrelated MCP error stays silent" "$INPUT5" no no

# Test 6: DISABLE env silences entirely
INPUT6='{
  "tool_name": "mcp__claude_ai_Gmail__search_threads",
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval",
  "session_id": "test-6"
}'
run_case "DISABLE env skips entirely" "$INPUT6" no no "CC_MCP_ROUTINE_BLOCK_DISABLE=1"

# Test 7: QUIET env writes receipt but suppresses warning
INPUT7='{
  "tool_name": "mcp__claude_ai_Notion__notion-fetch",
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval",
  "session_id": "test-7"
}'
run_case "QUIET env writes receipt but no warning" "$INPUT7" yes no "CC_MCP_ROUTINE_BLOCK_QUIET=1"

# Test 8: missing tool_name skipped
INPUT8='{
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval"
}'
run_case "missing tool_name skipped" "$INPUT8" no no

# Test 9: empty input skipped
INPUT9=''
run_case "empty input skipped" "$INPUT9" no no

# Test 10: malformed JSON skipped
INPUT10='not json at all'
run_case "malformed input skipped" "$INPUT10" no no

# Test 11: receipt content is well-formed JSON with all expected fields
INPUT11='{
  "tool_name": "mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql",
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval",
  "session_id": "well-formed-test"
}'
RECEIPT_DIR_11="$TEST_DIR/well_formed_test"
mkdir -p "$RECEIPT_DIR_11"
printf '%s' "$INPUT11" | env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" \
    CC_MCP_ROUTINE_BLOCK_DIR="$RECEIPT_DIR_11" \
    CC_MCP_ROUTINE_BLOCK_QUIET=1 \
    "$HOOK" 2>/dev/null

RECEIPT_FILE=$(find "$RECEIPT_DIR_11" -maxdepth 1 -type f -name '*.json' | head -1)
if [ -z "$RECEIPT_FILE" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: receipt is well-formed JSON — no receipt file found"
else
    TOOL=$(jq -r '.tool_name' "$RECEIPT_FILE" 2>/dev/null)
    SERVER=$(jq -r '.server' "$RECEIPT_FILE" 2>/dev/null)
    OPERATION=$(jq -r '.operation' "$RECEIPT_FILE" 2>/dev/null)
    SID=$(jq -r '.session_id' "$RECEIPT_FILE" 2>/dev/null)
    ERR=$(jq -r '.error_excerpt' "$RECEIPT_FILE" 2>/dev/null)

    if [ "$TOOL" = "mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql" ] \
       && [ "$SERVER" = "claude_ai_Atlassian" ] \
       && [ "$OPERATION" = "searchJiraIssuesUsingJql" ] \
       && [ "$SID" = "well-formed-test" ] \
       && [ -n "$ERR" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: receipt fields incorrect"
        echo "      tool=$TOOL server=$SERVER operation=$OPERATION sid=$SID err=$ERR"
    fi
fi

# Test 12: multiple hits in the same dir produce distinct files
INPUT12='{
  "tool_name": "mcp__claude_ai_Gmail__list_threads",
  "tool_result": "Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval",
  "session_id": "multi-receipt"
}'
RECEIPT_DIR_12="$TEST_DIR/multi_receipt"
mkdir -p "$RECEIPT_DIR_12"
for _ in 1 2; do
    printf '%s' "$INPUT12" | env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" \
        CC_MCP_ROUTINE_BLOCK_DIR="$RECEIPT_DIR_12" \
        CC_MCP_ROUTINE_BLOCK_QUIET=1 \
        "$HOOK" 2>/dev/null
    sleep 1  # second-resolution timestamp keeps filenames distinct
done
COUNT=$(find "$RECEIPT_DIR_12" -maxdepth 1 -type f -name '*.json' | wc -l)
if [ "$COUNT" = "2" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: multiple hits — expected 2 files, got $COUNT"
fi

# Test 13: error excerpt truncated to bounded length
LONG_ERR=$(printf 'Streamable HTTP error: Error POSTing to endpoint: MCP tool call requires approval')
LONG_PAD=$(printf 'X%.0s' $(seq 1 1500))
LONG_RESULT="${LONG_ERR} ${LONG_PAD}"
INPUT13=$(jq -nc \
    --arg t "mcp__claude_ai_Gmail__list_threads" \
    --arg r "$LONG_RESULT" \
    --arg s "trunc-test" \
    '{tool_name:$t, tool_result:$r, session_id:$s}')
RECEIPT_DIR_13="$TEST_DIR/trunc_test"
mkdir -p "$RECEIPT_DIR_13"
printf '%s' "$INPUT13" | env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" \
    CC_MCP_ROUTINE_BLOCK_DIR="$RECEIPT_DIR_13" \
    CC_MCP_ROUTINE_BLOCK_QUIET=1 \
    "$HOOK" 2>/dev/null
RECEIPT_FILE_13=$(find "$RECEIPT_DIR_13" -maxdepth 1 -type f -name '*.json' | head -1)
EXCERPT_LEN=$(jq -r '.error_excerpt | length' "$RECEIPT_FILE_13" 2>/dev/null)
if [ -n "$EXCERPT_LEN" ] && [ "$EXCERPT_LEN" -le 400 ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: excerpt truncation — length=$EXCERPT_LEN (expected ≤ 400)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
