#!/bin/bash
# Tests for subagent-identity-reassertion.sh — Issue #55488 mitigation hook
HOOK="examples/subagent-identity-reassertion.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit_code() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: Agent tool with subagent_type emits reminder block
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","name":"backend"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "Agent tool emits reminder header" "$OUT" "subagent-identity-reassertion"
assert_contains "reminder includes subagent label" "$OUT" "backend (general-purpose)"
assert_contains "reminder mentions Issue #55488" "$OUT" "#55488"
assert_contains "reminder includes parent-relay guard" "$OUT" "route sensitive DMs through the parent"
assert_contains "reminder includes context audit guard" "$OUT" "parent context does not contain secrets"
assert_contains "reminder includes identity-lock guard" "$OUT" "Confirm"
assert_exit_code "Agent tool exit 0" "$RC" 0

# Test 2: Bash tool skips silently with exit 0 (non-Agent fast path)
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "Bash tool emits no reminder" "$OUT" "subagent-identity-reassertion"
assert_exit_code "Bash tool exit 0" "$RC" 0

# Test 3: Empty tool_name skips silently
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty input emits no reminder" "$OUT" "subagent-identity-reassertion"
assert_exit_code "empty input exit 0" "$RC" 0

# Test 4: Agent without subagent_type still emits reminder with default label
OUT=$(echo '{"tool_name":"Agent","tool_input":{}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "Agent without subagent_type still warns" "$OUT" "subagent-identity-reassertion"
assert_contains "default role label is subagent" "$OUT" "Spawning subagent"
assert_exit_code "Agent without subagent_type exit 0" "$RC" 0

# Test 5: Agent with only subagent_type (no name)
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "Agent with only subagent_type" "$OUT" "Spawning general-purpose"
assert_exit_code "exit 0" "$RC" 0

# Test 6: Read tool (another non-Agent) skips silently
OUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "Read tool emits no reminder" "$OUT" "subagent-identity-reassertion"
assert_exit_code "Read tool exit 0" "$RC" 0

# Test 7: Malformed JSON falls through silently (jq returns empty)
OUT=$(echo 'not json' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "malformed JSON does not warn" "$OUT" "subagent-identity-reassertion"
# Note: jq exits with non-zero on malformed JSON, but `// empty` + set -euo
# may cause exit 1 here. Accept exit 0 or 1 (silent failure is acceptable).
[ "$RC" -le 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: malformed JSON exit code $RC > 1"; }

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
