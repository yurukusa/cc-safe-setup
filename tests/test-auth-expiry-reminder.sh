#!/bin/bash
# Tests for auth-expiry-reminder.sh
HOOK="$(dirname "$0")/../examples/auth-expiry-reminder.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
STATE="$TMPDIR/state"

reset_state() {
  rm -rf "$STATE"
  mkdir -p "$STATE"
  unset CC_AUTH_EXPIRY_REMINDER_REMIND
  unset CC_AUTH_EXPIRY_REMINDER_DISABLE
  unset CC_AUTH_EXPIRY_REMINDER_QUIET
  unset CC_AUTH_EXPIRY_REMINDER_DATE
}

echo "Testing auth-expiry-reminder.sh"
echo "================================"

# Test 1: Default (no env vars) → silent
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Default (no env vars) is silent" pass
else
  run_test "Default (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: REMIND=1 fires on first invocation of the day
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "auth-expiry-reminder"; then
  run_test "REMIND=1 fires on first invocation of the day" pass
else
  run_test "First invocation (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: Second invocation on the same day is silent (one-shot per day)
reset_state
CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>/dev/null  # First fire
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Second invocation same day is silent (one-shot per day)" pass
else
  run_test "Same-day repeat (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: Next day fires again
reset_state
CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>/dev/null  # Day 1 fire
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-31" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "auth-expiry-reminder"; then
  run_test "Next day fires again" pass
else
  run_test "Next day (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: DISABLE=1 silences even when REMIND=1
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_DISABLE=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences (overrides REMIND)" pass
else
  run_test "DISABLE (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: QUIET=1 silences even when REMIND=1
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_QUIET=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences (overrides REMIND)" pass
else
  run_test "QUIET (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: REMIND=0 → silent
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=0 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=0 is silent" pass
else
  run_test "REMIND=0 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 8: Advisory includes today's date in the header
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "2026-05-30"; then
  run_test "Advisory includes today's date" pass
else
  run_test "Date in advisory (out_len=${#OUT})" fail
fi

# Test 9: Advisory names the two checkpoint commands
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
HAS1=$(printf '%s' "$OUT" | grep -c "1) Anthropic auth surface")
HAS2=$(printf '%s' "$OUT" | grep -c "2) Third-party credential chains")
if [ "$HAS1" -ge "1" ] && [ "$HAS2" -ge "1" ]; then
  run_test "Advisory names both checkpoint commands" pass
else
  run_test "Two checkpoints (1=$HAS1 2=$HAS2)" fail
fi

# Test 10: Advisory cites the HIGH BLOCKER issue (#62354)
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "62354"; then
  run_test "Advisory cites #62354 HIGH BLOCKER" pass
else
  run_test "Cites #62354 (out_len=${#OUT})" fail
fi

# Test 11: Advisory cites the fresh issue (#63919) and the 3P SSO issue (#63185)
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "63919" && printf '%s' "$OUT" | grep -q "63185"; then
  run_test "Advisory cites #63919 (fresh) and #63185 (3P SSO)" pass
else
  run_test "Cites #63919 and #63185 (out_len=${#OUT})" fail
fi

# Test 12: State file is stamped with today's date
reset_state
CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>/dev/null
STAMP=$(head -1 "$STATE/auth-expiry-reminder.last" 2>/dev/null)
if [ "$STAMP" = "2026-05-30" ]; then
  run_test "State file is stamped with today's date" pass
else
  run_test "State stamp (stamp=$STAMP)" fail
fi

# Test 13: State dir auto-created when missing
reset_state
NEW_STATE="$TMPDIR/state-fresh"
[ -d "$NEW_STATE" ] && rmdir "$NEW_STATE"
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$NEW_STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -d "$NEW_STATE" ] && [ -f "$NEW_STATE/auth-expiry-reminder.last" ]; then
  run_test "State dir auto-created when missing" pass
else
  run_test "Auto-create (exit=$EXIT, dir_exists=$([ -d "$NEW_STATE" ] && echo y || echo n))" fail
fi

# Test 14: Advisory references the field guide gist
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "gist.github.com"; then
  run_test "Advisory references the field guide gist" pass
else
  run_test "Field guide link (out_len=${#OUT})" fail
fi

# Test 15: Advisory cross-references companion hook (auth-status-checker)
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "auth-status-checker"; then
  run_test "Advisory cross-references auth-status-checker companion hook" pass
else
  run_test "Companion hook link (out_len=${#OUT})" fail
fi

# Test 16: Advisory explains how to disable
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "unset CC_AUTH_EXPIRY_REMINDER_REMIND" \
   && printf '%s' "$OUT" | grep -q "export CC_AUTH_EXPIRY_REMINDER_QUIET=1"; then
  run_test "Advisory explains how to disable" pass
else
  run_test "Disable instructions (out_len=${#OUT})" fail
fi

# Test 17: Never blocks — exit 0 when firing
reset_state
CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when firing)" pass
else
  run_test "Exit on fire (exit=$EXIT)" fail
fi

# Test 18: Never blocks — exit 0 when silent
reset_state
CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when silent)" pass
else
  run_test "Exit when silent (exit=$EXIT)" fail
fi

# Test 19: Calendar-day boundary across midnight (23:55 → 00:05)
reset_state
CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>/dev/null  # 23:55 on day 1
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-31" \
  bash "$HOOK" 2>&1)  # 00:05 on day 2
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "2026-05-31"; then
  run_test "Calendar-day boundary fires next-day reminder" pass
else
  run_test "Midnight boundary (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 20: Advisory mentions the calendar-day cadence
reset_state
OUT=$(CC_AUTH_EXPIRY_REMINDER_REMIND=1 \
  CC_AUTH_EXPIRY_REMINDER_STATE_DIR="$STATE" \
  CC_AUTH_EXPIRY_REMINDER_DATE="2026-05-30" \
  bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "once per calendar day"; then
  run_test "Advisory mentions once-per-calendar-day cadence" pass
else
  run_test "Cadence framing (out_len=${#OUT})" fail
fi

echo "================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
