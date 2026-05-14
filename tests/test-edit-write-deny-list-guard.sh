#!/bin/bash
# Tests for edit-write-deny-list-guard.sh
HOOK="$(dirname "$0")/../examples/edit-write-deny-list-guard.sh"
PASS=0 FAIL=0

# Use a temporary HOME so we don't touch the operator's real settings.
TEST_HOME=$(mktemp -d)
mkdir -p "$TEST_HOME/.claude"

cleanup() {
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

write_settings() {
    cat > "$TEST_HOME/.claude/settings.json"
}

run_test() {
    local desc="$1" expected_exit="$2" tool="$3" path="$4"
    local payload
    payload=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path")
    local actual_exit
    echo "$payload" | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>/dev/null
    actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        ((FAIL++))
    fi
}

echo "Testing edit-write-deny-list-guard.sh"
echo "======================================"

# Group 1: No deny rules configured
write_settings <<'EOF'
{}
EOF
run_test "no deny rules - Edit passes" 0 "Edit" "/tmp/any.md"
run_test "no deny rules - Write passes" 0 "Write" "/tmp/any.md"

# Group 2: Exact path match
write_settings <<'EOF'
{
  "permissions": {
    "deny": [
      "Edit(/path/to/protected.md)",
      "Write(/path/to/protected.md)"
    ]
  }
}
EOF
run_test "Edit on denied exact path is blocked" 2 "Edit" "/path/to/protected.md"
run_test "Write on denied exact path is blocked" 2 "Write" "/path/to/protected.md"
run_test "Edit on unrelated path passes" 0 "Edit" "/path/to/free.md"
run_test "Write on unrelated path passes" 0 "Write" "/path/to/free.md"

# Group 3: MultiEdit
write_settings <<'EOF'
{
  "permissions": {
    "deny": [
      "MultiEdit(/secrets/keys.txt)"
    ]
  }
}
EOF
run_test "MultiEdit on denied path is blocked" 2 "MultiEdit" "/secrets/keys.txt"
run_test "MultiEdit on unrelated path passes" 0 "MultiEdit" "/public/file.txt"

# Group 4: Glob pattern (*)
write_settings <<'EOF'
{
  "permissions": {
    "deny": [
      "Edit(/etc/*.conf)"
    ]
  }
}
EOF
run_test "Edit on path matching glob is blocked" 2 "Edit" "/etc/nginx.conf"
# Note: bash case "*" crosses directory boundaries (standard bash glob).
# Operators wanting single-level globs should use more specific patterns.
run_test "Edit on nested path also matches single-level glob (bash case semantics)" 2 "Edit" "/etc/nginx/conf.d/site.conf"
run_test "Edit on unrelated subtree passes" 0 "Edit" "/var/log/messages"

# Group 5: Recursive glob (**)
write_settings <<'EOF'
{
  "permissions": {
    "deny": [
      "Write(/var/log/**)"
    ]
  }
}
EOF
run_test "Write on path matching recursive glob is blocked" 2 "Write" "/var/log/app/access.log"

# Group 6: Bash() patterns are NOT enforced by this hook
write_settings <<'EOF'
{
  "permissions": {
    "deny": [
      "Bash(rm -rf *)"
    ]
  }
}
EOF
run_test "Bash deny pattern doesn't affect Edit" 0 "Edit" "/tmp/any.md"

# Group 7: Non-Edit/Write tools pass through
write_settings <<'EOF'
{
  "permissions": {
    "deny": [
      "Edit(/secret.md)"
    ]
  }
}
EOF
run_test "Read tool passes regardless of deny rules" 0 "Read" "/secret.md"
run_test "Bash tool passes (handled by native enforcement)" 0 "Bash" "/secret.md"

# Group 8: Local settings file
rm -f "$TEST_HOME/.claude/settings.json"
cat > "$TEST_HOME/.claude/settings.local.json" <<'EOF'
{
  "permissions": {
    "deny": [
      "Edit(/local/file.md)"
    ]
  }
}
EOF
run_test "deny rule from settings.local.json is enforced" 2 "Edit" "/local/file.md"

# Group 9: Combined global + local settings
write_settings <<'EOF'
{
  "permissions": {
    "deny": ["Edit(/global/file.md)"]
  }
}
EOF
cat > "$TEST_HOME/.claude/settings.local.json" <<'EOF'
{
  "permissions": {
    "deny": ["Write(/local/file.md)"]
  }
}
EOF
run_test "global Edit deny is enforced" 2 "Edit" "/global/file.md"
run_test "local Write deny is enforced" 2 "Write" "/local/file.md"

# Group 10: Empty file_path is permitted (defensive)
rm -f "$TEST_HOME/.claude/settings.local.json"
write_settings <<'EOF'
{
  "permissions": {
    "deny": ["Edit(/some/path.md)"]
  }
}
EOF
echo '{"tool_name":"Edit","tool_input":{}}' | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  PASS: empty file_path passes (defensive)"
    ((PASS++))
else
    echo "  FAIL: empty file_path should pass"
    ((FAIL++))
fi

# Group 11: Malformed settings.json doesn't crash the hook
write_settings <<'EOF'
{not valid json
EOF
run_test "malformed settings.json doesn't crash hook" 0 "Edit" "/tmp/any.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
