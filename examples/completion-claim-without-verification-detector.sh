#!/bin/bash
# completion-claim-without-verification-detector.sh — Stop hook
# Trigger: Stop
# Matcher: ""
#
# Solves: Issue #60177 (mike-prokhorov, 2026-05-18) — "Claude marks tasks
#         done without testing — 12 days, 51 commits, still broken (Opus
#         4.x)". Across approximately fifty sessions over twelve days, the
#         agent repeatedly said "done, ready to test" without running any
#         verification step. Approximately 70% of the period's commits
#         were fix-of-prior-commit rather than progress. The user's
#         post-incident framing: a four-level honesty ladder where
#         L0 = file exists, L1 = smoke-tested locally, L2 = runs in
#         staging, L3 = user-approved. The agent defaulted to claiming
#         the highest aspirational level (L3-ish "done, ready to test")
#         without having reached even L1.
#
# Class of failure: claim-vs-reality divergence at the completion-signal
#         layer. The agent's response surface emits a definitive
#         completion claim ("done", "ready to test", "fixed",
#         "succeeded", "完了") that the underlying tool history does not
#         support. The user trusts the claim, attempts to use the
#         deliverable, and discovers the gap downstream — often after
#         expensive context loss.
#
# HOW IT WORKS:
#   On Stop, the hook reads the session transcript and looks at the
#   final assistant message for completion-claim markers. If a claim
#   is detected, it then scans the recent tool-use history (the last
#   FORTY tool calls in this session) for verification-shaped tools:
#   Bash invocations that run a test command (pytest / npm test /
#   go test / cargo test / curl / status check / smoke / verify),
#   Read on log files, or Grep against an output destination.
#   If a completion claim was emitted but no verification-shaped tool
#   appears in the recent window, the hook writes an advisory line to
#   stderr and logs the detection. The hook never blocks the Stop.
#
# WHY THIS MATTERS:
#   The 60177 failure shape is one of the most expensive in the
#   tracker. Every "done, ready to test" without verification spends
#   the operator's attention budget on a falsified completion, often
#   triggers a re-run cycle that burns API credits, and erodes the
#   trust margin that lets the agent operate autonomously at all.
#   Most prevention efforts focus on slowing the agent down with
#   permission prompts on individual tool calls. This hook works in
#   the opposite direction: it lets the agent run freely and only
#   surfaces a warning when the *completion claim* contradicts the
#   *recent tool history*.
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION:
#   CC_COMPLETION_CLAIM_DISABLE=1    disable the hook entirely
#   CC_COMPLETION_CLAIM_LOG=path     append detection events
#                                    (default ~/.claude/logs/completion-claim.log)
#   CC_COMPLETION_CLAIM_WINDOW=N     scan window size in tool calls
#                                    (default 40)
#
# SAFETY:
#   - Read-only on the transcript; never modifies any session state.
#   - Emits an advisory line via stderr; does not block Stop.
#   - Exits 0 always; never prevents the session from ending.
#   - Uses jq for transcript parsing; falls back silently if jq is
#     not installed (Claude Code requires jq for hook input parsing
#     so this is rarely a real problem).
#
# REFERENCES:
#   - anthropics/claude-code#60177 (mike-prokhorov, 2026-05-18) — the
#     canonical case with the L0/L1/L2/L3 ladder framing
#   - companion hook: rhetorical-verification-prompt-detector.sh
#     (catches the input-side rhetorical-question failure, while this
#     hook catches the output-side completion-claim failure)
set -u

[ "${CC_COMPLETION_CLAIM_DISABLE:-}" = "1" ] && exit 0

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${CC_COMPLETION_CLAIM_LOG:-${LOG_DIR}/completion-claim.log}"
mkdir -p "$LOG_DIR" 2>/dev/null

WINDOW="${CC_COMPLETION_CLAIM_WINDOW:-40}"

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Extract text of the last assistant message in the transcript.
# Each JSONL line of type=assistant has message.content as an array of
# blocks; we collect blocks of type=text.
LAST_TEXT=$(tac "$TRANSCRIPT" 2>/dev/null \
    | grep -m1 '"type":"assistant"' \
    | jq -r '
        if (.message.content | type) == "array" then
            [.message.content[] | select(.type=="text") | .text] | join("\n")
        else
            ""
        end
    ' 2>/dev/null || true)

[ -z "$LAST_TEXT" ] && exit 0

# Detection patterns — completion-claim markers.
# Conservative on purpose: only catch phrasing that strongly implies a
# definitive *done* assertion. Hedged phrasing ("seems to work",
# "I think this is ready", "this should be done") deliberately does not
# trigger — that hedged surface form is the honest one we want to keep.
EN_PATTERNS='\b(done|complete|completed|ready to test|fixed|fixed it|all set|good to go|works now|working now|deployed|shipped)\b|task (is )?(now )?(done|complete|finished)|implementation (is )?(now )?(done|complete|finished)|i.?ve (finished|completed|implemented|fixed)|successfully (implemented|completed|fixed|deployed)|the (fix|change|feature|implementation) is (now )?(working|done|complete|deployed)'

JA_PATTERNS='完了(しました|です)?|終わりました|完成(しました|です)?|準備(が )?完了|修正(済|完了|しました)|実装(完了|済|しました)|デプロイ(完了|済|しました)|動作(確認済|しました)?|テスト(してください|可能です)|動きます|動いています'

# Hedge detection — if the message contains hedging markers, treat it as
# NOT a definitive completion claim. Honest hedging is the surface form we
# want to preserve.
EN_HEDGE='\b(i think|i believe|i hope|hopefully|maybe|possibly|might be|might have|should be|should have|seems to|appears to|looks like|i\b.*not sure|haven.?t (tested|verified|checked|run)|did not (test|verify|check|run)|did.?nt (test|verify|check|run)|could you (verify|check|confirm|test)|please (verify|check|confirm|test))\b'
JA_HEDGE='と思います|だと思う|多分|たぶん|おそらく|かもしれ(ない|ません)|未確認|確認していません|テストしていません|確認していない|確認してください|テストしてください|チェックしてください'

# If hedging is present, exit silently — the surface form is honest.
if echo "$LAST_TEXT" | grep -qiE "$EN_HEDGE"; then
    exit 0
fi
if echo "$LAST_TEXT" | grep -qE "$JA_HEDGE"; then
    exit 0
fi

MATCHED_CLAIM=""

if echo "$LAST_TEXT" | grep -qiE "$EN_PATTERNS"; then
    MATCHED_CLAIM=$(echo "$LAST_TEXT" | grep -oiE "$EN_PATTERNS" | head -1)
elif echo "$LAST_TEXT" | grep -qE "$JA_PATTERNS"; then
    MATCHED_CLAIM=$(echo "$LAST_TEXT" | grep -oE "$JA_PATTERNS" | head -1)
fi

[ -z "$MATCHED_CLAIM" ] && exit 0

# Scan the last WINDOW tool-use entries for verification-shaped tools.
# We accept any of the following as evidence that some verification was
# attempted in the session's recent history:
#   - Bash invocations whose command matches verification commands
#   - Read of a log file
#   - Grep over an output destination
# This list is intentionally permissive: the goal is to catch the
# "claimed done without doing anything to check" pattern, not to grade
# every session on the quality of its tests.
VERIFY_COMMAND_PATTERN='pytest|unittest|npm (run )?test|yarn test|go test|cargo test|cargo check|jest|mocha|rspec|phpunit|composer test|mix test|gradle test|mvn test|make test|make check|bin/test|bin/rspec|bundle exec rspec|bundle exec rake test|curl |wget |httpie|http |status check|smoke|verify|sanity|tail -[fn]|less |cat .*\.log|grep .*\.log|systemctl status|docker (ps|logs)|kubectl (get|logs|describe)|psql -c|sqlite3 .*SELECT|redis-cli|nmap |ping |ssh .*-c|ssh .*uptime|ssh .*systemctl|ssh .*docker|ssh .*tail|gh run|gh workflow|git diff --check|git status|node -e .*assert|python -c .*assert|ruby -e .*raise'

VERIFY_TOOL_PATTERN='"name":"Bash"|"name":"Read"|"name":"Grep"|"name":"Glob"'

# Read the last WINDOW tool_use entries from the transcript.
# Each tool_use is inside a message.content block of type=tool_use.
RECENT_TOOL_USES=$(tac "$TRANSCRIPT" 2>/dev/null \
    | grep '"tool_use"' \
    | head -n "$WINDOW")

# Did any recent Bash command match a verification-shaped command?
VERIFICATION_FOUND="0"
if [ -n "$RECENT_TOOL_USES" ]; then
    # Bash commands
    BASH_COMMANDS=$(printf '%s\n' "$RECENT_TOOL_USES" \
        | jq -r '
            select(.message.content) |
            .message.content[]? |
            select(.type=="tool_use" and .name=="Bash") |
            .input.command // empty
        ' 2>/dev/null || true)

    if [ -n "$BASH_COMMANDS" ] && echo "$BASH_COMMANDS" | grep -qiE "$VERIFY_COMMAND_PATTERN"; then
        VERIFICATION_FOUND="1"
    fi

    # Read calls (we treat any Read in the window as plausible verification)
    if [ "$VERIFICATION_FOUND" = "0" ]; then
        if printf '%s\n' "$RECENT_TOOL_USES" | grep -q '"name":"Read"'; then
            # Be stricter: only count Read of log files / output files as verification
            READ_PATHS=$(printf '%s\n' "$RECENT_TOOL_USES" \
                | jq -r '
                    select(.message.content) |
                    .message.content[]? |
                    select(.type=="tool_use" and .name=="Read") |
                    .input.file_path // empty
                ' 2>/dev/null || true)
            if echo "$READ_PATHS" | grep -qiE '\.log|/log/|output|result|coverage|junit|test.*report|/tmp/'; then
                VERIFICATION_FOUND="1"
            fi
        fi
    fi
fi

[ "$VERIFICATION_FOUND" = "1" ] && exit 0

# Detection: completion claim emitted, no verification in recent window.
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

# Log the detection
{
    printf '[%s] completion-claim-without-verification session=%s claim=%q window=%s\n' \
        "$TS" "$SESSION_ID" "$MATCHED_CLAIM" "$WINDOW"
} >> "$LOG_FILE" 2>/dev/null || true

# Emit advisory to stderr — Claude Code surfaces this to the user.
cat >&2 << EOF
[completion-claim-without-verification] The assistant just emitted a completion claim ("$MATCHED_CLAIM") but the last $WINDOW tool calls in this session do not include a verification-shaped tool use (no pytest / npm test / curl / status check / log read). This pattern matches anthropics/claude-code#60177 (12 days, 51 commits, 0 working product). Consider asking the assistant which check actually ran, or run a verification command yourself before acting on the claim.
EOF

exit 0
