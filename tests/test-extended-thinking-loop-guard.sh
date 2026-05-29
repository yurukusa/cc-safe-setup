#!/bin/bash
# Tests for extended-thinking-loop-guard.sh (Cluster 13 Axis A, opt-in BLOCK)
# Covers: opt-in gating, event filtering, source filtering, transcript
#         pattern detection, blocking semantics (exit 2 + decision JSON),
#         threshold, kill switch, fail-open paths.

HOOK="examples/extended-thinking-loop-guard.sh"
PASS=0 FAIL=0

TEST_HOME=$(mktemp -d)
TEST_TRANSCRIPT_DIR="$TEST_HOME/transcripts"
mkdir -p "$TEST_TRANSCRIPT_DIR"
trap 'rm -rf "$TEST_HOME"' EXIT

write_transcript() {
    local f="$TEST_TRANSCRIPT_DIR/$1"; shift
    : > "$f"
    for line in "$@"; do
        printf '%s\n' "$line" >> "$f"
    done
    echo "$f"
}

run_hook() {
    local payload="$1"; shift
    HOME="$TEST_HOME" env "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  got: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Transcript line fixtures
empty_signed_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"sigABCDEF1234567890"}]}}'
empty_signed_line2='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"longerSignatureFFFF1234"}]}}'
empty_signed_line3='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"sigZZZZ"}]}}'
normal_thinking_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"reasoning text here","signature":"sigABCDEF"}]}}'
no_signature_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":""}]}}'
text_only_line='{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}'
user_line='{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}'

# ---- Group 1: opt-in gating (THE primary safety property) ----

# Test 1: env var not set → silent exit 0 even with precursor present
F=$(write_transcript "1.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "default-disabled exit 0" "$RC" "0"
assert_not_contains "default-disabled silent" "$OUT" "BLOCK"
assert_not_contains "default-disabled no decision" "$OUT" "decision"

# Test 2: env var set to anything other than "1" → still off
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=0 CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "enabled=0 stays off" "$RC" "0"
assert_not_contains "enabled=0 silent" "$OUT" "BLOCK"

# Test 3: env var set to "true" (not "1") → off (strict equality)
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=true CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "enabled=true stays off" "$RC" "0"

# Test 4: enabled + precursor → BLOCK (exit 2)
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "armed + precursor exit 2" "$RC" "2"
assert_contains "armed emits decision block" "$OUT" '"decision":"block"'
assert_contains "armed cites cluster 13A" "$OUT" "Cluster 13A precursor"

# Test 5: kill switch wins over enable
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_DISABLE=1 CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "kill switch beats enable" "$RC" "0"
assert_not_contains "kill switch silent" "$OUT" "BLOCK"

# ---- Group 2: event filtering ----

# Test 6: non-SessionStart event → exit 0 even when armed
OUT=$(run_hook '{"event":"Stop"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "non-SessionStart exit 0" "$RC" "0"
assert_not_contains "non-SessionStart no block" "$OUT" "BLOCK"

# Test 7: PreToolUse event → exit 0 even when armed
OUT=$(run_hook '{"event":"PreToolUse"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F")
RC=$?
assert_exit "PreToolUse exit 0" "$RC" "0"

# Test 8: empty input fails open
OUT=$(run_hook '{}' CC_LOOP_GUARD_ENABLED=1)
RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 9: invalid JSON fails open
OUT=$(run_hook 'not json' CC_LOOP_GUARD_ENABLED=1)
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# Test 10: SessionStart but no transcript anywhere → exit 0
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1)
RC=$?
assert_exit "no transcript exit 0" "$RC" "0"

# ---- Group 3: source filtering ----

# Test 11: source=startup → ignored even when armed
F11=$(write_transcript "11.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"startup"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "startup source exit 0" "$RC" "0"
assert_not_contains "startup no block" "$OUT" "BLOCK"

# Test 12: source=fresh → ignored
OUT=$(run_hook '{"event":"SessionStart","source":"fresh"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "fresh source exit 0" "$RC" "0"

# Test 13: source=new → ignored
OUT=$(run_hook '{"event":"SessionStart","source":"new"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "new source exit 0" "$RC" "0"

# Test 14: source=continue → fires
OUT=$(run_hook '{"event":"SessionStart","source":"continue"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "continue source fires" "$RC" "2"

# Test 15: missing source → scans (fail-open default)
OUT=$(run_hook '{"event":"SessionStart"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "missing source scans" "$RC" "2"

# Test 16: unknown source → scans
OUT=$(run_hook '{"event":"SessionStart","source":"experimental"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "unknown source scans" "$RC" "2"

# Test 17: FORCE overrides startup
OUT=$(run_hook '{"event":"SessionStart","source":"startup"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_FORCE=1 CC_LOOP_GUARD_TRANSCRIPT="$F11")
RC=$?
assert_exit "FORCE overrides startup" "$RC" "2"

# ---- Group 4: precursor pattern detection ----

# Test 18: clean transcript (text only) → exit 0
F18=$(write_transcript "18.jsonl" "$text_only_line" "$user_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F18")
RC=$?
assert_exit "clean transcript exit 0" "$RC" "0"

# Test 19: normal thinking (text + sig) → exit 0
F19=$(write_transcript "19.jsonl" "$normal_thinking_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F19")
RC=$?
assert_exit "normal thinking exit 0" "$RC" "0"

# Test 20: empty text but ALSO empty signature → exit 0 (not the precursor)
F20=$(write_transcript "20.jsonl" "$no_signature_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F20")
RC=$?
assert_exit "no signature exit 0" "$RC" "0"

# Test 21: single empty-signed block → block
F21=$(write_transcript "21.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F21")
RC=$?
assert_exit "single precursor blocks" "$RC" "2"

# Test 22: multiple empty-signed blocks → block, count reflected in reason
F22=$(write_transcript "22.jsonl" "$empty_signed_line" "$empty_signed_line2" "$empty_signed_line3")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F22")
RC=$?
assert_exit "multiple precursors block" "$RC" "2"
assert_contains "count in reason" "$OUT" "3 empty-text-signed"

# Test 23: mixed normal + precursor → block on precursor
F23=$(write_transcript "23.jsonl" "$normal_thinking_line" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F23")
RC=$?
assert_exit "mixed transcript blocks" "$RC" "2"

# Test 24: non-JSON lines tolerated (skipped)
F24=$(write_transcript "24.jsonl" "garbage line not json" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F24")
RC=$?
assert_exit "non-JSON tolerated, still blocks" "$RC" "2"

# ---- Group 5: threshold ----

# Test 25: threshold=2 with single precursor → exit 0
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_THRESHOLD=2 CC_LOOP_GUARD_TRANSCRIPT="$F21")
RC=$?
assert_exit "threshold 2, count 1 → exit 0" "$RC" "0"

# Test 26: threshold=2 with two precursors → block
F26=$(write_transcript "26.jsonl" "$empty_signed_line" "$empty_signed_line2")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_THRESHOLD=2 CC_LOOP_GUARD_TRANSCRIPT="$F26")
RC=$?
assert_exit "threshold 2, count 2 → block" "$RC" "2"

# Test 27: threshold=5 with three precursors → exit 0
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_THRESHOLD=5 CC_LOOP_GUARD_TRANSCRIPT="$F22")
RC=$?
assert_exit "threshold 5, count 3 → exit 0" "$RC" "0"

# ---- Group 6: decision JSON shape ----

# Test 28: decision payload includes "block"
F28=$(write_transcript "28.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F28")
assert_contains "decision JSON shape" "$OUT" '"decision":"block"'

# Test 29: reason cites recovery steps
assert_contains "reason cites strip workaround" "$OUT" "stripping thinking"

# Test 30: reason cites CC_LOOP_GUARD_DISABLE recovery escape
assert_contains "reason cites recovery escape" "$OUT" "CC_LOOP_GUARD_DISABLE"

# Test 31: reason cites field guide gist
assert_contains "reason cites field guide" "$OUT" "8c6be069f602399238356a9c9b719a45"

# Test 32: reason cites canonical issue
assert_contains "reason cites issue 63147" "$OUT" "63147"

# Test 33: reason explains the loop trap (not just a generic warning)
assert_contains "reason explains loop trap" "$OUT" "loop"

# ---- Group 7: transcript directory discovery ----

# Test 34: missing transcript dir → exit 0
unset_dir_test() {
    local cc_proj_dir="$TEST_HOME/nonexistent-project"
    HOME="$TEST_HOME" env CC_LOOP_GUARD_ENABLED=1 CC_PROJECT_DIR="$cc_proj_dir" bash "$HOOK" <<< '{"event":"SessionStart","source":"resume"}'
}
OUT=$(unset_dir_test 2>&1)
RC=$?
assert_exit "missing project transcript dir exit 0" "$RC" "0"

# Test 35: project slug computed → finds latest .jsonl
PROJ="$TEST_HOME/some/project"
mkdir -p "$PROJ"
SLUG_DIR="$TEST_HOME/.claude/projects/$(echo "$PROJ" | sed 's|^/||; s|/|-|g')"
mkdir -p "$SLUG_DIR"
# write older then newer file; hook should pick newer
echo "$normal_thinking_line" > "$SLUG_DIR/old.jsonl"
sleep 1  # ensure mtime differs
echo "$empty_signed_line" > "$SLUG_DIR/new.jsonl"
OUT=$(HOME="$TEST_HOME" env CC_LOOP_GUARD_ENABLED=1 CC_PROJECT_DIR="$PROJ" bash "$HOOK" <<< '{"event":"SessionStart","source":"resume"}' 2>&1)
RC=$?
assert_exit "discovers latest .jsonl and blocks" "$RC" "2"

# ---- Group 8: independence from PR #445 hook ----

# Test 36: this hook's env vars do not collide with PR #445's
# (PR #445 uses CC_EXTENDED_THINKING_RESUME_*, this uses CC_LOOP_GUARD_*)
# Verify: setting only PR #445's vars does NOT arm this hook
F36=$(write_transcript "36.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_FORCE=1 CC_LOOP_GUARD_TRANSCRIPT="$F36")
RC=$?
assert_exit "PR #445 env vars do not arm this hook" "$RC" "0"

# Test 37: this hook's env vars do not affect PR #445 (by namespace)
# (verified by inspecting the script — CC_LOOP_GUARD_* vars are exclusive)
grep -q "CC_LOOP_GUARD" examples/extended-thinking-loop-guard.sh && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: namespace check"; }

# ---- Group 9: exit code parity ----

# Test 38: when armed and no precursor, exit code is exactly 0
F38=$(write_transcript "38.jsonl" "$text_only_line")
HOME="$TEST_HOME" env CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F38" bash "$HOOK" <<< '{"event":"SessionStart","source":"resume"}' >/dev/null 2>&1
RC=$?
assert_exit "armed + clean = exit 0" "$RC" "0"

# Test 39: when armed and precursor present, exit code is exactly 2 (not 1)
HOME="$TEST_HOME" env CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="$F28" bash "$HOOK" <<< '{"event":"SessionStart","source":"resume"}' >/dev/null 2>&1
RC=$?
assert_exit "armed + precursor = exit 2" "$RC" "2"

# Test 40: transcript path that does not exist → exit 0 (fail open)
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_LOOP_GUARD_ENABLED=1 CC_LOOP_GUARD_TRANSCRIPT="/nonexistent/path/never.jsonl")
RC=$?
assert_exit "missing transcript path exit 0" "$RC" "0"

# ---- Summary ----
echo ""
echo "=== test-extended-thinking-loop-guard.sh ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
