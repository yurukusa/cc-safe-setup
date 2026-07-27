#!/bin/bash
# claim-verify-detector.sh — detect decisive language without verification
#
# Why: Multiple recent issues show the agent claiming success ("verified",
#      "fixed", "logged out", "won't lose money") while the underlying state
#      is unchanged or still broken. Examples observed in May 2026:
#        #57288 — agent declared "100% guaranteed no loss" 5 minutes after
#                 writing its own warning; loss occurred 6 minutes later.
#        #57271 — agent reported "compared the actual outputs" after only
#                 calling the report function and parsing strings; no visual
#                 comparison was performed.
#        #57285 — `/logout` returned "Successfully logged out" while the
#                 persistent credential store still held the OAuth token.
#      The pattern is: a decisive verb in the response without any evidence
#      that verification was actually executed. This hook flags such turns
#      so the user (or a downstream check) can require the missing evidence
#      before acting on the claim.
#
# How: Stop hook reads the transcript_path, extracts the last assistant
#      message's text, scans for decisive terms, and — when at least one
#      decisive term is present — confirms that at least one verification
#      term is also present. If a decisive term appears alone, write a
#      single warning line to stderr (advisory).
#
# Strict mode: set CC_CLAIM_VERIFY_BLOCK=1 to exit 2 instead of 0. Use this
#      in CI / unattended runs where an unverified claim should fail closed.
#
# Skip: set CC_CLAIM_VERIFY_SKIP=1 in shells where the heuristic fires too
#      often (research notebooks, retrospective writing, etc.).
#
# TRIGGER: Stop
# MATCHER: ""

set -u

[ "${CC_CLAIM_VERIFY_SKIP:-0}" = "1" ] && exit 0

INPUT=$(cat)

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Pull the text of the most recent assistant message. tac walks the jsonl in
# reverse so the first match is the latest turn. We concatenate every text
# block of that message into one string for scanning.
LAST_ASSISTANT=$(tac "$TRANSCRIPT" 2>/dev/null \
    | grep -m1 '"type":"assistant"' \
    | jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null)

[ -z "$LAST_ASSISTANT" ] && exit 0

# Decisive terms: words that imply a checked / completed / safe outcome.
# English and Japanese listed together. Matching is case-insensitive.
DECISIVE_RE='(\bverified\b|\bconfirmed\b|\bfixed\b|\bresolved\b|\bcompleted\b|\bsucceeded\b|\bworking\b|\bguaranteed\b|\bcannot fail\b|\bwill (not|never) (fail|lose|miss)\b|\b(?:successfully )?logged out\b|\bterminated cleanly\b|\bno (data )?loss\b|\bsafe to (commit|deploy|push)\b|直った|修正した|確認した|検証した|完了した|終了した|生存している|絶対に|保証する|リセット(した|済)|動作の確認)'

# Verification terms: words that show evidence was actually gathered.
# If the response includes a decisive term AND a verification term, treat
# the claim as backed and stay silent.
EVIDENCE_RE='(\bran\b|\bexecuted\b|\bexit code\b|\bstatus code\b|\boutput shows\b|\boutput was\b|\blog shows\b|\blogs? (show|showed|confirm)\b|\breturned\b|\bscreenshot\b|\bcaptured\b|\bobserved\b|\bmeasured\b|\bcompared\b|\bdiff\b|\bchecked .*output\b|実行した|出力は|戻り値は|終了状態は|ログ(は|が)|画面(の|を)?(取得|捕捉|表示)|計測(の結果|した)|表示した|並べて確認|比較した結果)'

# Use grep -P for proper word boundaries and alternation. Fall back to grep -E
# if -P is unavailable (e.g. busybox); the difference matters less than
# returning a clean exit on minimal systems.
GREP=grep
if ! echo "" | grep -P '' >/dev/null 2>&1; then
    GREP='grep -E'
    DECISIVE_RE=$(printf '%s' "$DECISIVE_RE" | sed 's/\\b//g')
    EVIDENCE_RE=$(printf '%s' "$EVIDENCE_RE" | sed 's/\\b//g')
fi

DECISIVE_HIT=$(printf '%s' "$LAST_ASSISTANT" | $GREP -ioP "$DECISIVE_RE" 2>/dev/null | head -3 | paste -sd ',' -)
[ -z "$DECISIVE_HIT" ] && exit 0

EVIDENCE_HIT=$(printf '%s' "$LAST_ASSISTANT" | $GREP -ioP "$EVIDENCE_RE" 2>/dev/null | head -1)
[ -n "$EVIDENCE_HIT" ] && exit 0

# Decisive without evidence — emit one advisory line.
{
    echo "WARNING: claim-verify-detector flagged decisive language without visible verification."
    echo "  Decisive terms: $DECISIVE_HIT"
    echo "  Suggestion: before acting on this claim, capture the verifying output (exit code, log line, screenshot, or diff) directly in the response."
    echo "  Background: this pattern matches Issues #57288 / #57271 / #57285 (May 2026 claim-vs-reality cluster)."
} >&2

if [ "${CC_CLAIM_VERIFY_BLOCK:-0}" = "1" ]; then
    echo "BLOCKED by claim-verify-detector (strict mode). Unset CC_CLAIM_VERIFY_BLOCK to convert to advisory." >&2
    exit 2
fi

exit 0
