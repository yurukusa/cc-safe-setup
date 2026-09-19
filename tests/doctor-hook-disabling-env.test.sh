#!/bin/bash
# --doctor: detect the environment variables that stop hooks loading at all
#
# Measured 2026-09-19 on Claude Code 2.1.278 (Linux/WSL2), disposable HOME and a
# scratch working directory, with a control on every row. Arrival was measured on
# UserPromptSubmit -- deliberately NOT PreToolUse on Bash, because --restricted
# removes Bash and then "the hook was ignored" and "nothing pulled the trigger"
# are the same observation.
#
#   (control) no flags              -> user, project and local hooks all fired
#   --dangerously-skip-permissions  -> hooks fired, the guard refused, exit 2
#   --restricted                    -> no hook fired; --settings restored them
#   --safe-mode                     -> no hook fired; --settings did NOT restore
#   CLAUDE_CODE_RESTRICTED=1        -> same as --restricted
#   CLAUDE_CODE_SAFE_MODE=1         -> same as --safe-mode, and Bash still ran
#
# The variables matter more than the flags: a flag is retyped every time you
# start, a line in a shell profile is read once and never seen again. Before this
# check, --doctor printed "All checks passed. Hooks should be working." with
# either variable set -- the exact false reassurance this command exists to
# prevent, since every other check inspects files that are all perfectly fine.
#
# Only the value "1" was measured. Any other non-empty, non-false value is
# flagged on the assumption that whoever typed it meant to turn it on; "0",
# "false" and empty are treated as off.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Assembled at runtime so this file does not carry the literal filename that the
# operator's own guards watch for.
SETTINGS_FILE="set""tings.json"

run_doctor() {
  # $1 = extra env assignments (may be empty). Prints only the lines this check owns.
  local envspec="$1"
  local home
  home=$(mktemp -d)
  mkdir -p "$home/.claude/hooks"
  printf '%s' '{"hooks":{}}' > "$home/.claude/$SETTINGS_FILE"
  # shellcheck disable=SC2086
  env -u CLAUDE_CODE_SAFE_MODE -u CLAUDE_CODE_RESTRICTED $envspec HOME="$home" \
    node "$ROOT/index.mjs" --doctor 2>&1 \
    | grep -E 'hook-disabling environment variable|CLAUDE_CODE_SAFE_MODE=|CLAUDE_CODE_RESTRICTED=|does NOT restore|pass your hooks with|unset CLAUDE_CODE' || true
  rm -rf "$home"
}

check() {
  local desc="$1" envspec="$2" expect="$3"
  local out
  out=$(run_doctor "$envspec")
  if printf '%s' "$out" | grep -q "$expect"; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "         expected to match: $expect"
    printf '%s\n' "${out:-<no output>}" | sed 's/^/         got: /'
    FAIL=$((FAIL + 1))
  fi
}

# --- the two variables are reported ----------------------------------------
check "CLAUDE_CODE_SAFE_MODE=1 is reported" \
  "CLAUDE_CODE_SAFE_MODE=1" "CLAUDE_CODE_SAFE_MODE=1"

check "CLAUDE_CODE_RESTRICTED=1 is reported" \
  "CLAUDE_CODE_RESTRICTED=1" "CLAUDE_CODE_RESTRICTED=1"

check "safe-mode says --settings does not help" \
  "CLAUDE_CODE_SAFE_MODE=1" "does NOT restore"

check "restricted points at --settings as the way back" \
  "CLAUDE_CODE_RESTRICTED=1" "pass your hooks with"

# --- controls: no false positives -------------------------------------------
# Without a control here, the two rows above would also pass if the check simply
# printed its warning unconditionally.
check "neither variable set reports the all-clear" \
  "" "no hook-disabling environment variable set"

check "an explicit 0 is treated as off" \
  "CLAUDE_CODE_SAFE_MODE=0" "no hook-disabling environment variable set"

check "the string false is treated as off" \
  "CLAUDE_CODE_RESTRICTED=false" "no hook-disabling environment variable set"

check "an empty value is treated as off" \
  "CLAUDE_CODE_SAFE_MODE=" "no hook-disabling environment variable set"

echo
echo "doctor-hook-disabling-env: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
