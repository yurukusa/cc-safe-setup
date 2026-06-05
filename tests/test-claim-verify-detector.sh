#!/bin/bash
# Test for claim-verify-detector.sh
#
# Builds a synthetic transcript (.jsonl) for each case so the hook reads a
# realistic last-assistant message and emits warnings only when decisive
# language appears without supporting evidence.

set -u

HOOK="$(dirname "$0")/../examples/claim-verify-detector.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Build a one-line jsonl transcript whose latest assistant message contains
# the supplied text. Returns the path to the file.
make_transcript() {
    local text="$1"
    local path="$TMPDIR/transcript-$$-$RANDOM.jsonl"
    jq -nc --arg t "$text" '{
        type: "user",
        message: { role: "user", content: [{type:"text", text:"do the thing"}] }
    }' > "$path"
    jq -nc --arg t "$text" '{
        type: "assistant",
        message: { role: "assistant", content: [{type:"text", text:$t}] }
    }' >> "$path"
    printf '%s' "$path"
}

run_case() {
    local name="$1"
    local text="$2"
    local expect_warn="$3"  # "yes" or "no"
    local strict="${4:-0}"
    local skip="${5:-0}"

    local transcript
    transcript=$(make_transcript "$text")
    local input
    input=$(jq -nc --arg p "$transcript" '{transcript_path:$p, session_id:"test"}')

    local stderr rc env
    env=""
    [ "$strict" = "1" ] && env="CC_CLAIM_VERIFY_BLOCK=1 "
    [ "$skip" = "1" ] && env="${env}CC_CLAIM_VERIFY_SKIP=1 "
    stderr=$(echo "$input" | env $env "$HOOK" 2>&1 >/dev/null)
    rc=$?

    if [ "$expect_warn" = "yes" ]; then
        if [ -n "$stderr" ]; then
            PASS=$((PASS + 1))
            echo "PASS: $name"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $name (expected warning, got none)"
        fi
        if [ "$strict" = "1" ]; then
            if [ "$rc" = "2" ]; then
                PASS=$((PASS + 1))
                echo "PASS: $name (strict, exit 2)"
            else
                FAIL=$((FAIL + 1))
                echo "FAIL: $name (strict, expected exit 2, got $rc)"
            fi
        fi
    else
        if [ -z "$stderr" ]; then
            PASS=$((PASS + 1))
            echo "PASS: $name"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $name (expected silence, got: $stderr)"
        fi
    fi
}

run_input_case() {
    local name="$1"
    local input="$2"
    local expect_warn="$3"

    local stderr
    stderr=$(echo "$input" | "$HOOK" 2>&1 >/dev/null)

    if [ "$expect_warn" = "yes" ]; then
        if [ -n "$stderr" ]; then
            PASS=$((PASS + 1))
            echo "PASS: $name"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $name (expected warning, got none)"
        fi
    else
        if [ -z "$stderr" ]; then
            PASS=$((PASS + 1))
            echo "PASS: $name"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $name (expected silence, got: $stderr)"
        fi
    fi
}

# ---- decisive-without-evidence cases (should warn) ----

run_case "EN: bare 'verified'" \
    "I have verified the change." "yes"

run_case "EN: bare 'fixed'" \
    "The bug is fixed." "yes"

run_case "EN: bare 'completed'" \
    "Task completed." "yes"

run_case "EN: bare 'logged out'" \
    "You have been successfully logged out." "yes"

run_case "EN: 'no data loss' alone" \
    "No data loss occurred." "yes"

run_case "EN: 'guaranteed'" \
    "This is guaranteed to work." "yes"

run_case "EN: '#57288 style claim'" \
    "100% guaranteed: this position cannot fail." "yes"

run_case "EN: 'safe to deploy'" \
    "It is safe to deploy now." "yes"

run_case "JP: 直った single" \
    "問題は直った。" "yes"

run_case "JP: 修正した single" \
    "issue を修正した。" "yes"

run_case "JP: 確認した single" \
    "全件確認した。" "yes"

run_case "JP: 完了した single" \
    "作業を完了した。" "yes"

run_case "JP: 終了した single" \
    "セッションを終了した。" "yes"

run_case "JP: 絶対に失敗しない" \
    "絶対に失敗しない設計だ。" "yes"

run_case "JP: 動作の確認 alone" \
    "動作の確認はもう済んだ。" "yes"

# ---- decisive WITH evidence (should stay silent) ----

run_case "EN: verified + ran" \
    "Verified — I ran the test suite and exit code was 0." "no"

run_case "EN: fixed + log shows" \
    "Fixed. The log shows the request returning 200." "no"

run_case "EN: completed + output was" \
    "Completed. Output was: 'all rows updated, 0 errors'." "no"

run_case "EN: confirmed + screenshot" \
    "Confirmed via screenshot at /tmp/check.png." "no"

run_case "EN: working + measured" \
    "Working: I measured response latency at 24ms." "no"

run_case "JP: 修正した + 実行した" \
    "修正した。テストを実行した結果、 全件 OK だった。" "no"

run_case "JP: 確認した + ログは" \
    "確認した。ログは 200 を返している。" "no"

run_case "JP: 完了した + 出力は" \
    "完了した。出力は 'success' だった。" "no"

run_case "JP: 検証した + 計測した" \
    "検証した。計測の結果、 1.2 秒だった。" "no"

# ---- no decisive language (should stay silent) ----

run_case "EN: descriptive only" \
    "I added a new function and ran the tests." "no"

run_case "EN: question reply" \
    "The function lives in src/utils.ts and takes one argument." "no"

run_case "JP: 単なる説明" \
    "新しい関数を src/utils.ts に追加した。" "no"

run_case "JP: 状態の報告" \
    "現状の試験の数は 30 件。" "no"

run_case "EN: empty assistant" \
    "" "no"

# ---- environment / input-shape edge cases ----

run_case "skip flag silences" \
    "Verified — but skip flag set." "no" "0" "1"

run_case "strict mode, decisive only -> exit 2" \
    "Fixed." "yes" "1"

run_input_case "missing transcript_path field" \
    '{"session_id":"x"}' "no"

run_input_case "transcript_path empty" \
    '{"transcript_path":"","session_id":"x"}' "no"

run_input_case "transcript_path nonexistent" \
    '{"transcript_path":"/tmp/does-not-exist-claim-verify.jsonl","session_id":"x"}' "no"

# ---- summary ----

echo ""
echo "RESULT: $PASS passed, $FAIL failed."
[ "$FAIL" = "0" ]
