#!/bin/bash
# Tests for windows-destructive-command-guard.sh — verifies
# detection of Windows-side destructive command shapes from the
# #56603 incident's escalation chain.
HOOK="examples/windows-destructive-command-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

make_input() {
  jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'
}

# Test 1: the #56603 terminal command exact pattern → blocked
CMD='cmd /c "rd /s /q \"D:\★zRC With Claude\.claude\worktrees\foo\""'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "#56603 terminal pattern blocked" "$RC" 2
assert_contains "block message present" "$OUT" "BLOCKED"
assert_contains "block names rd_recursive_quiet" "$OUT" "rd_recursive_quiet"
assert_contains "block names cmd_c_destructive" "$OUT" "cmd_c_destructive"
assert_contains "block references #56603" "$OUT" "#56603"

# Test 2: Remove-Item -Recurse -Force (#56603 escalation step 4) → blocked
CMD='Remove-Item -Recurse -Force "D:\worktree\foo"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Remove-Item -Recurse -Force blocked" "$RC" 2
assert_contains "Remove-Item pattern detected" "$OUT" "remove_item_recurse_force"

# Test 3: rd /s /q standalone (without cmd /c) → blocked
CMD='rd /s /q "C:\Users\foo\bar"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "rd /s /q standalone blocked" "$RC" 2
assert_contains "rd recursive detected" "$OUT" "rd_recursive_quiet"

# Test 4: del /s /q recursive → blocked
CMD='del /s /q "D:\old\*.tmp"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "del /s /q blocked" "$RC" 2
assert_contains "del recursive detected" "$OUT" "del_recursive_quiet"

# Test 5: Format-Volume → blocked (disk level)
CMD='Format-Volume -DriveLetter D -FileSystem NTFS'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Format-Volume blocked" "$RC" 2
assert_contains "disk-level pattern detected" "$OUT" "disk_level_destructive"

# Test 6: Remove-Item without -Recurse → not blocked (single-file is safe)
CMD='Remove-Item "C:\foo\bar.txt"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "single-file Remove-Item not blocked" "$RC" 0
assert_not_contains "single-file no warning" "$OUT" "BLOCKED"

# Test 7: cmd /c without destructive primitive → not blocked
CMD='cmd /c "echo hello"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "cmd /c echo not blocked" "$RC" 0
assert_not_contains "cmd /c echo no warning" "$OUT" "BLOCKED"

# Test 8: not a Bash tool → exit silently
INPUT=$(jq -n '{tool_name: "Read", tool_input: {file_path: "/tmp/foo"}}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "non-Bash tool exits 0" "$RC" 0
assert_not_contains "non-Bash tool no warning" "$OUT" "BLOCKED"

# Test 9: empty command → exit silently
INPUT=$(jq -n '{tool_name: "Bash", tool_input: {command: ""}}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty command exits 0" "$RC" 0

# Test 10: warn-only mode — destructive command produces warning, exit 0
CMD='cmd /c "rd /s /q D:\foo"'
INPUT=$(make_input "$CMD")
OUT=$(WINDOWS_DESTRUCTIVE_BLOCK=0 bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$INPUT" 2>&1)
RC=$?
assert_exit "warn-only mode exits 0" "$RC" 0
assert_contains "warn-only mode produces WARNING" "$OUT" "WARNING"

# Test 11: drive-root target risk note flagged
CMD='Remove-Item -Recurse -Force "D:\"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "drive-root target blocked" "$RC" 2
assert_contains "drive-root risk noted" "$OUT" "drive_root_target"

# Test 12: case-insensitive detection (RD vs rd)
CMD='RD /S /Q "C:\old"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "uppercase RD blocked" "$RC" 2
assert_contains "uppercase RD detected" "$OUT" "rd_recursive_quiet"

# Test 13: rmdir alias for rd
CMD='rmdir /s /q "C:\old"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "rmdir blocked" "$RC" 2
assert_contains "rmdir detected" "$OUT" "rd_recursive_quiet"

# Test 14: Remove-Item -Recurse without -Force → not blocked (less risky)
CMD='Remove-Item -Recurse "C:\old"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Recurse without Force not blocked" "$RC" 0
assert_not_contains "Recurse without Force no warning" "$OUT" "BLOCKED"

# Test 15: POSIX rm -rf — not in scope (covered by separate hook)
CMD='rm -rf /tmp/foo'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "POSIX rm -rf not blocked by Windows hook" "$RC" 0
assert_not_contains "POSIX rm -rf out of scope" "$OUT" "BLOCKED"

# Test 16: block message includes safer-alternatives guidance
CMD='cmd /c "rd /s /q D:\foo"'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
assert_contains "guidance includes Remove-Item LiteralPath" "$OUT" "LiteralPath"
assert_contains "guidance mentions stopping for locked worktrees" "$OUT" "locked"

# Test 17: Clear-Disk → blocked
CMD='Clear-Disk -Number 0 -RemoveData'
INPUT=$(make_input "$CMD")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Clear-Disk blocked" "$RC" 2
assert_contains "Clear-Disk disk-level detected" "$OUT" "disk_level_destructive"

# Summary
echo
echo "=== windows-destructive-command-guard tests: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
