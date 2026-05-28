#!/bin/bash
# Tests for hook-self-disable-detector.sh

set -u
HOOK="$(dirname "$0")/../examples/hook-self-disable-detector.sh"
PASS=0
FAIL=0

assert_no_warning() {
    local desc="$1"
    local output="$2"
    if ! echo "$output" | grep -q '⚠ hook-self-disable-detector'; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — unexpected warning: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_warning() {
    local desc="$1"
    local output="$2"
    if echo "$output" | grep -q '⚠ hook-self-disable-detector'; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected warning, got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1"
    local output="$2"
    local needle="$3"
    if echo "$output" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in: $output"
        FAIL=$((FAIL + 1))
    fi
}

new_workspace() {
    local d
    d=$(mktemp -d /tmp/test-hook-self-disable.XXXXXX)
    mkdir -p "$d/state" "$d/.claude"
    echo "$d"
}

write_settings() {
    local path="$1"; shift
    cat > "$path" <<EOF
$*
EOF
}

settings_with_two_hooks='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"bash hookA.sh"}]},{"matcher":"Edit","hooks":[{"command":"bash hookB.sh"}]}]}}'
settings_with_one_hook='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"bash hookA.sh"}]}]}}'
settings_with_three_hooks='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"bash hookA.sh"}]},{"matcher":"Edit","hooks":[{"command":"bash hookB.sh"}]}],"PostToolUse":[{"matcher":"","hooks":[{"command":"bash hookC.sh"}]}]}}'
settings_empty_hooks='{"hooks":{}}'
settings_no_hooks_key='{}'
settings_malformed='{"hooks": {"PreToolUse": ['

# --- Test 1: first run is silent under QUIET=1 ---
echo "Test 1: first run with QUIET=1 emits no informational message"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "first run produces no warning" "$out"
[ -z "$out" ] && PASS=$((PASS + 1)) && echo "  PASS: first run with QUIET=1 truly silent" || { FAIL=$((FAIL + 1)); echo "  FAIL: first run not silent: $out"; }
rm -rf "$WS"

# --- Test 2: first run with QUIET=0 emits informational note ---
echo "Test 2: first run with QUIET=0 mentions snapshot count"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" bash "$HOOK" 2>&1)
assert_contains "first run informational message present" "$out" "first run"
assert_no_warning "first run shows no removal warning" "$out"
rm -rf "$WS"

# --- Test 3: second run with no changes is silent ---
echo "Test 3: second run with identical state emits no warning"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "no warning when state unchanged" "$out"
rm -rf "$WS"

# --- Test 4: a removed user hook triggers a warning naming it ---
echo "Test 4: removing a user hook produces a warning listing it"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
write_settings "$WS/user.json" "$settings_with_one_hook"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_warning "removal of hookB triggers warning" "$out"
assert_contains "warning names the missing hook command" "$out" "bash hookB.sh"
assert_contains "warning labels the origin user" "$out" "[user]"
rm -rf "$WS"

# --- Test 5: a removed project hook is also detected ---
echo "Test 5: removing a project hook is detected and labeled project"
WS=$(new_workspace)
write_settings "$WS/.claude/settings.json" "$settings_with_two_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/no-user.json" CC_PROJECT_SETTINGS="$WS/.claude/settings.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
write_settings "$WS/.claude/settings.json" "$settings_with_one_hook"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/no-user.json" CC_PROJECT_SETTINGS="$WS/.claude/settings.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_warning "project hook removal triggers warning" "$out"
assert_contains "warning labels the origin project" "$out" "[project]"
rm -rf "$WS"

# --- Test 6: adding a new hook is NOT a warning ---
echo "Test 6: adding a new hook produces no warning"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_one_hook"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
write_settings "$WS/user.json" "$settings_with_two_hooks"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "adding a hook does not warn" "$out"
rm -rf "$WS"

# --- Test 7: changing a command counts as a removal+addition (warning) ---
echo "Test 7: changing a command emits a warning naming the old command"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
mutated='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"bash hookA-NEW.sh"}]},{"matcher":"Edit","hooks":[{"command":"bash hookB.sh"}]}]}}'
write_settings "$WS/user.json" "$mutated"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_warning "command change warns" "$out"
assert_contains "old command name is reported" "$out" "bash hookA.sh"
rm -rf "$WS"

# --- Test 8: changing a matcher counts as a removal+addition ---
echo "Test 8: changing a matcher emits a warning"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
mutated='{"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"command":"bash hookA.sh"}]},{"matcher":"Edit","hooks":[{"command":"bash hookB.sh"}]}]}}'
write_settings "$WS/user.json" "$mutated"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_warning "matcher change warns" "$out"
assert_contains "old matcher Bash mentioned" "$out" "matcher='Bash'"
rm -rf "$WS"

# --- Test 9: missing user settings does not crash; project alone suffices ---
echo "Test 9: missing user settings is tolerated"
WS=$(new_workspace)
write_settings "$WS/.claude/settings.json" "$settings_with_one_hook"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/no-user.json" CC_PROJECT_SETTINGS="$WS/.claude/settings.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "missing user settings does not warn on first run" "$out"
rm -rf "$WS"

# --- Test 10: both settings absent is tolerated ---
echo "Test 10: both user and project settings absent does not crash"
WS=$(new_workspace)
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/no-user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "no settings files does not warn" "$out"
rm -rf "$WS"

# --- Test 11: empty hooks object is treated as zero entries ---
echo "Test 11: empty hooks object snapshots zero entries without crash"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_empty_hooks"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "empty hooks object is silent" "$out"
rm -rf "$WS"

# --- Test 12: settings.json without a hooks key is tolerated ---
echo "Test 12: settings.json without a hooks key is tolerated"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_no_hooks_key"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_no_warning "no hooks key is silent" "$out"
rm -rf "$WS"

# --- Test 13: malformed settings.json is tolerated (no crash) ---
echo "Test 13: malformed settings.json does not crash the session"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_malformed"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
status=$?
[ "$status" -eq 0 ] && PASS=$((PASS + 1)) && echo "  PASS: malformed input exits 0" || { FAIL=$((FAIL + 1)); echo "  FAIL: malformed input exit=$status"; }
rm -rf "$WS"

# --- Test 14: detector handles multiple event types ---
echo "Test 14: detector handles PreToolUse and PostToolUse together"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_three_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
mutated='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"bash hookA.sh"}]},{"matcher":"Edit","hooks":[{"command":"bash hookB.sh"}]}]}}'
write_settings "$WS/user.json" "$mutated"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_warning "removal of PostToolUse hook is detected" "$out"
assert_contains "PostToolUse event labeled in warning" "$out" "event=PostToolUse"
assert_contains "removed hookC.sh named" "$out" "bash hookC.sh"
rm -rf "$WS"

# --- Test 15: snapshot file is created after each run ---
echo "Test 15: snapshot file is written after each invocation"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_two_hooks"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
count=$(ls "$WS/state"/snapshot-*.txt 2>/dev/null | wc -l)
[ "$count" -ge 1 ] && PASS=$((PASS + 1)) && echo "  PASS: snapshot file created" || { FAIL=$((FAIL + 1)); echo "  FAIL: no snapshot file"; }
sleep 1
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/no-project.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
count=$(ls "$WS/state"/snapshot-*.txt 2>/dev/null | wc -l)
[ "$count" -ge 2 ] && PASS=$((PASS + 1)) && echo "  PASS: second invocation adds another snapshot" || { FAIL=$((FAIL + 1)); echo "  FAIL: snapshot count $count"; }
rm -rf "$WS"

# --- Test 16: removing both user and project hooks lists both origins ---
echo "Test 16: simultaneous user and project removals list both origins"
WS=$(new_workspace)
write_settings "$WS/user.json" "$settings_with_one_hook"
write_settings "$WS/.claude/settings.json" "$settings_with_one_hook"
echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/.claude/settings.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" >/dev/null 2>&1
write_settings "$WS/user.json" "$settings_empty_hooks"
write_settings "$WS/.claude/settings.json" "$settings_empty_hooks"
out=$(echo '{}' | CC_HOOK_STATE_DIR="$WS/state" CC_USER_SETTINGS="$WS/user.json" CC_PROJECT_SETTINGS="$WS/.claude/settings.json" CC_HOOK_DISABLE_QUIET=1 bash "$HOOK" 2>&1)
assert_contains "user origin reported" "$out" "[user]"
assert_contains "project origin reported" "$out" "[project]"
rm -rf "$WS"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
