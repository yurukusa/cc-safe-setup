#!/bin/bash
# Tests for compound-command-deny-enforcer.sh
HOOK="$(dirname "$0")/../examples/compound-command-deny-enforcer.sh"
PASS=0 FAIL=0

run_test() {
    local desc="$1" expected_exit="$2" command="$3"
    local actual_exit
    echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(printf '%s' "$command" | jq -R .)}}" \
        | bash "$HOOK" >/dev/null 2>/dev/null
    actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        ((FAIL++))
    fi
}

echo "Testing compound-command-deny-enforcer.sh"
echo "========================================="

# === The 9 patterns the #59498 reporter tested (settings.json variants) ===
# All should be blocked by this hook regardless of settings.json pattern format.

run_test "cd /different && git push (the #59498 bug)"    2 "cd /tmp && git push"
run_test "cd /different && git push --dry-run"            2 "cd /tmp && git push --dry-run"
run_test "echo test && git push (non-cd compound)"        2 "echo test && git push"
run_test "echo test ; git push (semicolon compound)"      2 "echo test ; git push"
run_test "echo test || git push (or compound)"            2 "echo a || git push"
run_test "cd quoted-path && git push"                     2 'cd "/path with space" && git push'
run_test "cd \$HOME && git push"                          2 'cd $HOME && git push'

# === Other irreversible operations ===

run_test "cd && rm -rf /tmp/foo"                          2 "cd /tmp && rm -rf /tmp/foo"
run_test "cd && git reset --hard HEAD~1"                  2 "cd /tmp && git reset --hard HEAD~1"
run_test "cd && git clean -fd"                            2 "cd /tmp && git clean -fd"
run_test "cd && git filter-repo --path foo"               2 "cd /tmp && git filter-repo --path foo"
run_test "cd && git filter-branch"                        2 "cd /tmp && git filter-branch"
run_test "cd && dd if=/foo of=/bar"                       2 "cd /tmp && dd if=/foo of=/bar"
run_test "cd && mkfs.ext4 /dev/sdb"                       2 "cd /tmp && mkfs.ext4 /dev/sdb"
run_test "cat foo > /dev/sda"                             2 "cat foo > /dev/sda"

# === Safe commands that must pass ===

run_test "simple ls"                                      0 "ls"
run_test "cd /tmp && ls"                                  0 "cd /tmp && ls"
run_test "cd /tmp && git status"                          0 "cd /tmp && git status"
run_test "cd /tmp && git log --oneline"                   0 "cd /tmp && git log --oneline"
run_test "cd /tmp && npm test"                            0 "cd /tmp && npm test"
run_test "cd /tmp && cat foo.txt"                         0 "cd /tmp && cat foo.txt"
run_test "echo hello && echo world"                       0 "echo hello && echo world"
run_test "cd /tmp ; ls -la ; pwd"                         0 "cd /tmp ; ls -la ; pwd"

# === Edge cases ===

run_test "empty command (no opinion)"                     0 ""
run_test "git pushes (substring of git push but not the cmd)" 0 "git pushes-table-status"
run_test "git push-foo (extension cmd)"                   0 "git push-foo --help"
run_test "deeply nested cd && cd && git push"             2 "cd /a && cd /b && git push"
run_test "cd && safe && git push"                         2 "cd /tmp && ls && git push"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
