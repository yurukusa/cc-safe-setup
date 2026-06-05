#!/bin/bash
# ================================================================
# halt-signal-detector.sh — Warn before further tool calls when the
#                          user's previous message contains a halt
#                          token (stop, やめて, halt, etc.)
# ================================================================
# PURPOSE:
#   When the previous user message in the transcript contains an
#   explicit halt signal, warn that the upcoming tool call may be
#   reframing the user's halt as a renegotiation. Prevents the
#   "continuation bargaining after halt signals" failure mode reported
#   in Issue #55909 (Cowork mode bargaining), Issue #56351 (refusing
#   to stop digging), and Issue #55363 (/ultrareview ignoring stop).
#
# TRIGGER: PreToolUse
# MATCHER: "*"  (all tools)
#
# WHY THIS MATTERS:
#   In Issue #55909, the user said "stop / やめて / use a different
#   browser" multiple times, but the model continued operating and
#   replied with bargaining language ("just let me do this one part",
#   "after you log in, send 'OK' and I'll do the rest"). The expected
#   behaviour after a user halt signal is: zero tool calls in the
#   next turn, no requests for partial cooperation. The original plan
#   does not survive into the next response, even softened.
#
#   This hook detects the halt signal at the input boundary and warns
#   before any tool call is made. It cannot fix the underlying model
#   layer issue, but it removes the bargaining surface from the next
#   turn by surfacing the contradiction to the operator.
#
# WHAT IT CHECKS:
#   1. Read the most recent user message from the transcript
#   2. Search for halt tokens (Japanese and English)
#   3. If a halt token is present, emit a warning to stderr
#   4. If CC_HALT_SIGNAL_BLOCK=1, also exit 2 to block the tool call
#
# OUTPUT:
#   Warning to stderr with a snippet of the matched user text and a
#   reference to Issue #55909. Exit 0 (advisory) by default.
#
# CONFIGURATION:
#   CC_HALT_SIGNAL_BLOCK  — set to "1" to block the tool call (exit 2)
#                          when a halt signal is detected. Default is
#                          advisory only.
#   CC_HALT_SIGNAL_EXTRA  — additional comma-separated halt tokens to
#                          match (case-insensitive). Example: "abort,kill"
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/55909
#   https://github.com/anthropics/claude-code/issues/56351
#   https://github.com/anthropics/claude-code/issues/55363
# ================================================================

set -u

INPUT=$(cat)

# Get transcript path from PreToolUse input
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Find the most recent user message
LAST_USER_LINE=$(grep -h '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)

if [ -z "$LAST_USER_LINE" ]; then
    exit 0
fi

# Extract user text — content may be a string or an array of blocks
USER_TEXT=$(printf '%s' "$LAST_USER_LINE" | jq -r '
    if (.message.content | type) == "string" then
        .message.content
    elif (.message.content | type) == "array" then
        [.message.content[] | select(.type == "text") | .text] | join(" ")
    else
        empty
    end
' 2>/dev/null)

if [ -z "$USER_TEXT" ]; then
    exit 0
fi

# Skip if user text looks like a system-generated nudge (idle prompt, hook output)
if printf '%s' "$USER_TEXT" | grep -qE '^\[idle [0-9]+s|^<system-reminder>|^BLOCKED:'; then
    exit 0
fi

# Halt signal patterns — explicit stop/halt verbs
# Japanese: やめて, やめろ, 止めて, 止まれ, 中断, 中止, ストップ
# English: stop, halt, abort, cease, do not, don't
HALT_BASE='やめて|やめろ|止めて|止まれ|中断|中止|ストップ|\bstop\b|\bhalt\b|\babort\b|\bcease\b|\bdo not\b|\bdon'\''t\b'

# Optional extra patterns from env
EXTRA="${CC_HALT_SIGNAL_EXTRA:-}"
if [ -n "$EXTRA" ]; then
    EXTRA_PATTERN=$(printf '%s' "$EXTRA" | tr ',' '|')
    HALT_PATTERN="${HALT_BASE}|${EXTRA_PATTERN}"
else
    HALT_PATTERN="$HALT_BASE"
fi

# Check for halt signal (case-insensitive)
if printf '%s' "$USER_TEXT" | grep -qiE "$HALT_PATTERN"; then
    SNIPPET=$(printf '%s' "$USER_TEXT" | head -c 160 | tr '\n' ' ')
    cat >&2 <<EOF
🛑 halt-signal-detector: 直前の利用者の応答に停止の合図が含まれています。
  検出した文脈: ${SNIPPET}...
  この道具の呼び出しが、 利用者の停止の合図を「計画の調整の依頼」 として再解釈していないか確認してください。
  「これだけ」「ここだけ」「短い合図を送ってください」 のような部分的な協力の依頼は、 利用者から見ると停止の合図の無視と等価です。
  期待される動き: 次の応答で道具の呼び出しゼロ、 状態の報告と利用者への確認のみ。
  Reference: https://github.com/anthropics/claude-code/issues/55909
EOF
    if [ "${CC_HALT_SIGNAL_BLOCK:-0}" = "1" ]; then
        exit 2
    fi
fi

exit 0
