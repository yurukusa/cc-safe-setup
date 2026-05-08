#!/bin/bash
# Tests for subagent-boundary-precheck.sh — verifies the four-axis
# boundary-declaration detection against representative Task prompts.
HOOK="examples/subagent-boundary-precheck.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

make_input() {
  jq -n --arg p "$1" '{tool_name: "Task", tool_input: {prompt: $p}}'
}

# Test 1: well-formed prompt with all four axes → no warning
PROMPT='You are a sub-agent. Stay in working directory ./src and only edit files matching *.ts. Do not modify parent settings.json. Report back when done.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "well-formed prompt exits 0" "$RC" 0
assert_not_contains "well-formed prompt no warning" "$OUT" "WARNING"

# Test 2: missing all four axes → warning lists 4 missing
PROMPT='Find the bug and fix it.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "bare prompt exits 0 in warn-only" "$RC" 0
assert_contains "bare prompt warns" "$OUT" "WARNING"
assert_contains "bare prompt counts 4 missing" "$OUT" "4 of 4"
assert_contains "bare prompt mentions cluster" "$OUT" "#55488"

# Test 3: only work_directory present → 3 missing
PROMPT='Stay in ./src. Find the bug.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "partial prompt exits 0" "$RC" 0
assert_contains "partial prompt counts 3 missing" "$OUT" "3 of 4"
assert_not_contains "work_directory not in missing list" "$OUT" "work_directory "

# Test 4: only file_pattern present → 3 missing
PROMPT='Only edit files matching *.md.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "file_pattern detected, others missing" "$OUT" "3 of 4"
assert_not_contains "file_pattern not in missing list" "$OUT" "file_pattern "

# Test 5: only settings prohibition present → 3 missing
PROMPT='Do not edit parent settings.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "settings prohibition detected, others missing" "$OUT" "3 of 4"
assert_not_contains "settings_prohibition not in missing list" "$OUT" "settings_prohibition "

# Test 6: only identity role present → 3 missing
PROMPT='You are a sub-agent. Report back the findings.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "identity role detected, others missing" "$OUT" "3 of 4"
assert_not_contains "identity_role not in missing list" "$OUT" "identity_role "

# Test 7: not a Task tool → exit silently
INPUT=$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "non-Task tool exits 0" "$RC" 0
assert_not_contains "non-Task tool no warning" "$OUT" "WARNING"

# Test 8: empty prompt → exit silently
INPUT=$(jq -n '{tool_name: "Task", tool_input: {prompt: ""}}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty prompt exits 0" "$RC" 0
assert_not_contains "empty prompt no warning" "$OUT" "WARNING"

# Test 9: missing prompt field → exit silently
INPUT=$(jq -n '{tool_name: "Task", tool_input: {}}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing prompt exits 0" "$RC" 0
assert_not_contains "missing prompt no warning" "$OUT" "WARNING"

# Test 10: block mode with missing axes → exit 2
PROMPT='Find and fix the bug.'
INPUT=$(make_input "$PROMPT")
OUT=$(SUBAGENT_BOUNDARY_BLOCK=1 bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$INPUT" 2>&1)
RC=$?
assert_exit "block mode exits 2" "$RC" 2
assert_contains "block message present" "$OUT" "BLOCKED"
assert_contains "block lists axes" "$OUT" "work_directory"

# Test 11: block mode with full prompt → exit 0
PROMPT='You are a sub-agent. Stay in ./src and only edit files matching *.ts. Do not modify parent settings.json. Report back.'
INPUT=$(make_input "$PROMPT")
OUT=$(SUBAGENT_BOUNDARY_BLOCK=1 bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$INPUT" 2>&1)
RC=$?
assert_exit "block mode with full prompt exits 0" "$RC" 0
assert_not_contains "block mode with full prompt no block" "$OUT" "BLOCKED"

# Test 12: alternative phrasings for work directory ("scope:")
PROMPT='Scope: ./tests directory only. File pattern: *.test.ts. No settings.json edits. Sub-agent: report findings.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "alternative phrasings exit 0" "$RC" 0
assert_not_contains "alternative phrasings no warning" "$OUT" "WARNING"

# Test 13: alternative phrasings for identity ("delegated agent")
PROMPT='As a delegated agent, work in ./docs only. Edit only *.md files. Settings.json off-limits. Return your results.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "delegated phrasing exits 0" "$RC" 0
assert_not_contains "delegated phrasing no warning" "$OUT" "WARNING"

# Test 14: investigation-only phrasing
PROMPT='Investigation only: scan files in ./logs. Read-only investigation. Files matching *.log allowed. Do not change settings. Report what you find.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "investigation phrasing exits 0" "$RC" 0
assert_not_contains "investigation phrasing no warning" "$OUT" "WARNING"

# Test 15: warning includes remediation guidance
PROMPT='Just do it.'
INPUT=$(make_input "$PROMPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
assert_contains "warning includes remediation" "$OUT" "add explicit declarations"

# Summary
echo
echo "=== subagent-boundary-precheck tests: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
