#!/bin/bash
# forbidden-response-phrase-detector.sh — Detect operator-declared forbidden
# phrases in the assistant's final response.
#
# Solves: response-layer recognition-without-arrest where a CLAUDE.md rule
#   prohibiting specific opening or filler phrases is acknowledged by the
#   model and then violated on the next turn (issue #60339).
#
# How it works: Stop hook that reads the operator's CLAUDE.md, extracts
#   forbidden response phrases from three operator-natural formats, and
#   checks whether the final assistant response contains any of them. The
#   model's articulation of the rule is no longer load-bearing because the
#   hook reads the rule directly and enforces it at response finalisation.
#
# How prohibitions are declared in CLAUDE.md
# The hook accepts three operator-natural formats. Forbidden phrases must
# be inside backticks (or smart quotes) for unambiguous extraction. The
# match is case-insensitive against the response text by default.
#
#   Format 1 — inline prose:
#     Do NOT open replies with `You're right` or `Great point`.
#     never say `I apologize` in responses.
#
#   Format 2 — Japanese prose:
#     `了解しました` を返信の冒頭で使うな
#     `はい、その通りです` の使用は禁止
#
#   Format 3 — list under a "Forbidden Response Phrases" / 禁止 header:
#     ## Forbidden Response Phrases
#     - `You're right`
#     - `Great point`
#     - `I apologize`
#
# TRIGGER: Stop
# MATCHER: ""
#
# Configuration:
#   CC_FORBIDDEN_PHRASE_DISABLE=1   Disable the hook entirely.
#   CC_FORBIDDEN_PHRASE_BLOCK=1     Exit non-zero (exit 2) on match. Default:
#                                   advisory (warn to stderr, exit 0).
#   CC_FORBIDDEN_PHRASE_OPEN_ONLY=1 Only check the first 200 chars of the
#                                   response (filler-phrase pattern).
#   CC_CLAUDEMD_PATH=/path          Override CLAUDE.md search path.
#   CC_FORBIDDEN_PHRASE_CASE_SENSITIVE=1  Case-sensitive match. Default off.

set -u

[ "${CC_FORBIDDEN_PHRASE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Extract the last assistant response from the transcript.
LAST_ASSISTANT=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"role":"assistant"' || true)
[ -z "$LAST_ASSISTANT" ] && exit 0

RESPONSE_TEXT=$(printf '%s' "$LAST_ASSISTANT" | jq -r '
  if .message.content then
    (.message.content | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end)
  elif .content then
    (.content | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end)
  else
    empty
  end
' 2>/dev/null)

[ -z "$RESPONSE_TEXT" ] && exit 0

# Find CLAUDE.md.
CLAUDEMD=""
if [ -n "${CC_CLAUDEMD_PATH:-}" ] && [ -r "$CC_CLAUDEMD_PATH" ]; then
    CLAUDEMD="$CC_CLAUDEMD_PATH"
else
    for candidate in "CLAUDE.md" ".claude/CLAUDE.md" "../CLAUDE.md" "$HOME/.claude/CLAUDE.md"; do
        if [ -r "$candidate" ]; then
            CLAUDEMD="$candidate"
            break
        fi
    done
fi
[ -z "$CLAUDEMD" ] && exit 0

# Extract forbidden phrases.
FORBIDDEN_LIST=""

# Pass 1: prose prohibitions referring to response/reply behaviour
PROSE=$(grep -iE '(do[ -]not (open|start|begin|use|say)|never (say|use|open|begin)|を返信|を使うな|の使用は禁止|返信の冒頭|filler|opening)' "$CLAUDEMD" 2>/dev/null || true)
if [ -n "$PROSE" ]; then
    # Extract backtick-quoted phrases (single backtick form) and curly quotes
    EXTRACTED=$(printf '%s\n' "$PROSE" | grep -oE '`[^`]+`|"[^"]+"' 2>/dev/null | sed -e 's/^`//' -e 's/`$//' -e 's/^"//' -e 's/"$//' | sort -u || true)
    if [ -n "$EXTRACTED" ]; then
        FORBIDDEN_LIST="$EXTRACTED"
    fi
fi

# Pass 2: list items under "Forbidden Response Phrases" / "Forbidden Phrases" / 禁止 headers
HEADER_LINES=$(grep -inE '^#+ +(forbidden (response )?phrases|forbidden replies|prohibited (response )?phrases|filler phrases|禁止する応答|応答の禁止)' "$CLAUDEMD" 2>/dev/null | cut -d: -f1 || true)
if [ -n "$HEADER_LINES" ]; then
    for ln in $HEADER_LINES; do
        SECTION=$(sed -n "${ln},$((ln+20))p" "$CLAUDEMD" 2>/dev/null || true)
        ITEMS=$(printf '%s\n' "$SECTION" | grep -E '^[ ]*[-*] +`[^`]+`' 2>/dev/null | grep -oE '`[^`]+`' | sed 's/`//g' || true)
        if [ -n "$ITEMS" ]; then
            FORBIDDEN_LIST="${FORBIDDEN_LIST}${FORBIDDEN_LIST:+$'\n'}${ITEMS}"
        fi
    done
fi

[ -z "$FORBIDDEN_LIST" ] && exit 0

FORBIDDEN_LIST=$(printf '%s\n' "$FORBIDDEN_LIST" | sort -u)

# Decide scope.
if [ "${CC_FORBIDDEN_PHRASE_OPEN_ONLY:-0}" = "1" ]; then
    SCOPE=$(printf '%s' "$RESPONSE_TEXT" | head -c 200)
else
    SCOPE="$RESPONSE_TEXT"
fi

# Match each phrase.
VIOLATIONS=""
GREP_FLAGS="-F"
if [ "${CC_FORBIDDEN_PHRASE_CASE_SENSITIVE:-0}" != "1" ]; then
    GREP_FLAGS="${GREP_FLAGS}i"
fi

while IFS= read -r phrase; do
    [ -z "$phrase" ] && continue
    if printf '%s' "$SCOPE" | grep -q $GREP_FLAGS -- "$phrase" 2>/dev/null; then
        VIOLATIONS="${VIOLATIONS}${VIOLATIONS:+$'\n'}${phrase}"
    fi
done <<< "$FORBIDDEN_LIST"

[ -z "$VIOLATIONS" ] && exit 0

# Emit warning.
echo "⚠ forbidden-response-phrase-detector: assistant response contained phrases prohibited by $CLAUDEMD:" >&2
printf '%s\n' "$VIOLATIONS" | while IFS= read -r line; do
    [ -n "$line" ] && echo "  - \"$line\"" >&2
done
echo "  See issue #60339 for the failure shape (CLAUDE.md rule re-violated immediately after correction)." >&2

if [ "${CC_FORBIDDEN_PHRASE_BLOCK:-0}" = "1" ]; then
    exit 2
fi

exit 0
