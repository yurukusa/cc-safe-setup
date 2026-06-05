#!/bin/bash
# Tests for tool-result-size-guard.sh
HOOK="examples/tool-result-size-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  output: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; echo "  output: $2"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

run_hook() { echo "$1" | bash "$HOOK" 2>&1; }
run_hook_exit() { echo "$1" | bash "$HOOK" > /dev/null 2>&1; echo $?; }

# Test 1: empty command — silent pass
OUT=$(run_hook '{"tool_input":{"command":""}}')
RC=$(run_hook_exit '{"tool_input":{"command":""}}')
assert_not_contains "empty command no warning" "$OUT" "WARNING"
assert_exit "empty command exit 0" "$RC" "0"

# Test 2: harmless command — silent pass
OUT=$(run_hook '{"tool_input":{"command":"ls -la"}}')
RC=$(run_hook_exit '{"tool_input":{"command":"ls -la"}}')
assert_not_contains "harmless ls -la no warning" "$OUT" "WARNING"
assert_exit "harmless ls -la exit 0" "$RC" "0"

# Test 3: find / without -maxdepth — warns
OUT=$(run_hook '{"tool_input":{"command":"find / -name foo"}}')
RC=$(run_hook_exit '{"tool_input":{"command":"find / -name foo"}}')
assert_contains "find / warns" "$OUT" "find / or find ~"
assert_contains "find / suggests -maxdepth" "$OUT" "maxdepth"
assert_exit "find / warn exit 0" "$RC" "0"

# Test 4: find / with -maxdepth — silent pass
OUT=$(run_hook '{"tool_input":{"command":"find / -maxdepth 3 -name foo"}}')
RC=$(run_hook_exit '{"tool_input":{"command":"find / -maxdepth 3 -name foo"}}')
assert_not_contains "find / -maxdepth no warning" "$OUT" "WARNING"
assert_exit "find / -maxdepth exit 0" "$RC" "0"

# Test 5: ls -R — warns
OUT=$(run_hook '{"tool_input":{"command":"ls -R /tmp"}}')
assert_contains "ls -R warns" "$OUT" "ls -R"

# Test 6: ls -R piped to head — silent pass
OUT=$(run_hook '{"tool_input":{"command":"ls -R /tmp | head -50"}}')
assert_not_contains "ls -R | head no warning" "$OUT" "WARNING"

# Test 7: tail -f — warns
OUT=$(run_hook '{"tool_input":{"command":"tail -f /var/log/syslog"}}')
assert_contains "tail -f warns" "$OUT" "tail -f"
assert_contains "tail -f suggests one-shot" "$OUT" "one-shot"

# Test 8: tail -n (one-shot) — silent pass
OUT=$(run_hook '{"tool_input":{"command":"tail -n 100 /var/log/syslog"}}')
assert_not_contains "tail -n no warning" "$OUT" "WARNING"

# Test 9: dmesg — warns
OUT=$(run_hook '{"tool_input":{"command":"dmesg"}}')
assert_contains "dmesg warns" "$OUT" "dmesg"

# Test 10: dmesg | tail — silent pass
OUT=$(run_hook '{"tool_input":{"command":"dmesg | tail -100"}}')
assert_not_contains "dmesg | tail no warning" "$OUT" "WARNING"

# Test 11: journalctl without -n — warns
OUT=$(run_hook '{"tool_input":{"command":"journalctl"}}')
assert_contains "journalctl warns" "$OUT" "journalctl without"

# Test 12: journalctl -n 100 — silent pass
OUT=$(run_hook '{"tool_input":{"command":"journalctl -n 100"}}')
assert_not_contains "journalctl -n no warning" "$OUT" "WARNING"

# Test 13: git log without -n — warns
OUT=$(run_hook '{"tool_input":{"command":"git log"}}')
assert_contains "git log warns" "$OUT" "git log"

# Test 14: git log --oneline — silent pass
OUT=$(run_hook '{"tool_input":{"command":"git log --oneline"}}')
assert_not_contains "git log --oneline no warning" "$OUT" "WARNING"

# Test 15: git log -10 — silent pass
OUT=$(run_hook '{"tool_input":{"command":"git log -10"}}')
assert_not_contains "git log -10 no warning" "$OUT" "WARNING"

# Test 16: npm ls -a — warns
OUT=$(run_hook '{"tool_input":{"command":"npm ls -a"}}')
assert_contains "npm ls -a warns" "$OUT" "npm ls"

# Test 17: pip list — warns
OUT=$(run_hook '{"tool_input":{"command":"pip list"}}')
assert_contains "pip list warns" "$OUT" "pip list"

# Test 18: pip list | grep — silent pass
OUT=$(run_hook '{"tool_input":{"command":"pip list | grep claude"}}')
assert_not_contains "pip list | grep no warning" "$OUT" "WARNING"

# Test 19: docker logs without --tail — warns
OUT=$(run_hook '{"tool_input":{"command":"docker logs mycontainer"}}')
assert_contains "docker logs warns" "$OUT" "docker logs"

# Test 20: docker logs --tail 200 — silent pass
OUT=$(run_hook '{"tool_input":{"command":"docker logs --tail 200 mycontainer"}}')
assert_not_contains "docker logs --tail no warning" "$OUT" "WARNING"

# Test 21: BLOCK_MODE upgrade — find / blocks
RC=$(CC_TOOL_RESULT_BLOCK=1 sh -c "echo '{\"tool_input\":{\"command\":\"find / -name foo\"}}' | bash $HOOK > /dev/null 2>&1; echo \$?")
assert_exit "BLOCK_MODE find / blocks with exit 2" "$RC" "2"

# Test 22: BLOCK_MODE harmless still passes
RC=$(CC_TOOL_RESULT_BLOCK=1 sh -c "echo '{\"tool_input\":{\"command\":\"ls -la\"}}' | bash $HOOK > /dev/null 2>&1; echo \$?")
assert_exit "BLOCK_MODE harmless passes" "$RC" "0"

# Test 23: SKIP pattern — find / skipped
OUT=$(CC_TOOL_RESULT_GUARD_SKIP=find sh -c "echo '{\"tool_input\":{\"command\":\"find / -name foo\"}}' | bash $HOOK 2>&1")
assert_not_contains "SKIP find suppresses warning" "$OUT" "find / or find ~"

# Test 24: Invalid JSON — silent pass (no crash)
RC=$(echo 'not json' | bash "$HOOK" > /dev/null 2>&1; echo $?)
assert_exit "invalid JSON exit 0" "$RC" "0"

echo ""
echo "PASS: $PASS / $((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
