#!/bin/bash
# Tests for per-prompt-token-cap.sh — uses synthesized JSONL transcripts
# to simulate single-prompt token consumption patterns.
HOOK="examples/per-prompt-token-cap.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

make_transcript() {
  local file
  file=$(mktemp)
  printf '%s\n' "$1" > "$file"
  printf '%s' "$file"
}

make_input() {
  local transcript_path="$1"
  jq -n --arg t "$transcript_path" '{transcript_path: $t, tool_name: "Bash", tool_input: {command: "echo test"}}'
}

# Test 1: small prompt under default warn cap (1M tokens) → no warning
TRANSCRIPT_LINES='{"type":"user","message":{"content":"hello"}}
{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":500,"cache_read_input_tokens":200}}}'
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "small prompt exits 0" "$RC" 0
assert_not_contains "small prompt no warning" "$OUT" "WARNING"
rm -f "$TRANSCRIPT"

# Test 2: prompt above default warn cap (1M tokens) → warning
LARGE_INPUT_TOKENS=900000
LARGE_CACHE_CREATION=200000
TRANSCRIPT_LINES="{\"type\":\"user\",\"message\":{\"content\":\"big task\"}}
{\"type\":\"assistant\",\"message\":{\"usage\":{\"input_tokens\":${LARGE_INPUT_TOKENS},\"cache_creation_input_tokens\":${LARGE_CACHE_CREATION},\"cache_read_input_tokens\":0}}}"
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "large prompt exits 0 in warn-only mode" "$RC" 0
assert_contains "large prompt produces warning" "$OUT" "WARNING"
assert_contains "warning mentions hook name" "$OUT" "per-prompt-token-cap"
assert_contains "warning mentions issue cluster" "$OUT" "#56297"
rm -f "$TRANSCRIPT"

# Test 3: only the LATEST prompt's tokens are counted (older user turn ignored)
TRANSCRIPT_LINES='{"type":"user","message":{"content":"first task"}}
{"type":"assistant","message":{"usage":{"input_tokens":2000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"user","message":{"content":"second task — small"}}
{"type":"assistant","message":{"usage":{"input_tokens":50000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":5000}}}'
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "boundary detection exits 0" "$RC" 0
assert_not_contains "previous large prompt's tokens not double-counted" "$OUT" "WARNING"
rm -f "$TRANSCRIPT"

# Test 4: block cap configured and exceeded → exit 2
TRANSCRIPT_LINES='{"type":"user","message":{"content":"runaway task"}}
{"type":"assistant","message":{"usage":{"input_tokens":3000000,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":500000}}}'
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(PER_PROMPT_TOKEN_BLOCK=2000000 bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$INPUT" 2>&1)
RC=$?
assert_exit "block path exits 2" "$RC" 2
assert_contains "block message present" "$OUT" "BLOCKED"
assert_contains "block message includes count" "$OUT" "4500000"
rm -f "$TRANSCRIPT"

# Test 5: missing transcript_path → exit 0 silently
INPUT='{"tool_name":"Bash","tool_input":{"command":"echo test"}}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing transcript exits 0" "$RC" 0
assert_not_contains "missing transcript no warning" "$OUT" "WARNING"

# Test 6: nonexistent transcript file → exit 0 silently
INPUT=$(jq -n '{transcript_path: "/tmp/nonexistent-transcript-xyz.jsonl", tool_name: "Bash"}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "nonexistent transcript exits 0" "$RC" 0
assert_not_contains "nonexistent transcript no warning" "$OUT" "WARNING"

# Test 7: custom warn cap respected
TRANSCRIPT_LINES='{"type":"user","message":{"content":"task"}}
{"type":"assistant","message":{"usage":{"input_tokens":15000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(PER_PROMPT_TOKEN_CAP=10000 bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$INPUT" 2>&1)
RC=$?
assert_exit "custom warn cap exits 0" "$RC" 0
assert_contains "custom warn cap triggers warning" "$OUT" "WARNING"
assert_contains "warning shows actual count" "$OUT" "15000"
rm -f "$TRANSCRIPT"

# Test 8: empty transcript → exit 0 silently
TRANSCRIPT=$(make_transcript "")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty transcript exits 0" "$RC" 0
assert_not_contains "empty transcript no warning" "$OUT" "WARNING"
rm -f "$TRANSCRIPT"

# Test 9: only user turns, no assistant turns → exit 0 silently
TRANSCRIPT_LINES='{"type":"user","message":{"content":"task"}}
{"type":"user","message":{"content":"another"}}'
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "user-only transcript exits 0" "$RC" 0
assert_not_contains "user-only transcript no warning" "$OUT" "WARNING"
rm -f "$TRANSCRIPT"

# Test 10: malformed JSONL lines tolerated → no crash
TRANSCRIPT_LINES='not valid json
{"type":"user","message":{"content":"task"}}
{"type":"assistant","message":{"usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
also not json'
TRANSCRIPT=$(make_transcript "$TRANSCRIPT_LINES")
INPUT=$(make_input "$TRANSCRIPT")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "malformed lines tolerated, exits 0" "$RC" 0
assert_not_contains "malformed input no warning under default cap" "$OUT" "WARNING"
rm -f "$TRANSCRIPT"

# Summary
echo
echo "=== per-prompt-token-cap tests: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
