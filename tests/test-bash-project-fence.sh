#!/bin/bash
# Tests for bash-project-fence.sh
HOOK="$(dirname "$0")/../examples/bash-project-fence.sh"
PASS=0 FAIL=0

# Set up a fake project root in /tmp (already in default allow list, so we
# override CC_BASH_FENCE_ALLOW empty in tests that need /tmp as project root)
PROJECT_ROOT="/tmp/test-bash-project-fence-$$"
mkdir -p "$PROJECT_ROOT/src"
mkdir -p "$PROJECT_ROOT/docs"
trap 'rm -rf "$PROJECT_ROOT"' EXIT

run_test() {
  local desc="$1" expected_exit="$2" cmd="$3"
  shift 3
  local actual_exit
  echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(printf '%s' "$cmd" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}" \
    | env CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$@" bash "$HOOK" >/dev/null 2>/dev/null
  actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing bash-project-fence.sh"
echo "============================="

# 1. Empty command — pass
run_test "empty command passes" 0 ""

# 2. Relative path — pass (no absolute path tokens)
run_test "relative path passes" 0 "cat src/file.txt"

# 3. Absolute path inside project root — pass
run_test "absolute path inside project root passes" 0 "cat ${PROJECT_ROOT}/src/file.txt"

# 4. find inside project root — pass
run_test "find inside project root passes" 0 "find ${PROJECT_ROOT}/src -name '*.py'"

# 5. /tmp path — pass (default allow list includes /tmp)
run_test "/tmp path passes (default allow)" 0 "cat /tmp/something.txt"

# 6. /dev/null — pass (default allow list)
run_test "/dev/null passes (default allow)" 0 "command > /dev/null 2>&1"

# 7. Issue #56739 reproduction: find across Desktop — BLOCK
run_test "find across /Users Desktop blocks (#56739)" 2 \
  "find /Users/admin/Desktop -name '*.png'"

# 8. cat outside project — BLOCK
run_test "cat /etc/passwd blocks" 2 "cat /etc/passwd"

# 9. cp outside project — BLOCK (source outside)
run_test "cp /etc/hosts to project blocks" 2 \
  "cp /etc/hosts ${PROJECT_ROOT}/hosts.bak"

# 10. cp to outside project — BLOCK (destination outside)
run_test "cp project to /etc blocks" 2 \
  "cp ${PROJECT_ROOT}/file.txt /etc/file.txt"

# 11. ls outside project — BLOCK
run_test "ls /home/user/Documents blocks" 2 "ls /home/user/Documents"

# 12. grep outside project — BLOCK
run_test "grep on /var/log blocks" 2 "grep error /var/log/syslog"

# 13. Multiple paths, one outside — BLOCK
run_test "command with mixed paths blocks if any outside" 2 \
  "cp ${PROJECT_ROOT}/a /home/other/b"

# 14. CC_BASH_FENCE_ALLOW expansion allows specific path
run_test "CC_BASH_FENCE_ALLOW permits specified path" 0 \
  "cat /home/user/config.json" CC_BASH_FENCE_ALLOW="/home/user"

# 15. CC_BASH_FENCE_ACTION=warn returns 0 even when outside
run_test "warn action passes (exit 0) but emits warning" 0 \
  "cat /etc/passwd" CC_BASH_FENCE_ACTION=warn

# 16. CC_BASH_FENCE_OFF=1 disables hook
run_test "CC_BASH_FENCE_OFF=1 disables hook" 0 \
  "cat /etc/passwd" CC_BASH_FENCE_OFF=1

# 17. Tilde expansion to $HOME outside project
run_test "tilde-expanded HOME outside project blocks" 2 \
  "cat ~/Desktop/secret.png"

# 18. URL is skipped (not treated as path)
run_test "URL with absolute path scheme is skipped" 0 \
  "curl https://example.com/api"

# 19. Flag-like absolute argument is NOT skipped if it resolves outside.
# This is a documented limitation — operators should not use absolute paths
# as flag values pointing outside the project. The hook errs on the side of
# blocking. We assert the block here for clarity.
run_test "absolute path as command argument always checked" 2 \
  "find / -type f -name '*.key'"

# 20. find with -path option inside project — pass
run_test "find with relative -path option passes" 0 \
  "find ${PROJECT_ROOT} -path '*/docs/*'"

# 21. Output redirect target outside project — BLOCK
run_test "output redirect to /etc blocks" 2 \
  "echo data > /etc/somefile"

# 22. /proc/self/fd is in default allow list
run_test "/proc/self/fd passes (default allow)" 0 \
  "cat /proc/self/fd/0"

# 23. Trailing slash on outside path — BLOCK
run_test "trailing-slash outside path blocks" 2 "ls /home/user/"

# 24. Quoted absolute path outside — BLOCK (after quote strip)
run_test "quoted outside path blocks" 2 \
  "cat \"/var/log/secure\""

# 25. Path with .. that resolves outside — BLOCK
run_test "../traversal to outside blocks" 2 \
  "cat ${PROJECT_ROOT}/../../../etc/passwd"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
