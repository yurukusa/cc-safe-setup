#!/bin/bash
# Tests for core-file-protect-guard.sh
# Run: bash tests/test-core-file-protect-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/core-file-protect-guard.sh"

test_hook() {
    local input="$1" expected_exit="$2" desc="$3"
    local actual_exit=0
    echo "$input" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

test_hook_env() {
    local env_var="$1" input="$2" expected_exit="$3" desc="$4"
    local actual_exit=0
    echo "$input" | env "$env_var" bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "core-file-protect-guard.sh tests"
echo ""

# --- Edit/Write on protected files (exit 2) ---
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"src/game_rules.py"}}' 2 "Edit rules file blocked"
test_hook '{"tool_name":"Write","tool_input":{"file_path":"app/config.yaml"}}' 2 "Write config file blocked"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"lib/core_engine.py"}}' 2 "Edit core file blocked"
test_hook '{"tool_name":"Write","tool_input":{"file_path":"settings/core_settings.json"}}' 2 "Write core settings blocked"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"data/combat_rules.json"}}' 2 "Edit combat_rules blocked"

# --- Edit/Write on non-protected files (exit 0) ---
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"src/main.py"}}' 0 "Edit non-protected file allowed"
test_hook '{"tool_name":"Write","tool_input":{"file_path":"src/utils.ts"}}' 0 "Write non-protected file allowed"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}' 0 "Edit README allowed"

# --- Bash sed/awk on protected files (exit 2) ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"sed -i s/old/new/ game_rules.txt"}}' 2 "sed -i on rules file blocked"
test_hook '{"tool_name":"Bash","tool_input":{"command":"awk -i inplace {print} core_logic.py"}}' 2 "awk -i on core file blocked"

# --- Bash on non-protected files (exit 0) ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"sed -i s/x/y/ main.py"}}' 0 "sed -i on non-protected allowed"
test_hook '{"tool_name":"Bash","tool_input":{"command":"cat config.yaml"}}' 0 "cat (read) on protected name allowed"

# --- Custom CC_PROTECTED_FILES ---
test_hook_env "CC_PROTECTED_FILES=*schema*:*migration*" '{"tool_name":"Edit","tool_input":{"file_path":"db/schema.rb"}}' 2 "custom env: schema file blocked"
test_hook_env "CC_PROTECTED_FILES=*schema*:*migration*" '{"tool_name":"Edit","tool_input":{"file_path":"src/game_rules.py"}}' 0 "custom env: rules file allowed (not in custom patterns)"

# --- Edge cases ---
test_hook '{"tool_name":"Edit","tool_input":{"file_path":""}}' 0 "empty file path passes"
test_hook '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "empty command passes"
test_hook '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' 0 "echo command allowed"
test_hook '{"tool_input":{"command":"ls"}}' 0 "no tool_name passes"
test_hook '{}' 0 "empty input passes"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed!"
