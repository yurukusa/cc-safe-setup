#!/bin/bash
# Tests for extended-thinking-resume-warning.sh (Cluster 13 Axis A)
# Covers: event filtering, source filtering, transcript pattern detection,
# fail-open, environment variables, edge cases.

HOOK="examples/extended-thinking-resume-warning.sh"
PASS=0 FAIL=0

TEST_HOME=$(mktemp -d)
TEST_TRANSCRIPT_DIR="$TEST_HOME/transcripts"
mkdir -p "$TEST_TRANSCRIPT_DIR"
trap 'rm -rf "$TEST_HOME"' EXIT

write_transcript() {
    # $1 = filename, $2... = lines
    local f="$TEST_TRANSCRIPT_DIR/$1"; shift
    : > "$f"
    for line in "$@"; do
        printf '%s\n' "$line" >> "$f"
    done
    echo "$f"
}

run_hook() {
    # $1 = input JSON, optional env vars trail
    local payload="$1"; shift
    HOME="$TEST_HOME" env "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  got: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Helper to build a thinking-block jsonl line
empty_signed_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"sigABCDEF1234567890"}]}}'
empty_signed_line2='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"longerSignatureFFFF1234"}]}}'
normal_thinking_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"reasoning text here","signature":"sigABCDEF"}]}}'
no_signature_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":""}]}}'
text_only_line='{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}'
user_line='{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}'

# ---- Group 1: event filtering ----

# Test 1: non-SessionStart event ignored
F=$(write_transcript "1.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"Stop"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "non-SessionStart exit 0" "$RC" "0"
assert_not_contains "non-SessionStart no advisory" "$OUT" "Cluster 13A"

# Test 2: empty input fails open
OUT=$(run_hook '{}')
RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 3: invalid JSON fails open
OUT=$(run_hook 'not json')
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# Test 4: SessionStart with no transcript at all → exit 0
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}')
RC=$?
assert_exit "no transcript exit 0" "$RC" "0"
assert_not_contains "no transcript no advisory" "$OUT" "Cluster 13A"

# ---- Group 2: source filtering ----

# Test 5: source=startup → ignored
F=$(write_transcript "5.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"startup"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "startup source exit 0" "$RC" "0"
assert_not_contains "startup source no advisory" "$OUT" "Cluster 13A"

# Test 6: source=fresh → ignored
OUT=$(run_hook '{"event":"SessionStart","source":"fresh"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "fresh source exit 0" "$RC" "0"

# Test 7: source=resume + matching transcript → advisory fires
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "resume source exit 0" "$RC" "0"
assert_contains "resume fires advisory" "$OUT" "Cluster 13A precursor detected"
assert_contains "resume names transcript" "$OUT" "Transcript:"
assert_contains "resume cites field guide" "$OUT" "Field guide:"
assert_contains "resume cites #63147" "$OUT" "63147"

# Test 8: source=continue → fires
OUT=$(run_hook '{"event":"SessionStart","source":"continue"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "continue source exit 0" "$RC" "0"
assert_contains "continue fires advisory" "$OUT" "Cluster 13A precursor detected"

# Test 9: missing source field → scans (fail-open)
OUT=$(run_hook '{"event":"SessionStart"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "no source exit 0" "$RC" "0"
assert_contains "no source still scans" "$OUT" "Cluster 13A precursor detected"

# Test 10: FORCE env var overrides source filtering
OUT=$(run_hook '{"event":"SessionStart","source":"startup"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F" CC_EXTENDED_THINKING_RESUME_FORCE=1)
RC=$?
assert_exit "FORCE exit 0" "$RC" "0"
assert_contains "FORCE bypasses source filter" "$OUT" "Cluster 13A precursor detected"

# ---- Group 3: transcript pattern detection ----

# Test 11: empty transcript → no advisory
F=$(write_transcript "11.jsonl")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "empty transcript exit 0" "$RC" "0"
assert_not_contains "empty transcript no advisory" "$OUT" "Cluster 13A"

# Test 12: transcript with only user/text lines → no advisory
F=$(write_transcript "12.jsonl" "$user_line" "$text_only_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "no thinking exit 0" "$RC" "0"
assert_not_contains "no thinking no advisory" "$OUT" "Cluster 13A"

# Test 13: thinking blocks with text (healthy) → no advisory
F=$(write_transcript "13.jsonl" "$normal_thinking_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "healthy thinking exit 0" "$RC" "0"
assert_not_contains "healthy thinking no advisory" "$OUT" "Cluster 13A"

# Test 14: empty thinking with empty signature → no advisory
F=$(write_transcript "14.jsonl" "$no_signature_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "no-sig empty exit 0" "$RC" "0"
assert_not_contains "no-sig empty no advisory" "$OUT" "Cluster 13A"

# Test 15: single empty-signed block → advisory fires, count = 1
F=$(write_transcript "15.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "single empty-signed exit 0" "$RC" "0"
assert_contains "single empty-signed fires" "$OUT" "Cluster 13A precursor detected"
assert_contains "single empty-signed count 1" "$OUT" "block(s): 1"

# Test 16: multiple empty-signed blocks → count reflects total
F=$(write_transcript "16.jsonl" "$empty_signed_line" "$empty_signed_line2" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "multi empty-signed exit 0" "$RC" "0"
assert_contains "multi empty-signed count 3" "$OUT" "block(s): 3"

# Test 17: mix of healthy and empty-signed → only empty-signed counted
F=$(write_transcript "17.jsonl" "$normal_thinking_line" "$empty_signed_line" "$normal_thinking_line" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "mixed exit 0" "$RC" "0"
assert_contains "mixed counts only empty-signed" "$OUT" "block(s): 2"

# Test 18: assistant message with multiple content blocks
mixed_content='{"type":"assistant","message":{"content":[{"type":"text","text":"reply"},{"type":"thinking","thinking":"","signature":"sigXYZ123"},{"type":"thinking","thinking":"healthy text","signature":"sigOK"}]}}'
F=$(write_transcript "18.jsonl" "$mixed_content")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "multi-content exit 0" "$RC" "0"
assert_contains "multi-content counts 1" "$OUT" "block(s): 1"

# ---- Group 4: environment variable behavior ----

# Test 19: CC_EXTENDED_THINKING_RESUME_DISABLE silences hook
F=$(write_transcript "19.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F" CC_EXTENDED_THINKING_RESUME_DISABLE=1)
RC=$?
assert_exit "disabled exit 0" "$RC" "0"
assert_not_contains "disabled no advisory" "$OUT" "Cluster 13A"

# Test 20: CC_EXTENDED_THINKING_RESUME_VERBOSE adds signature length info
F=$(write_transcript "20.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F" CC_EXTENDED_THINKING_RESUME_VERBOSE=1)
RC=$?
assert_exit "verbose exit 0" "$RC" "0"
assert_contains "verbose includes signature lengths" "$OUT" "per-block signature lengths"

# ---- Group 5: project-directory auto-discovery (limited; we use override in tests) ----

# Test 21: missing transcript path AND no project dir → exit 0
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}')
RC=$?
assert_exit "no project dir exit 0" "$RC" "0"

# Test 22: transcript path that doesn't exist on disk → exit 0
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="/nonexistent/path.jsonl")
RC=$?
assert_exit "missing transcript path exit 0" "$RC" "0"

# ---- Group 6: malformed transcript resilience ----

# Test 23: transcript with malformed json line → does not crash
F=$(write_transcript "23.jsonl" "not valid json at all" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "malformed line exit 0" "$RC" "0"
# jq processes each line independently; the bad line is skipped, the good one still matches.
assert_contains "malformed line still counts good" "$OUT" "block(s): 1"

# Test 24: thinking field present but null → not counted as empty
null_thinking='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":null,"signature":"sigNULL"}]}}'
F=$(write_transcript "24.jsonl" "$null_thinking")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "null thinking exit 0" "$RC" "0"
# null thinking becomes "" via the jq // operator, so this DOES match.
assert_contains "null thinking treated as empty" "$OUT" "block(s): 1"

# Test 25: signature field present but null → not counted as bypass
null_sig='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":null}]}}'
F=$(write_transcript "25.jsonl" "$null_sig")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
RC=$?
assert_exit "null sig exit 0" "$RC" "0"
assert_not_contains "null sig no advisory" "$OUT" "Cluster 13A"

# ---- Group 7: advisory shape ----

# Test 26: advisory names sub-pattern
F=$(write_transcript "26.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"SessionStart","source":"resume"}' CC_EXTENDED_THINKING_RESUME_TRANSCRIPT="$F")
assert_contains "advisory names 13A" "$OUT" "13A precursor"

# Test 27: advisory lists recovery actions
assert_contains "advisory lists save state" "$OUT" "save state"
assert_contains "advisory lists fresh session" "$OUT" "start a fresh session"
assert_contains "advisory mentions /model" "$OUT" "/model"

# Test 28: advisory quotes API error
assert_contains "advisory quotes API error" "$OUT" "thinking.*blocks.*cannot be modified"

echo ""
echo "Tests: $((PASS+FAIL)) | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
