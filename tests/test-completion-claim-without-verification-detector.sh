#!/bin/bash
# Tests for completion-claim-without-verification-detector.sh
# Run: bash tests/test-completion-claim-without-verification-detector.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/completion-claim-without-verification-detector.sh"

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Helper: build a transcript with the given assistant message + tool history
# args: $1=output_file $2=assistant_text $3=tool_use_lines_count $4=tool_pattern
build_transcript() {
    local out="$1"
    local assistant_text="$2"
    local extra_jsonl="${3:-}"
    {
        # Optional extra JSONL lines (tool use entries etc.)
        if [ -n "$extra_jsonl" ]; then
            printf '%s\n' "$extra_jsonl"
        fi
        # Final assistant message with the text content
        jq -nc \
            --arg text "$assistant_text" \
            '{type: "assistant", message: {content: [{type: "text", text: $text}]}}'
    } > "$out"
}

# Helper: run the hook with a transcript and capture stderr (advisory output)
run_hook() {
    local transcript="$1"
    local extra_env="${2:-}"
    local input
    input=$(jq -nc \
        --arg t "$transcript" \
        --arg s "test-session-123" \
        '{transcript_path: $t, session_id: $s}')
    if [ -n "$extra_env" ]; then
        printf '%s' "$input" | env -i PATH="$PATH" HOME="$TMPDIR" $extra_env bash "$HOOK" 2>&1 >/dev/null
    else
        printf '%s' "$input" | env -i PATH="$PATH" HOME="$TMPDIR" bash "$HOOK" 2>&1 >/dev/null
    fi
}

assert_silent() {
    local label="$1"
    local output="$2"
    if [ -z "$output" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $label"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label"
        echo "    expected silent, got: ${output:0:200}"
    fi
}

assert_warns() {
    local label="$1"
    local output="$2"
    if echo "$output" | grep -q "completion-claim-without-verification"; then
        PASS=$((PASS + 1))
        echo "  ✓ $label"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label (no warning emitted)"
        echo "    got: ${output:0:200}"
    fi
}

echo "=== Silent cases (no completion claim) ==="

TRANS="$TMPDIR/t1.jsonl"
build_transcript "$TRANS" "I'll start by reading the file structure."
OUT=$(run_hook "$TRANS")
assert_silent "no completion claim — progress message" "$OUT"

build_transcript "$TRANS" "Here is the analysis of the current state. The function appears to use a recursive approach."
OUT=$(run_hook "$TRANS")
assert_silent "no completion claim — analysis message" "$OUT"

build_transcript "$TRANS" "I think this should be done, but I haven't run the tests yet — could you verify?"
OUT=$(run_hook "$TRANS")
assert_silent "hedged statement — 'I think' + asking to verify" "$OUT"

build_transcript "$TRANS" "This seems to work locally but I have not deployed it."
OUT=$(run_hook "$TRANS")
assert_silent "hedged 'seems to work' — not a definitive claim" "$OUT"

echo ""
echo "=== Detection: English completion claims without verification ==="

build_transcript "$TRANS" "Done. The refactor is complete."
OUT=$(run_hook "$TRANS")
assert_warns "english 'done' — bare claim" "$OUT"

build_transcript "$TRANS" "Ready to test. The changes are in place."
OUT=$(run_hook "$TRANS")
assert_warns "english 'ready to test'" "$OUT"

build_transcript "$TRANS" "Fixed. The bug has been resolved."
OUT=$(run_hook "$TRANS")
assert_warns "english 'fixed'" "$OUT"

build_transcript "$TRANS" "I've finished implementing the feature."
OUT=$(run_hook "$TRANS")
assert_warns "english 'finished implementing'" "$OUT"

build_transcript "$TRANS" "Successfully implemented the requested change."
OUT=$(run_hook "$TRANS")
assert_warns "english 'successfully implemented'" "$OUT"

build_transcript "$TRANS" "The implementation is now complete and working."
OUT=$(run_hook "$TRANS")
assert_warns "english 'implementation is now complete'" "$OUT"

build_transcript "$TRANS" "Task complete. Code is shipped to production."
OUT=$(run_hook "$TRANS")
assert_warns "english 'task complete'" "$OUT"

echo ""
echo "=== Detection: Japanese completion claims without verification ==="

build_transcript "$TRANS" "完了しました。修正をご確認ください。"
OUT=$(run_hook "$TRANS")
assert_warns "japanese 完了しました" "$OUT"

build_transcript "$TRANS" "修正完了です。"
OUT=$(run_hook "$TRANS")
assert_warns "japanese 修正完了" "$OUT"

build_transcript "$TRANS" "実装完了しました。テストしてみてください。"
OUT=$(run_hook "$TRANS")
assert_warns "japanese 実装完了" "$OUT"

build_transcript "$TRANS" "デプロイ完了。準備完了です。"
OUT=$(run_hook "$TRANS")
assert_warns "japanese デプロイ完了 / 準備完了" "$OUT"

echo ""
echo "=== Silent: completion claim WITH verification in recent history ==="

# Build a transcript with a Bash tool_use that runs pytest, then the
# completion claim. The hook should NOT fire because verification was done.
TRANS="$TMPDIR/t2.jsonl"
{
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Bash", input: {command: "pytest tests/"}}
            ]
        }
    }'
    jq -nc '{
        type: "user",
        message: {
            content: [
                {type: "tool_result", content: "12 passed in 1.23s"}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "text", text: "Done. All tests pass."}
            ]
        }
    }'
} > "$TRANS"
OUT=$(run_hook "$TRANS")
assert_silent "completion claim + recent pytest — verification found" "$OUT"

TRANS="$TMPDIR/t3.jsonl"
{
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Bash", input: {command: "npm test"}}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "text", text: "Fixed. Implementation is complete."}
            ]
        }
    }'
} > "$TRANS"
OUT=$(run_hook "$TRANS")
assert_silent "completion claim + recent npm test — verification found" "$OUT"

TRANS="$TMPDIR/t4.jsonl"
{
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Bash", input: {command: "curl -s http://localhost:8080/health"}}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "text", text: "Ready to test. The endpoint is responding."}
            ]
        }
    }'
} > "$TRANS"
OUT=$(run_hook "$TRANS")
assert_silent "completion claim + recent curl — verification found" "$OUT"

TRANS="$TMPDIR/t5.jsonl"
{
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Bash", input: {command: "go test ./..."}}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "text", text: "完了しました。テスト通過済。"}
            ]
        }
    }'
} > "$TRANS"
OUT=$(run_hook "$TRANS")
assert_silent "japanese completion claim + go test — verification found" "$OUT"

echo ""
echo "=== Silent: Read of log file counts as verification ==="

TRANS="$TMPDIR/t6.jsonl"
{
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Read", input: {file_path: "/tmp/server.log"}}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "text", text: "Done. Server is running cleanly."}
            ]
        }
    }'
} > "$TRANS"
OUT=$(run_hook "$TRANS")
assert_silent "completion claim + Read of log file" "$OUT"

echo ""
echo "=== Detection: irrelevant Bash commands don't count as verification ==="

TRANS="$TMPDIR/t7.jsonl"
{
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Bash", input: {command: "ls -la"}}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "tool_use", name: "Bash", input: {command: "git add ."}}
            ]
        }
    }'
    jq -nc '{
        type: "assistant",
        message: {
            content: [
                {type: "text", text: "Done. Changes committed."}
            ]
        }
    }'
} > "$TRANS"
OUT=$(run_hook "$TRANS")
assert_warns "completion claim + ls/git add only (no test) — should warn" "$OUT"

echo ""
echo "=== Safety: disable env var, empty input ==="

TRANS="$TMPDIR/t8.jsonl"
build_transcript "$TRANS" "Done. Task complete."
OUT=$(run_hook "$TRANS" "CC_COMPLETION_CLAIM_DISABLE=1")
assert_silent "CC_COMPLETION_CLAIM_DISABLE=1 disables" "$OUT"

# Empty input
OUT=$(echo '' | env -i PATH="$PATH" HOME="$TMPDIR" bash "$HOOK" 2>&1)
assert_silent "empty input" "$OUT"

# Missing transcript_path
OUT=$(echo '{}' | env -i PATH="$PATH" HOME="$TMPDIR" bash "$HOOK" 2>&1)
assert_silent "no transcript_path in input" "$OUT"

# Non-existent transcript path
OUT=$(echo '{"transcript_path": "/nonexistent/path.jsonl"}' | env -i PATH="$PATH" HOME="$TMPDIR" bash "$HOOK" 2>&1)
assert_silent "non-existent transcript path" "$OUT"

echo ""
echo "=== Results ==="
echo "Pass: $PASS"
echo "Fail: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
