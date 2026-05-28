#!/bin/bash
# Tests for broad-prefix-session-trap-warner.sh (Cluster 6 Axis 8)
# Covers: default prefix matching across nine prefix categories,
# silent on non-matching commands, custom pattern override,
# disable/silent environment toggles, JSON output shape, fail-open.

HOOK="examples/broad-prefix-session-trap-warner.sh"
PASS=0 FAIL=0

run_hook() {
    local payload="$1"; shift
    env -u CC_BROAD_PREFIX_PATTERNS -u CC_BROAD_PREFIX_DISABLE \
        -u CC_BROAD_PREFIX_SILENT \
        "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: empty input — silent, exit 0
OUT=$(run_hook '{}')
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
assert_not_contains "empty input silent" "$OUT" "broad-prefix"

# Test 2: docker matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"docker ps -a"}}')
RC=$?
assert_exit "docker exit 0" "$RC" "0"
assert_contains "docker warns" "$OUT" "broad-prefix command detected"
assert_contains "docker references #62437" "$OUT" "#62437"
assert_contains "docker recommends Approve once" "$OUT" "Approve once"
assert_contains "docker emits PreToolUse hookSpecificOutput" "$OUT" "PreToolUse"

# Test 3: kubectl matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"kubectl get pods -n kube-system"}}')
assert_contains "kubectl warns" "$OUT" "broad-prefix command detected"
assert_contains "kubectl names matched pattern" "$OUT" "kubectl"

# Test 4: gcloud matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"gcloud compute instances list"}}')
assert_contains "gcloud warns" "$OUT" "broad-prefix command detected"

# Test 5: aws matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"aws s3 ls"}}')
assert_contains "aws warns" "$OUT" "broad-prefix command detected"

# Test 6: helm matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"helm list"}}')
assert_contains "helm warns" "$OUT" "broad-prefix command detected"

# Test 7: terraform matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"terraform plan"}}')
assert_contains "terraform warns" "$OUT" "broad-prefix command detected"

# Test 8: rm -rf matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"rm -rf /tmp/scratch"}}')
assert_contains "rm -rf warns" "$OUT" "broad-prefix command detected"

# Test 9: rm -Rf (capital R) also matches
OUT=$(run_hook '{"tool_input":{"command":"rm -Rf /tmp/scratch"}}')
assert_contains "rm -Rf warns" "$OUT" "broad-prefix command detected"

# Test 10: rm -f without -r still matches the bracket class [rRf]
OUT=$(run_hook '{"tool_input":{"command":"rm -f /tmp/scratch"}}')
assert_contains "rm -f warns" "$OUT" "broad-prefix command detected"

# Test 11: dd matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"dd if=/dev/zero of=/tmp/x bs=1M count=10"}}')
assert_contains "dd warns" "$OUT" "broad-prefix command detected"

# Test 12: mkfs matches the default broad-prefix list
OUT=$(run_hook '{"tool_input":{"command":"mkfs.ext4 /dev/sdz1"}}')
assert_contains "mkfs warns" "$OUT" "broad-prefix command detected"

# Test 13: safe command not in broad-prefix list — silent
OUT=$(run_hook '{"tool_input":{"command":"ls -la /tmp"}}')
RC=$?
assert_exit "safe command exit 0" "$RC" "0"
assert_not_contains "safe command silent" "$OUT" "broad-prefix command detected"

# Test 14: cat is not in the default list — silent
OUT=$(run_hook '{"tool_input":{"command":"cat /etc/hosts"}}')
assert_not_contains "cat silent" "$OUT" "broad-prefix command detected"

# Test 15: grep is not in the default list — silent
OUT=$(run_hook '{"tool_input":{"command":"grep -r foo ."}}')
assert_not_contains "grep silent" "$OUT" "broad-prefix command detected"

# Test 16: command must START with the prefix (no false positive on docker as substring)
OUT=$(run_hook '{"tool_input":{"command":"cat ./mydocker.txt"}}')
# 'docker' appears but pattern is 'docker( |$)' so 'docker.txt' has '.' after — should NOT match
assert_not_contains "docker as substring not matched" "$OUT" "broad-prefix command detected"

# Test 17: disable env var suppresses everything
OUT=$(run_hook '{"tool_input":{"command":"docker ps"}}' CC_BROAD_PREFIX_DISABLE=1)
RC=$?
assert_exit "disable exit 0" "$RC" "0"
assert_not_contains "disable silent" "$OUT" "broad-prefix command detected"

# Test 18: silent env var skips JSON but keeps stderr advisory
OUT=$(run_hook '{"tool_input":{"command":"docker ps"}}' CC_BROAD_PREFIX_SILENT=1)
assert_contains "silent keeps stderr" "$OUT" "broad-prefix command detected"
assert_not_contains "silent skips JSON" "$OUT" "hookSpecificOutput"

# Test 19: custom pattern override via env var
OUT=$(run_hook '{"tool_input":{"command":"sudo something"}}' 'CC_BROAD_PREFIX_PATTERNS=sudo( |$):rsync( |$)')
assert_contains "custom pattern sudo warns" "$OUT" "broad-prefix command detected"

# Test 20: custom pattern doesn't match default-list command
OUT=$(run_hook '{"tool_input":{"command":"docker ps"}}' 'CC_BROAD_PREFIX_PATTERNS=sudo( |$):rsync( |$)')
assert_not_contains "custom pattern excludes docker" "$OUT" "broad-prefix command detected"

# Test 21: malformed JSON input — fail-open (exit 0, no crash)
OUT=$(run_hook 'not-json')
RC=$?
assert_exit "malformed input exit 0" "$RC" "0"
assert_not_contains "malformed input silent" "$OUT" "broad-prefix command detected"

# Test 22: missing tool_input — fail-open silently
OUT=$(run_hook '{"other":"field"}')
RC=$?
assert_exit "missing tool_input exit 0" "$RC" "0"
assert_not_contains "missing tool_input silent" "$OUT" "broad-prefix command detected"

# Test 23: command with extra args after broad prefix still matches
OUT=$(run_hook '{"tool_input":{"command":"docker --host=tcp://example:2375 rm -f $(docker ps -q)"}}')
assert_contains "docker with --host warns" "$OUT" "broad-prefix command detected"

# Test 24: trap mechanics articulation present in warning
OUT=$(run_hook '{"tool_input":{"command":"docker ps"}}')
assert_contains "warning mentions docker rm -f trap example" "$OUT" "docker rm -f"
assert_contains "warning references meta-issue 30519" "$OUT" "#30519"
assert_contains "warning references bypass-mode meta 39523" "$OUT" "#39523"

# Test 25: hookSpecificOutput JSON shape — hookEventName is PreToolUse
OUT=$(run_hook '{"tool_input":{"command":"docker ps"}}')
assert_contains "JSON output names PreToolUse event" "$OUT" '"hookEventName": "PreToolUse"'
assert_contains "JSON output has additionalContext" "$OUT" "additionalContext"

# Test 26: warning explicitly recommends 'Approve once' over 'Always'
OUT=$(run_hook '{"tool_input":{"command":"kubectl delete pod foo"}}')
assert_contains "warning recommends Approve once" "$OUT" "Approve once"
assert_contains "warning warns against Always" "$OUT" "Reserve 'Always'"

# Test 27: empty command field — silent
OUT=$(run_hook '{"tool_input":{"command":""}}')
RC=$?
assert_exit "empty command exit 0" "$RC" "0"
assert_not_contains "empty command silent" "$OUT" "broad-prefix command detected"

# Test 28: compound command starting with broad prefix matches
OUT=$(run_hook '{"tool_input":{"command":"docker ps && echo done"}}')
assert_contains "compound docker warns" "$OUT" "broad-prefix command detected"

# Test 29: simulate session-approved cache state still warns (every invocation)
# Hook fires per-invocation; even if operator already approved-always in a
# prior session, the hook keeps surfacing the trap in case the env reset.
OUT1=$(run_hook '{"tool_input":{"command":"docker ps"}}')
OUT2=$(run_hook '{"tool_input":{"command":"docker rm -f $(docker ps -q)"}}')
assert_contains "first docker invocation warns" "$OUT1" "broad-prefix command detected"
assert_contains "second docker invocation also warns" "$OUT2" "broad-prefix command detected"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
