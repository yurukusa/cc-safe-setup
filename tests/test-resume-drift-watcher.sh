#!/bin/bash
# Tests for resume-drift-watcher.sh
HOOK="examples/resume-drift-watcher.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

LOG="${HOME}/.claude/logs/resume-drift.log"
mkdir -p "${HOME}/.claude/logs"
: > "$LOG"

# Test 1: No transcript — exit 0, no log line
OUT=$(printf '{"session_id":"s1","tool_name":"X"}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no transcript exits 0" "$RC" 0

# Test 2: Healthy fresh session — first message large, no warning
TRANS=$(mktemp)
{
  printf '{"role":"user","content":"This is a reasonably sized first message with enough bytes to be well above 500. Adding filler: %s"}\n' "$(printf 'x%.0s' {1..600})"
  printf '{"role":"assistant","content":"reply"}\n'
  printf '{"role":"user","content":"follow up"}\n'
  printf '{"role":"assistant","content":"reply 2"}\n'
  printf '{"role":"user","content":"turn 3"}\n'
  printf '{"role":"assistant","content":"reply 3"}\n'
} >> "$TRANS"
: > "$LOG"
OUT=$(printf '{"session_id":"healthy","transcript_path":"%s"}' "$TRANS" | bash "$HOOK" 2>&1)
assert_not_contains "healthy session no warning" "$OUT" "resume-drift signal"
if grep -q "healthy" "$LOG"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: healthy session should log"; fi
rm -f "$TRANS"

# Test 3: Drift signal — tiny first message + large total + >4 turns
TRANS=$(mktemp)
printf '{"role":"user","content":"tiny"}\n' >> "$TRANS"           # <500 bytes
# Pad total size above 50KB using large assistant messages
for i in 1 2 3 4 5; do
  printf '{"role":"assistant","content":"%s"}\n' "$(printf 'A%.0s' {1..12000})" >> "$TRANS"
  printf '{"role":"user","content":"t%d"}\n' "$i" >> "$TRANS"
done
: > "$LOG"
OUT=$(printf '{"session_id":"drifted","transcript_path":"%s"}' "$TRANS" | bash "$HOOK" 2>&1)
assert_contains "drift emits warning" "$OUT" "resume-drift signal"
assert_contains "warning references issue" "$OUT" "#43278"
rm -f "$TRANS"

# Test 4: Under turn-count threshold — no warning even if first small
TRANS=$(mktemp)
printf '{"role":"user","content":"tiny"}\n' >> "$TRANS"
printf '{"role":"assistant","content":"%s"}\n' "$(printf 'A%.0s' {1..60000})" >> "$TRANS"
: > "$LOG"
OUT=$(printf '{"session_id":"early","transcript_path":"%s"}' "$TRANS" | bash "$HOOK" 2>&1)
assert_not_contains "early turns no warning" "$OUT" "resume-drift signal"
rm -f "$TRANS"

# Test 5: TSV format — 5 fields
if [ -s "$LOG" ]; then
  FIELDS=$(awk -F'\t' '{print NF}' "$LOG" | head -1)
  if [ "$FIELDS" = "5" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 5 TSV fields, got $FIELDS"; fi
fi

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
