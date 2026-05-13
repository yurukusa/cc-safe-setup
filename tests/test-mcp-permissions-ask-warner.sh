#!/bin/bash
# Tests for mcp-permissions-ask-warner.sh

HOOK="$(dirname "$0")/../examples/mcp-permissions-ask-warner.sh"
PASS=0 FAIL=0

TMPROOT="$(mktemp -d -t cc-mcp-ask-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

write_settings() {
  local file="$1" body="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s' "$body" > "$file"
}

run_test() {
  local desc="$1" expected_exit="$2" files="$3" extra_env="$4"
  local logfile="$TMPROOT/log-$RANDOM"
  local actual_exit
  if [ -n "$extra_env" ]; then
    actual_exit=$(env CC_MCP_ASK_LOG="$logfile" CC_MCP_ASK_FILES="$files" $extra_env bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
  else
    actual_exit=$(env CC_MCP_ASK_LOG="$logfile" CC_MCP_ASK_FILES="$files" bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
  fi
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected $expected_exit, got $actual_exit)"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing mcp-permissions-ask-warner.sh"
echo "====================================="

# 1. No settings.json at all → pass silently
run_test "no settings.json passes silently" 0 "$TMPROOT/missing/settings.json"

# 2. settings.json without permissions key → pass
F="$TMPROOT/no-perms.json"
write_settings "$F" '{"theme":"dark"}'
run_test "settings without permissions key passes" 0 "$F"

# 3. permissions.ask empty → pass
F="$TMPROOT/empty-ask.json"
write_settings "$F" '{"permissions":{"ask":[]}}'
run_test "empty ask array passes" 0 "$F"

# 4. permissions.ask with non-MCP entries only → pass
F="$TMPROOT/no-mcp.json"
write_settings "$F" '{"permissions":{"ask":["Bash(rm:*)","Write"]}}'
run_test "ask with non-MCP entries passes" 0 "$F"

# 5. permissions.ask with ONE MCP entry → warn (exit 0 default)
F="$TMPROOT/one-mcp.json"
write_settings "$F" '{"permissions":{"ask":["mcp__atlassian__create_page"]}}'
run_test "one MCP entry warns" 0 "$F"

# 6. Same with block mode → exit 2
run_test "one MCP entry blocks in block mode" 2 "$F" "CC_MCP_ASK_ACTION=block"

# 7. Multiple MCP entries → warn, log has all
F="$TMPROOT/many-mcp.json"
write_settings "$F" '{"permissions":{"ask":["mcp__a__b","mcp__c__d","Bash"]}}'
LOG="$TMPROOT/many.log"
env CC_MCP_ASK_LOG="$LOG" CC_MCP_ASK_FILES="$F" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$LOG" ] && [ "$(grep -c "mcp_in_ask" "$LOG")" -eq 2 ]; then
  echo "  PASS: multiple MCP entries all logged"
  PASS=$((PASS+1))
else
  echo "  FAIL: multiple MCP entries log count"
  FAIL=$((FAIL+1))
fi

# 8. Two files, MCP entries in both → all detected
F1="$TMPROOT/file1.json"
F2="$TMPROOT/file2.json"
write_settings "$F1" '{"permissions":{"ask":["mcp__foo__bar"]}}'
write_settings "$F2" '{"permissions":{"ask":["mcp__baz__qux"]}}'
LOG="$TMPROOT/two-files.log"
env CC_MCP_ASK_LOG="$LOG" CC_MCP_ASK_FILES="$F1,$F2" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$LOG" ] && [ "$(grep -c "mcp_in_ask" "$LOG")" -eq 2 ]; then
  echo "  PASS: MCP entries across multiple files detected"
  PASS=$((PASS+1))
else
  echo "  FAIL: multi-file detection"
  FAIL=$((FAIL+1))
fi

# 9. Disabled → pass
F="$TMPROOT/disabled.json"
write_settings "$F" '{"permissions":{"ask":["mcp__x__y"]}}'
run_test "CC_MCP_ASK_DISABLE=1 disables hook" 0 "$F" "CC_MCP_ASK_DISABLE=1"

# 10. Malformed JSON → pass silently (jq returns empty)
F="$TMPROOT/malformed.json"
write_settings "$F" '{"permissions":'
run_test "malformed JSON passes silently" 0 "$F"

# 11. permissions.ask with object entry (non-string) → ignored
F="$TMPROOT/obj-entry.json"
write_settings "$F" '{"permissions":{"ask":[{"tool":"mcp__x__y"}]}}'
run_test "non-string ask entries ignored" 0 "$F"

# 12. Warning to stderr, stdout empty
F="$TMPROOT/stderr-test.json"
write_settings "$F" '{"permissions":{"ask":["mcp__test__call"]}}'
STDOUT=$(env CC_MCP_ASK_FILES="$F" bash "$HOOK" 2>/dev/null)
STDERR=$(env CC_MCP_ASK_FILES="$F" bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDOUT" ] && echo "$STDERR" | grep -q "MCP tool entries"; then
  echo "  PASS: stdout empty, stderr has warning"
  PASS=$((PASS+1))
else
  echo "  FAIL: stdout/stderr separation"
  FAIL=$((FAIL+1))
fi

# 13. Warning contains source file path
F="$TMPROOT/named.json"
write_settings "$F" '{"permissions":{"ask":["mcp__sample__action"]}}'
STDERR=$(env CC_MCP_ASK_FILES="$F" bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -qF "$F"; then
  echo "  PASS: warning mentions source file"
  PASS=$((PASS+1))
else
  echo "  FAIL: source file not in warning"
  FAIL=$((FAIL+1))
fi

# 14. Auto-discovery via CLAUDE_PROJECT_DIR
PROJDIR="$TMPROOT/proj"
mkdir -p "$PROJDIR/.claude"
echo '{"permissions":{"ask":["mcp__discovered__tool"]}}' > "$PROJDIR/.claude/settings.json"
LOG="$TMPROOT/auto.log"
EXIT=$(env -u CC_MCP_ASK_FILES CLAUDE_PROJECT_DIR="$PROJDIR" HOME="$TMPROOT/fakehome" CC_MCP_ASK_LOG="$LOG" bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
if [ "$EXIT" -eq 0 ] && [ -f "$LOG" ] && grep -q "mcp__discovered__tool" "$LOG"; then
  echo "  PASS: auto-discovery via CLAUDE_PROJECT_DIR"
  PASS=$((PASS+1))
else
  echo "  FAIL: CLAUDE_PROJECT_DIR auto-discovery"
  FAIL=$((FAIL+1))
fi

# 15. permissions.ask is null → pass
F="$TMPROOT/null-ask.json"
write_settings "$F" '{"permissions":{"ask":null}}'
run_test "ask=null passes silently" 0 "$F"

# 16. permissions.allow has MCP but ask doesn't → pass
F="$TMPROOT/allow-not-ask.json"
write_settings "$F" '{"permissions":{"allow":["mcp__x__y"],"ask":["Bash"]}}'
run_test "MCP in allow but not ask passes" 0 "$F"

# 17. permissions.deny has MCP but ask doesn't → pass
F="$TMPROOT/deny-not-ask.json"
write_settings "$F" '{"permissions":{"deny":["mcp__x__y"],"ask":[]}}'
run_test "MCP in deny but not ask passes" 0 "$F"

# 18. Log contains action value
F="$TMPROOT/action.json"
write_settings "$F" '{"permissions":{"ask":["mcp__log__check"]}}'
LOG="$TMPROOT/action.log"
env CC_MCP_ASK_LOG="$LOG" CC_MCP_ASK_FILES="$F" CC_MCP_ASK_ACTION="block" bash "$HOOK" >/dev/null 2>/dev/null
if grep -q "action=block" "$LOG"; then
  echo "  PASS: log records action value"
  PASS=$((PASS+1))
else
  echo "  FAIL: log missing action"
  FAIL=$((FAIL+1))
fi

# 19. Mixed MCP and non-MCP only logs MCP
F="$TMPROOT/mixed.json"
write_settings "$F" '{"permissions":{"ask":["Bash","mcp__keep__me","Write","mcp__also__keep","Read"]}}'
LOG="$TMPROOT/mixed.log"
env CC_MCP_ASK_LOG="$LOG" CC_MCP_ASK_FILES="$F" bash "$HOOK" >/dev/null 2>/dev/null
if [ "$(grep -c "mcp_in_ask" "$LOG")" -eq 2 ]; then
  echo "  PASS: only MCP entries logged from mixed ask list"
  PASS=$((PASS+1))
else
  echo "  FAIL: mixed list count"
  FAIL=$((FAIL+1))
fi

# 20. mcp__ prefix with nothing after → still treated as MCP entry (degenerate but valid prefix)
F="$TMPROOT/short.json"
write_settings "$F" '{"permissions":{"ask":["mcp__just_prefix"]}}'
run_test "MCP prefix with short name detected" 0 "$F"

# 21. Pre-existing log file is appended, not overwritten
F="$TMPROOT/append.json"
write_settings "$F" '{"permissions":{"ask":["mcp__append__test"]}}'
LOG="$TMPROOT/append.log"
echo "OLD LOG LINE" > "$LOG"
env CC_MCP_ASK_LOG="$LOG" CC_MCP_ASK_FILES="$F" bash "$HOOK" >/dev/null 2>/dev/null
if grep -q "OLD LOG LINE" "$LOG" && grep -q "mcp__append__test" "$LOG"; then
  echo "  PASS: log file appended, not overwritten"
  PASS=$((PASS+1))
else
  echo "  FAIL: log overwritten"
  FAIL=$((FAIL+1))
fi

echo "====================================="
echo "Result: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
