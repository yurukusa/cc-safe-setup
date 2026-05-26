#!/bin/bash
# authorized-reconfirmation-detector.sh — Measure how often
# AskUserQuestion fires on an action that the operator's prior turn
# already authorized.
#
# Solves: anthropics/claude-code#61929 (Claude Code makes major design
# decisions silently but asks for confirmation on trivial things),
# specifically case (3) in the three-way split articulated in
# https://github.com/anthropics/claude-code/issues/61929#issuecomment-4549798175 :
#
#   (1) Genuine fork — model has multiple plausible paths; AUQ is correct
#   (2) Articulation-surface mis-bound — model has the answer (marks
#       "(Recommended)") and uses AUQ to describe its choice rather than
#       delegate it
#   (3) Authorized re-confirmation — operator already said "do X" in the
#       prior turn; model opens AUQ asking "Should I do X?" with
#       "(Recommended) yes"
#
# This hook does not block. It measures. The output is one structured
# log line per detected case (3) — turn timestamp, AUQ question text,
# matched verb stem, user-message excerpt. That log file becomes the
# empirical foundation for the eventual UserPromptSubmit-side intent
# classifier (case 3's primary fix). Case (2) cannot be addressed at
# Stop without already having shown the menu; that one needs PreToolUse
# visibility into the AUQ preamble (#61983) to convert the menu into an
# inline articulation.
#
# Detection signature (all three required to log):
#   a) An AskUserQuestion tool call exists in the latest assistant turn.
#   b) At least one of its options carries a "(Recommended)" marker
#      (English) or "推奨" (Japanese).
#   c) The most recent user message contains a content word (length >= 4)
#      that also appears in the AUQ question text. Common stopwords are
#      filtered. This is the "operator already named the action" echo.
#
# False positives are intentionally tolerated for measurement — the
# detector emits an advisory log line, never an exit code, never a block.
# An operator may have authorized an irreversible action and still want
# AUQ to fire as a safety re-check; that case will show up in the log
# and informs the classifier's eventual exclusion list.
#
# Related:
#   #61337 (mhernz) — /goal-mode authorization is structurally
#                     indistinguishable from prior-message authorization;
#                     the load-bearing axis that lets one classifier
#                     address both with the same signal.
#   #61983          — preamble visibility constraint that blocks the
#                     PreToolUse-AUQ menu-to-articulation conversion
#                     (case 2 territory).
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_AUTH_RECONF_LOG       log file path
#                            (default: ~/.claude/audit/authorized-reconfirmation.log)
#   CC_AUTH_RECONF_DISABLE   set to "1" to disable entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/authorized-reconfirmation-detector.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_AUTH_RECONF_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

LOG_FILE="${CC_AUTH_RECONF_LOG:-${HOME}/.claude/audit/authorized-reconfirmation.log}"

# Locate AskUserQuestion calls in the latest assistant turn.
# Transcript shape varies across Claude Code versions; try several keys.
AUQ_CALLS=$(printf '%s' "$INPUT" | jq -c '
    def latest_assistant:
        ([ .transcript[]? | select(.role == "assistant") ] | .[-1])
        // .last_assistant_message
        // {};
    def auq_filter(arr):
        [ arr[]?
          | select((.name // .tool_name // "") == "AskUserQuestion")
          | (.input // .tool_input // {}) ];
    (latest_assistant) as $a
    | (auq_filter($a.tool_calls // [])) as $from_tc
    | (auq_filter($a.content // []))    as $from_content
    | ($from_tc + $from_content)
' 2>/dev/null)

# Nothing to measure if no AUQ this turn.
if [ -z "$AUQ_CALLS" ] || [ "$AUQ_CALLS" = "null" ] || [ "$AUQ_CALLS" = "[]" ]; then
    exit 0
fi

# Find the most recent user (operator) message text.
USER_TEXT=$(printf '%s' "$INPUT" | jq -r '
    ([ .transcript[]? | select(.role == "user") ] | .[-1]) as $u
    | ($u.content
        | if   type == "string" then .
          elif type == "array"  then [ .[]? | (.text // .content // "") ] | join(" ")
          else "" end)
' 2>/dev/null)

if [ -z "$USER_TEXT" ] || [ "$USER_TEXT" = "null" ]; then
    USER_TEXT=$(printf '%s' "$INPUT" | jq -r '.last_user_message // empty' 2>/dev/null)
fi

# No user text → cannot compare → silent exit.
if [ -z "$USER_TEXT" ] || [ "$USER_TEXT" = "null" ]; then
    exit 0
fi

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Lowercase the user text once.
UT=$(printf '%s' "$USER_TEXT" | tr '[:upper:]' '[:lower:]')

STOPWORDS='^(should|would|could|with|that|this|from|into|your|have|will|been|were|then|than|when|what|which|while|where|there|please|claude|about|just|like|some|also|even|only|over|under|after|before|both|each|same|other|those|these|right|wrong|maybe|going|doing|done|need|want|sure|okay|yeah|nope|true|false)$'

# Walk each AUQ call.
printf '%s' "$AUQ_CALLS" | jq -c '.[]' 2>/dev/null | while read -r CALL; do
    # Skip empty calls.
    [ -z "$CALL" ] || [ "$CALL" = "null" ] && continue

    # Recommended-option marker check.
    HAS_RECOMMENDED=$(printf '%s' "$CALL" | jq -r '
        (.questions // []) | .[]? | (.options // []) | .[]?
        | ((.label // "") + " " + (.description // ""))
    ' 2>/dev/null | grep -ciE '\(recommended\)|推奨|^recommended\b|\brecommended:' || true)
    HAS_RECOMMENDED=${HAS_RECOMMENDED:-0}

    # No recommended marker → likely case (1) genuine fork. Skip.
    [ "$HAS_RECOMMENDED" -eq 0 ] && continue

    # Enumerate every question text in this call.
    QUESTIONS=$(printf '%s' "$CALL" | jq -r '
        (.questions // [{question: (.question // "")}])
        | .[]? | (.question // "")
        | select(length > 0)
    ' 2>/dev/null)

    [ -z "$QUESTIONS" ] && continue

    while IFS= read -r Q; do
        [ -z "$Q" ] && continue

        # Content words (length >= 4, alpha) from the AUQ question.
        QWORDS=$(printf '%s' "$Q" | tr '[:upper:]' '[:lower:]' \
            | grep -oE '[a-z]{4,}' | sort -u \
            | grep -vE "$STOPWORDS" || true)

        [ -z "$QWORDS" ] && continue

        # Find at least one content word that also appears in the user
        # message.
        MATCHED_WORD=""
        while IFS= read -r W; do
            [ -z "$W" ] && continue
            if printf '%s' "$UT" | grep -qw "$W"; then
                MATCHED_WORD="$W"
                break
            fi
        done <<< "$QWORDS"

        [ -z "$MATCHED_WORD" ] && continue

        # Detected. Emit a structured log line.
        TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
        USER_EXCERPT=$(printf '%s' "$USER_TEXT" | tr '\n' ' ' | head -c 240)
        ENTRY=$(jq -nc \
            --arg ts "$TS" \
            --arg q "$Q" \
            --arg word "$MATCHED_WORD" \
            --arg user_excerpt "$USER_EXCERPT" \
            '{
                timestamp: $ts,
                event: "authorized_reconfirmation_detected",
                auq_question: $q,
                matched_word: $word,
                user_excerpt: $user_excerpt
            }' 2>/dev/null)

        [ -n "$ENTRY" ] && echo "$ENTRY" >> "$LOG_FILE"
    done <<< "$QUESTIONS"
done

exit 0
