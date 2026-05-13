#!/bin/bash
# Tests for mcp-tool-response-mismatch.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/mcp-tool-response-mismatch.sh"
TEST_HOME=$(mktemp -d)
PASS=0; FAIL=0; TOTAL=0

# Override HOME to isolate state
export HOME="$TEST_HOME"

make_payload() {
    local tool="$1"
    local response="$2"
    jq -nc --arg tool "$tool" --arg resp "$response" '{
        session_id: "test-session",
        tool_name: $tool,
        tool_response: $resp
    }'
}

run_exit_zero() {
    local desc="$1"; local tool="$2"; local response="$3"
    TOTAL=$((TOTAL + 1))
    local payload
    payload=$(make_payload "$tool" "$response")
    local out
    out=$(echo "$payload" | bash "$HOOK" 2>&1)
    local code=$?
    if [[ "$code" -eq 0 ]]; then
        PASS=$((PASS + 1))
        echo "✅ $desc (exit 0)"
    else
        FAIL=$((FAIL + 1))
        echo "❌ $desc (exit $code, expected 0): $out"
    fi
}

run_exit_two() {
    local desc="$1"; local tool="$2"; local response="$3"
    TOTAL=$((TOTAL + 1))
    local payload
    payload=$(make_payload "$tool" "$response")
    local out
    out=$(echo "$payload" | bash "$HOOK" 2>&1)
    local code=$?
    if [[ "$code" -eq 2 ]]; then
        PASS=$((PASS + 1))
        echo "✅ $desc (exit 2 = block)"
    else
        FAIL=$((FAIL + 1))
        echo "❌ $desc (exit $code, expected 2): $out"
    fi
}

# --- TESTS ---

echo "=== Test 1: Non-MCP tools → exit 0 (no-op) ==="
run_exit_zero "Bash tool" "Bash" "Browser extension is not connected"
run_exit_zero "Edit tool" "Edit" "not connected to mcp"
run_exit_zero "Read tool" "Read" "tools not exposed"
run_exit_zero "Empty tool name" "" "browser extension is not connected"

echo ""
echo "=== Test 2: MCP tool with normal response → exit 0 ==="
run_exit_zero "mcp__github__list_repos with normal output" \
    "mcp__github__list_repos" '{"repos": ["foo", "bar"]}'
run_exit_zero "mcp__gitlab__create_issue with success" \
    "mcp__gitlab__create_issue" '{"issue_number": 42, "url": "https://gitlab.com/..."}'
run_exit_zero "mcp__claude-in-chrome__tabs with content" \
    "mcp__claude-in-chrome__tabs" '[{"id": 1, "url": "https://example.com"}]'

echo ""
echo "=== Test 3: #58553 pattern (claude-in-chrome) → exit 2 ==="
run_exit_two "Browser extension is not connected" \
    "mcp__claude-in-chrome__tabs_context_mcp" \
    "Browser extension is not connected. Please ensure the Claude browser extension is installed."

echo ""
echo "=== Test 4: #58506 pattern (GitLab tools not exposed) → exit 2 ==="
run_exit_two "tools not exposed pattern" \
    "mcp__gitlab__list_projects" \
    "Error: tools not exposed to Claude's context. Relay connected but no tools available."

echo ""
echo "=== Test 5: Various disconnection patterns → exit 2 ==="
run_exit_two "mcp server not responding" \
    "mcp__notion__search" \
    "Error: mcp server not responding after 30s timeout"

run_exit_two "extension is not connected (variant)" \
    "mcp__browser__screenshot" \
    "Error: extension is not connected"

run_exit_two "no tools available" \
    "mcp__sentry__list_issues" \
    "Connection established but no tools available from relay"

run_exit_two "mcp handshake failed" \
    "mcp__slack__post" \
    "Failed: MCP handshake failed at /handshake endpoint"

echo ""
echo "=== Test 6: Case-insensitive matching → exit 2 ==="
run_exit_two "uppercase pattern" \
    "mcp__test__call" \
    "ERROR: BROWSER EXTENSION IS NOT CONNECTED to host"

run_exit_two "mixed case" \
    "mcp__test__call" \
    "Tools Not Exposed in current session"

echo ""
echo "=== Test 7: Disable flag → exit 0 always ==="
export CC_MCP_MISMATCH_DISABLE=1
run_exit_zero "disabled, would normally block" \
    "mcp__claude-in-chrome__tabs" \
    "Browser extension is not connected"
unset CC_MCP_MISMATCH_DISABLE

echo ""
echo "=== Test 8: Extra patterns via env → exit 2 ==="
export CC_MCP_MISMATCH_EXTRA_PATTERNS="custom error xyz:another known issue"
run_exit_two "custom pattern matches" \
    "mcp__test__call" \
    "Failure: custom error xyz occurred in handshake"
run_exit_two "another custom pattern" \
    "mcp__test__call" \
    "another known issue with the relay"
run_exit_zero "non-matching with custom patterns" \
    "mcp__test__call" \
    "Success: operation completed"
unset CC_MCP_MISMATCH_EXTRA_PATTERNS

echo ""
echo "=== Test 9: Empty/malformed payload → exit 0 ==="
TOTAL=$((TOTAL + 1))
out=$(echo "" | bash "$HOOK" 2>&1)
code=$?
if [[ "$code" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "✅ empty payload → exit 0"
else
    FAIL=$((FAIL + 1))
    echo "❌ empty payload (exit $code): $out"
fi

TOTAL=$((TOTAL + 1))
out=$(echo '{"tool_name": "mcp__test__call"}' | bash "$HOOK" 2>&1)
code=$?
if [[ "$code" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "✅ no response field → exit 0"
else
    FAIL=$((FAIL + 1))
    echo "❌ no response field (exit $code): $out"
fi

echo ""
echo "=== Test 10: Log file written on block ==="
TOTAL=$((TOTAL + 1))
LOG_FILE="$TEST_HOME/.claude/state/mcp-mismatch-log.jsonl"
# Trigger a block
echo "$(make_payload 'mcp__test__call' 'Browser extension is not connected')" | bash "$HOOK" > /dev/null 2>&1
if [[ -f "$LOG_FILE" ]] && grep -q "browser extension is not connected" "$LOG_FILE"; then
    PASS=$((PASS + 1))
    echo "✅ log file written and contains matched pattern"
else
    FAIL=$((FAIL + 1))
    echo "❌ log file missing or incorrect"
fi

# --- SUMMARY ---
echo ""
echo "================================"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
echo "================================"

# Cleanup
rm -rf "$TEST_HOME"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
