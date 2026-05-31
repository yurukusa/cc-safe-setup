#!/bin/bash
# test-cliff-countdown-advisor.sh
#
# Tests for cliff-countdown-advisor.sh hook
# Exercises all five time windows (acute, elevated, caution, quiet-far, post-cliff)
# plus the opt-out paths.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../examples/cliff-countdown-advisor.sh"

pass_count=0
fail_count=0

assert_contains() {
  local description="$1"
  local actual="$2"
  local expected_substring="$3"
  if [[ "${actual}" == *"${expected_substring}"* ]]; then
    pass_count=$((pass_count + 1))
    echo "PASS: ${description}"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: ${description}"
    echo "  expected substring: ${expected_substring}"
    echo "  actual: ${actual}"
  fi
}

assert_empty() {
  local description="$1"
  local actual="$2"
  if [[ -z "${actual}" ]]; then
    pass_count=$((pass_count + 1))
    echo "PASS: ${description}"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: ${description}"
    echo "  expected empty output"
    echo "  actual: ${actual}"
  fi
}

# Test 1: ~14 days before cliff (elevated advisory)
output=$(CC_CLIFF_DATE="$(date -d '14 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "14 days from now: elevated advisory marker present" "${output}" "⚠"
assert_contains "14 days from now: Pool 2 reduction mentioned" "${output}" "Pool 2"
assert_contains "14 days from now: 14-day plan referenced" "${output}" "14-day-plan"

# Test 2: ~7 days before cliff (still elevated)
output=$(CC_CLIFF_DATE="$(date -d '7 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "7 days from now: elevated marker present" "${output}" "days until"
assert_contains "7 days from now: spend limit mentioned" "${output}" "Spend Limit"

# Test 3: ~1 day from now (cliff day boundary, integer-division puts this at 0 days)
output=$(CC_CLIFF_DATE="$(date -d '1 day' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "1 day from now: cliff day boundary advisory" "${output}" "Anthropic Console Usage snapshot"

# Test 4: cliff day exactly (acute)
output=$(CC_CLIFF_DATE="$(date +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "cliff day: acute marker present" "${output}" "cliff day"
assert_contains "cliff day: measurement priority mentioned" "${output}" "Anthropic Console Usage snapshot"

# Test 5: ~20 days before cliff (caution single-line, with integer-division tolerance)
output=$(CC_CLIFF_DATE="$(date -d '20 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "20 days from now: caution single-line marker" "${output}" "days until"
assert_contains "20 days from now: baseline capture mentioned" "${output}" "baseline capture"

# Test 6: ~25 days before cliff (still caution)
output=$(CC_CLIFF_DATE="$(date -d '25 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "25 days from now: caution marker" "${output}" "billing cliff"

# Test 7: 60 days before cliff (quiet)
output=$(CC_CLIFF_DATE="$(date -d '60 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_empty "60 days before cliff: quiet output" "${output}"

# Test 8: 35 days before cliff (well past caution window, quiet)
output=$(CC_CLIFF_DATE="$(date -d '35 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_empty "35 days before cliff: quiet" "${output}"

# Test 9: 5 days after cliff (post-cliff diff capture advisory)
output=$(CC_CLIFF_DATE="$(date -d '-5 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "5 days after cliff: post-cliff marker" "${output}" "Day 5 after"
assert_contains "5 days after cliff: diff capture mentioned" "${output}" "diff vs pre-cliff"

# Test 10: 20 days after cliff (still post-cliff window)
output=$(CC_CLIFF_DATE="$(date -d '-20 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_contains "20 days after cliff: post-cliff marker" "${output}" "Day 20 after"

# Test 11: 31 days after cliff (silent again)
output=$(CC_CLIFF_DATE="$(date -d '-31 days' +%Y-%m-%d)" bash "${HOOK}" 2>&1)
assert_empty "31 days after cliff: quiet" "${output}"

# Test 12: CC_CLIFF_QUIET=1 silences output (override elevated window)
output=$(CC_CLIFF_DATE="$(date -d '7 days' +%Y-%m-%d)" CC_CLIFF_QUIET=1 bash "${HOOK}" 2>&1)
assert_empty "CC_CLIFF_QUIET=1: elevated window silenced" "${output}"

# Test 13: CC_CLIFF_DISABLE=1 silences output
output=$(CC_CLIFF_DATE="$(date -d '7 days' +%Y-%m-%d)" CC_CLIFF_DISABLE=1 bash "${HOOK}" 2>&1)
assert_empty "CC_CLIFF_DISABLE=1: silences output" "${output}"

# Test 14: hook exits 0 even on cliff day (advisory, never blocks)
CC_CLIFF_DATE="$(date +%Y-%m-%d)" bash "${HOOK}" > /dev/null 2>&1
exit_code=$?
if [[ ${exit_code} -eq 0 ]]; then
  pass_count=$((pass_count + 1))
  echo "PASS: cliff day exits 0 (non-blocking advisory)"
else
  fail_count=$((fail_count + 1))
  echo "FAIL: cliff day exit code ${exit_code} (expected 0)"
fi

# Test 15: invalid date format degrades gracefully (silent)
output=$(CC_CLIFF_DATE="not-a-date" bash "${HOOK}" 2>&1)
assert_empty "invalid CC_CLIFF_DATE: silent" "${output}"

# Test 16: default cliff date (2026-06-15) — verify hook references correct date in elevated window
# Skip this test if today is too far from 2026-06-15 to fall in any active window.
default_diff=$(( ($(date -d '2026-06-15' +%s) - $(date +%s)) / 86400 ))
if [[ ${default_diff} -ge 1 ]] && [[ ${default_diff} -le 30 ]]; then
  output=$(bash "${HOOK}" 2>&1)
  assert_contains "default cliff date (2026-06-15) referenced when in active window" "${output}" "2026-06-15"
else
  echo "SKIP: default cliff date test (today is ${default_diff} days from cliff, outside active window)"
fi

echo ""
echo "=========================================="
echo "Tests run: $((pass_count + fail_count))"
echo "Passed: ${pass_count}"
echo "Failed: ${fail_count}"
echo "=========================================="

if [[ ${fail_count} -gt 0 ]]; then
  exit 1
fi
exit 0
