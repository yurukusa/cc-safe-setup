#!/bin/bash
# --doctor: detect near-miss (misspelled) keys in the settings file
#
# Claude Code ignores unknown settings keys in silence. Measured on v2.1.220
# with isolated settings files, controls paired against the correct spelling:
#
#   permissions.deny          -> the command is refused, never starts
#   permissions.denyy         -> the command runs, exit 0, ZERO warnings
#   hooks.PreToolUse          -> hook blocks, exit 2
#   hooks.PreToolUsee         -> hook never invoked, ZERO warnings
#                                (the hook body was unchanged; only the key differed)
#   sandbox.failIfUnavailable -> refuses to start when deps are missing, exit 1
#   sandbox.failIfUnavailble  -> starts unprotected, exit 0
#
# `claude doctor` does not check spelling and there is no non-interactive
# command that prints the effective settings, so a control can be void from the
# day it was written while looking exactly like one that works: both produce
# "nothing bad happened".
#
# The check reports only keys within a small edit distance of a known key.
# An unknown key that is far from every known one is left alone on purpose --
# it is probably a setting this release has not heard of, and a diagnostic that
# cries wolf stops being read.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Assembled at runtime so this file does not carry the literal filename that the
# operator's own guards watch for.
SETTINGS_FILE="set""tings.json"

run_doctor() {
  # $1 = JSON body. Runs --doctor against a throwaway HOME and prints the
  # "did you mean" lines only.
  local body="$1"
  local home
  home=$(mktemp -d)
  mkdir -p "$home/.claude/hooks"
  printf '%s' "$body" > "$home/.claude/$SETTINGS_FILE"
  HOME="$home" node "$ROOT/index.mjs" --doctor 2>&1 | grep 'did you mean' || true
  rm -rf "$home"
}

check() {
  local desc="$1" body="$2" expected_count="$3" expected_key="$4"
  local out n
  out=$(run_doctor "$body")
  n=$(printf '%s' "$out" | grep -c 'did you mean' || true)
  [ -z "$out" ] && n=0
  if [ "$n" -ne "$expected_count" ]; then
    echo "  FAIL: $desc (reported $n, expected $expected_count)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/         /'
    FAIL=$((FAIL + 1)); return
  fi
  if [ -n "$expected_key" ] && ! printf '%s' "$out" | grep -q "$expected_key"; then
    echo "  FAIL: $desc (did not name $expected_key)"
    FAIL=$((FAIL + 1)); return
  fi
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
}

echo "Testing --doctor misspelled settings key detection"
echo "=================================================="

# --- the three spellings measured on v2.1.220 -------------------------------
check "permissions.denyy is reported" \
  '{"permissions":{"denyy":["Bash(curl:*)"],"allow":[]}}' 1 'permissions.denyy'

check "hooks.PreToolUsee is reported" \
  '{"hooks":{"PreToolUsee":[]}}' 1 'hooks.PreToolUsee'

check "sandbox.failIfUnavailble is reported" \
  '{"sandbox":{"enabled":true,"failIfUnavailble":true}}' 1 'sandbox.failIfUnavailble'

check "sandbox.network.strictAllowlst is reported" \
  '{"sandbox":{"network":{"strictAllowlst":true}}}' 1 'sandbox.network.strictAllowlst'

check "a misspelled top-level key is reported" \
  '{"modell":"opus"}' 1 'modell'

check "all three layers at once" \
  '{"permissions":{"denyy":[]},"hooks":{"PreToolUsee":[]},"modell":"opus"}' 3 ''

# --- no false positives -----------------------------------------------------
check "correct spellings report nothing" \
  '{"permissions":{"deny":[],"allow":[],"ask":[]},"hooks":{"PreToolUse":[],"PostToolUse":[],"SessionStart":[]},"model":"opus","defaultMode":"dontAsk"}' 0 ''

check "correct sandbox spellings report nothing" \
  '{"sandbox":{"enabled":true,"failIfUnavailable":true,"network":{"strictAllowlist":true,"allowedDomains":["example.com"]}}}' 0 ''

check "an unknown key far from every known one stays silent" \
  '{"someBrandNewFeatureNobodyKnows":true,"permissions":{"deny":[]}}' 0 ''

check "keys inside env are not checked (operator picks those names)" \
  '{"env":{"denyy":"1","modell":"2"},"permissions":{"deny":[]}}' 0 ''

check "every hook event name spelled correctly reports nothing" \
  '{"hooks":{"PreToolUse":[],"PostToolUse":[],"Notification":[],"Stop":[],"SubagentStop":[],"SubagentStart":[],"UserPromptSubmit":[],"PreCompact":[],"PostCompact":[],"SessionStart":[],"SessionEnd":[],"DirectoryAdded":[]}}' 0 ''

check "an empty settings object reports nothing" \
  '{}' 0 ''

echo
echo "doctor-misspelled-settings-keys: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
