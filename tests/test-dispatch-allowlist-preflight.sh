#!/bin/bash
# Tests for dispatch-allowlist-preflight.sh
# Issue: anthropics/claude-code#61315 (mitselek silent-stall on MCP gate)
# Principle: background sub-agent dispatch with MCP tool refs must surface
#            as a loud signal before the silent permission-gate stall.

HOOK="examples/dispatch-allowlist-preflight.sh"
PASS=0 FAIL=0

# Isolate receipts and settings to a temp directory
TMPDIR_RECEIPTS=$(mktemp -d)
TMPDIR_SETTINGS=$(mktemp -d)
export CC_DISPATCH_RECEIPT_DIR="$TMPDIR_RECEIPTS"
export CC_PROJECT_SETTINGS_PATH="$TMPDIR_SETTINGS/project-settings.json"
export CC_USER_SETTINGS_PATH="$TMPDIR_SETTINGS/user-settings.json"

cleanup() {
    [ -n "$TMPDIR_RECEIPTS" ] && [ -d "$TMPDIR_RECEIPTS" ] && find "$TMPDIR_RECEIPTS" -type f -delete && rmdir "$TMPDIR_RECEIPTS" 2>/dev/null
    [ -n "$TMPDIR_SETTINGS" ] && [ -d "$TMPDIR_SETTINGS" ] && find "$TMPDIR_SETTINGS" -type f -delete && rmdir "$TMPDIR_SETTINGS" 2>/dev/null
}
trap cleanup EXIT

assert_contains() { if echo "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

reset_state() {
    find "$CC_DISPATCH_RECEIPT_DIR" -name '*.jsonl' -delete 2>/dev/null
    rm -f "$CC_PROJECT_SETTINGS_PATH" "$CC_USER_SETTINGS_PATH"
    unset CC_DISPATCH_PREFLIGHT_MODE
}

# ----------------------------------------------------------------
# Group 1: Empty / malformed input silently passes
# ----------------------------------------------------------------

# Test 1: empty input silently passes
reset_state
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 2: tool_input with no fields silently passes
reset_state
OUT=$(echo '{"tool_input":{}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "tool_input empty exit 0" "$RC" "0"

# Test 3: completely invalid JSON treated as empty
reset_state
OUT=$(echo 'not json at all' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 2: Dispatches without MCP refs are no-op (still writes receipt)
# ----------------------------------------------------------------

# Test 4: dispatch with no MCP refs, no run_in_background — exit 0, no warning
reset_state
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"survey the codebase"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no-MCP foreground exit 0" "$RC" "0"
assert_not_contains "no-MCP foreground no warning" "$OUT" "WARNING"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt mcp_tools_referenced empty" "$RECEIPT_BODY" '"mcp_tools_referenced":\[\]'
assert_contains "receipt decision execute" "$RECEIPT_BODY" '"decision":"execute"'

# Test 5: dispatch with no MCP refs, run_in_background=true — exit 0, no warning
reset_state
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"do the work","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no-MCP background exit 0" "$RC" "0"
assert_not_contains "no-MCP background no warning" "$OUT" "WARNING"

# Test 6: MCP ref but foreground (no run_in_background) — exit 0, no warning
reset_state
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"call mcp__service__tool"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "MCP foreground exit 0" "$RC" "0"
assert_not_contains "MCP foreground no warning (foreground surfaces prompts)" "$OUT" "WARNING"

# ----------------------------------------------------------------
# Group 3: MCP refs + background — warning mode (default)
# ----------------------------------------------------------------

# Test 7: MCP ref + run_in_background — warns to stderr, exits 0
reset_state
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"call mcp__service__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "MCP bg warn-mode exit 0" "$RC" "0"
assert_contains "MCP bg warn-mode emits WARNING" "$OUT" "WARNING"
assert_contains "MCP bg warn-mode names tool" "$OUT" "mcp__service__tool"
assert_contains "MCP bg warn-mode references issue #61315" "$OUT" "61315"

# Test 8: warning mentions the silent-stall observation
reset_state
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"call mcp__service__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
assert_contains "warning explains 28-min stall" "$OUT" "28 min"
assert_contains "warning lists mitigations" "$OUT" "Mitigations"

# Test 9: multiple MCP refs in prompt all surfaced
reset_state
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__a__one and mcp__b__two","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "multi-MCP exit 0" "$RC" "0"
assert_contains "multi-MCP lists first tool" "$OUT" "mcp__a__one"
assert_contains "multi-MCP lists second tool" "$OUT" "mcp__b__two"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt has first MCP tool" "$RECEIPT_BODY" 'mcp__a__one'
assert_contains "receipt has second MCP tool" "$RECEIPT_BODY" 'mcp__b__two'

# ----------------------------------------------------------------
# Group 4: Refuse mode (CC_DISPATCH_PREFLIGHT_MODE=refuse)
# ----------------------------------------------------------------

# Test 10: refuse mode blocks dispatch (exit 2)
reset_state
export CC_DISPATCH_PREFLIGHT_MODE=refuse
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "refuse mode exit 2" "$RC" "2"
assert_contains "refuse mode emits BLOCKED" "$OUT" "BLOCKED"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt decision refuse" "$RECEIPT_BODY" '"decision":"refuse"'

# Test 11: refuse mode does NOT block when no MCP refs
reset_state
export CC_DISPATCH_PREFLIGHT_MODE=refuse
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain work","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "refuse mode no-MCP exit 0" "$RC" "0"
assert_not_contains "refuse mode no-MCP no BLOCKED" "$OUT" "BLOCKED"

# Test 12: refuse mode does NOT block when foreground (no run_in_background)
reset_state
export CC_DISPATCH_PREFLIGHT_MODE=refuse
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "refuse mode foreground exit 0" "$RC" "0"
assert_not_contains "refuse mode foreground no BLOCKED" "$OUT" "BLOCKED"

# ----------------------------------------------------------------
# Group 5: Off mode (CC_DISPATCH_PREFLIGHT_MODE=off)
# ----------------------------------------------------------------

# Test 13: off mode silent, but still writes receipt
reset_state
export CC_DISPATCH_PREFLIGHT_MODE=off
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "off mode exit 0" "$RC" "0"
assert_not_contains "off mode no WARNING" "$OUT" "WARNING"
assert_not_contains "off mode no BLOCKED" "$OUT" "BLOCKED"
RECEIPT_FILES=$(find "$CC_DISPATCH_RECEIPT_DIR" -name '*.jsonl' | wc -l)
if [ "$RECEIPT_FILES" -ge "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: off mode did not write receipt"; fi

# ----------------------------------------------------------------
# Group 6: Allowlist coverage detection
# ----------------------------------------------------------------

# Test 14: allowlist includes the MCP tool — coverage marked true,
# warning explains parent has it but inheritance bug persists
reset_state
cat > "$CC_PROJECT_SETTINGS_PATH" <<JSON
{"permissions":{"allow":["mcp__plugin__tool","Read"]}}
JSON
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "covered MCP exit 0" "$RC" "0"
assert_contains "covered MCP warning mentions parent allowlist" "$OUT" "In parent allowlist"
assert_contains "covered MCP warning mentions inheritance bug" "$OUT" "61315"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt marks coverage true" "$RECEIPT_BODY" '"parent_covered":true'

# Test 15: allowlist does NOT include the MCP tool — coverage false,
# warning mentions silent permission gate
reset_state
cat > "$CC_PROJECT_SETTINGS_PATH" <<JSON
{"permissions":{"allow":["Read","Bash"]}}
JSON
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
assert_contains "uncovered MCP warning mentions silent permission gate" "$OUT" "silent permission gate"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt marks coverage false" "$RECEIPT_BODY" '"parent_covered":false'

# Test 16: allowlist merged from both project + user scopes
reset_state
cat > "$CC_PROJECT_SETTINGS_PATH" <<JSON
{"permissions":{"allow":["Read"]}}
JSON
cat > "$CC_USER_SETTINGS_PATH" <<JSON
{"permissions":{"allow":["mcp__plugin__tool"]}}
JSON
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "user-scope allowlist counted" "$RECEIPT_BODY" '"parent_covered":true'

# Test 17: malformed settings file does not crash
reset_state
echo 'not valid json' > "$CC_PROJECT_SETTINGS_PATH"
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"use mcp__plugin__tool","run_in_background":true}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "malformed settings exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 7: Receipt format integrity
# ----------------------------------------------------------------

# Test 18: receipt is valid JSONL (one object per line)
reset_state
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"p1","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"y","prompt":"p2 with mcp__a__b","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
LINES_OK=0
LINES_TOTAL=0
while IFS= read -r line; do
    LINES_TOTAL=$((LINES_TOTAL+1))
    if echo "$line" | jq . >/dev/null 2>&1; then
        LINES_OK=$((LINES_OK+1))
    fi
done < "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl
if [ "$LINES_OK" = "2" ] && [ "$LINES_TOTAL" = "2" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: receipt JSONL not valid (got $LINES_OK/$LINES_TOTAL valid)"
fi

# Test 19: receipt has ISO 8601 UTC timestamp
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | head -1)
assert_contains "receipt ts ISO 8601 UTC" "$RECEIPT_BODY" '"ts":"20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z"'

# Test 20: PHI safety — prompt not stored verbatim
reset_state
SENSITIVE="patient SSN 123-45-6789 needs review"
echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"x\",\"prompt\":\"$SENSITIVE\",\"run_in_background\":true}}" | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_not_contains "receipt does not contain SSN" "$RECEIPT_BODY" "123-45-6789"
assert_not_contains "receipt does not contain 'patient'" "$RECEIPT_BODY" "patient SSN"
assert_contains "receipt does contain prompt_hash" "$RECEIPT_BODY" '"prompt_hash"'

# Test 21: prompt_hash deterministic sha256
reset_state
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"hello world","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
EXPECTED_HASH="b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
assert_contains "prompt_hash matches sha256('hello world')" "$RECEIPT_BODY" "$EXPECTED_HASH"

# ----------------------------------------------------------------
# Group 8: Edge cases
# ----------------------------------------------------------------

# Test 22: very large prompt (10KB) handled
reset_state
BIG=$(printf 'use mcp__a__b. ' && python3 -c "print('x' * 10000)")
PAYLOAD=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":%s,"run_in_background":true}}' "$(printf '%s' "$BIG" | jq -Rs .)")
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "10KB prompt exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "10KB prompt MCP ref captured" "$RECEIPT_BODY" "mcp__a__b"

# Test 23: special chars in subagent_type
reset_state
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"agent-with-dashes_and_under","prompt":"use mcp__svc__tool","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "subagent_type with dashes preserved" "$RECEIPT_BODY" 'agent-with-dashes_and_under'

# Test 24: subagent_type missing — defaults to general-purpose
reset_state
echo '{"tool_name":"Agent","tool_input":{"prompt":"use mcp__svc__tool","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "subagent_type defaults to general-purpose" "$RECEIPT_BODY" '"subagent_type":"general-purpose"'

# ----------------------------------------------------------------
# Group 9: Audit query usability
# ----------------------------------------------------------------

# Test 25: audit query to find dispatches with MCP refs works
reset_state
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"a","prompt":"plain","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"b","prompt":"use mcp__svc__tool","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"c","prompt":"use mcp__other__one mcp__other__two","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
MCP_DISPATCHES=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null | jq -c 'select(.mcp_tools_referenced | length > 0)' | wc -l)
if [ "$MCP_DISPATCHES" = "2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: audit query expected 2 MCP-ref dispatches, got $MCP_DISPATCHES"; fi

# ----------------------------------------------------------------
# Group 10: Schema v2 — articulated_scope fields from companion log
#
# Schema v2 adds articulated_scope_hash and articulated_scope_length
# fields to the receipt, populated from the most recent
# userprompt-submit-YYYY-MM-DD.jsonl companion log entry. When the
# companion log is absent, both fields are written as null.
#
# Architecture rationale at:
# https://github.com/anthropics/claude-code/issues/61102#issuecomment-4514215413
# ----------------------------------------------------------------

# Test 26: receipt includes schema_version 2
reset_state
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain"}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null)
assert_contains "receipt has schema_version 2" "$RECEIPT_BODY" '"schema_version":2'

# Test 27: without companion log, articulated_scope_hash is null
reset_state
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain"}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null)
assert_contains "no companion → articulated_scope_hash null" "$RECEIPT_BODY" '"articulated_scope_hash":null'
assert_contains "no companion → articulated_scope_length null" "$RECEIPT_BODY" '"articulated_scope_length":null'

# Test 28: with companion log, articulated_scope fields populated
reset_state
COMPANION="$CC_DISPATCH_RECEIPT_DIR/userprompt-submit-$(date +%Y-%m-%d).jsonl"
cat > "$COMPANION" <<JSON
{"ts":"2026-05-22T00:00:00Z","prompt_hash":"abcdef0123456789","prompt_length":42,"schema_version":1}
JSON
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain"}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null)
assert_contains "with companion → articulated_scope_hash populated" "$RECEIPT_BODY" '"articulated_scope_hash":"abcdef0123456789"'
assert_contains "with companion → articulated_scope_length populated" "$RECEIPT_BODY" '"articulated_scope_length":42'

# Test 29: companion log with multiple entries — only the last is used
reset_state
COMPANION="$CC_DISPATCH_RECEIPT_DIR/userprompt-submit-$(date +%Y-%m-%d).jsonl"
cat > "$COMPANION" <<JSON
{"ts":"2026-05-22T00:00:00Z","prompt_hash":"first0000000000","prompt_length":10,"schema_version":1}
{"ts":"2026-05-22T00:00:01Z","prompt_hash":"last1111111111","prompt_length":20,"schema_version":1}
JSON
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain"}}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null)
assert_contains "last entry wins (hash)" "$RECEIPT_BODY" '"articulated_scope_hash":"last1111111111"'
assert_contains "last entry wins (length)" "$RECEIPT_BODY" '"articulated_scope_length":20'

# Test 30: malformed companion log entry — fields stay null, no crash
reset_state
COMPANION="$CC_DISPATCH_RECEIPT_DIR/userprompt-submit-$(date +%Y-%m-%d).jsonl"
echo 'not valid json at all' > "$COMPANION"
OUT=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "malformed companion exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null)
assert_contains "malformed companion → hash null" "$RECEIPT_BODY" '"articulated_scope_hash":null'

# Test 31: receipt is still valid JSONL with schema v2 fields
reset_state
COMPANION="$CC_DISPATCH_RECEIPT_DIR/userprompt-submit-$(date +%Y-%m-%d).jsonl"
cat > "$COMPANION" <<JSON
{"ts":"2026-05-22T00:00:00Z","prompt_hash":"abcd1234","prompt_length":50,"schema_version":1}
JSON
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"p1"}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"y","prompt":"p2 with mcp__a__b","run_in_background":true}}' | bash "$HOOK" >/dev/null 2>&1
LINES_OK=0
LINES_TOTAL=0
while IFS= read -r line; do
    LINES_TOTAL=$((LINES_TOTAL+1))
    if echo "$line" | jq . >/dev/null 2>&1; then
        LINES_OK=$((LINES_OK+1))
    fi
done < "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl
if [ "$LINES_OK" = "2" ] && [ "$LINES_TOTAL" = "2" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: v2 receipt JSONL not valid (got $LINES_OK/$LINES_TOTAL valid)"
fi

# Test 32: schema v2 receipt is joinable on articulated_scope_hash
reset_state
COMPANION="$CC_DISPATCH_RECEIPT_DIR/userprompt-submit-$(date +%Y-%m-%d).jsonl"
cat > "$COMPANION" <<JSON
{"ts":"2026-05-22T00:00:00Z","prompt_hash":"joinable_hash_1","prompt_length":33,"schema_version":1}
JSON
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"plain"}}' | bash "$HOOK" >/dev/null 2>&1
# Audit query: find dispatches whose articulated_scope is known
JOINABLE=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null | \
    jq -c 'select(.articulated_scope_hash != null)' | wc -l)
if [ "$JOINABLE" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: joinable receipt count expected 1, got $JOINABLE"; fi

echo ""
echo "===================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "===================="
[ "$FAIL" = "0" ] && exit 0 || exit 1
