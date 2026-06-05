#!/bin/bash
# ai-slop-punctuation-arrest.sh — Refuse Write/Edit to public-text files
# that contain AI-slop punctuation patterns the operator has chosen to
# exclude — em-dash (—) and the double-hyphen substitute the model often
# emits when prose-instructed to "stop using em dashes".
#
# Background: the punctuation patterns that read as machine-authored prose
# are recognised widely enough that they function as a heuristic-trust
# signal against the artefact's writer (operator credibility cost), even
# when the content itself is honest and substantive. The most-cited
# offenders are em-dash (—) and its close substitute the double-hyphen
# (` -- ` in prose context).
#
# The active failure mode this hook addresses is the *substitution-by-
# default* variant of recognition-without-arrest (@suwayama's second
# comment on #60226): the operator says "stop using em-dashes", the model
# acknowledges the rule at the recognition layer, and emits double-hyphens
# in lieu — a near-substitute that satisfies the literal rule and violates
# the operator's intent. This is the punctuation-surface instance of the
# substitution mechanism @suwayama named on the Spotify-playlist case.
#
# This hook is not opinionated about whether you should ban em-dashes. It
# is opinionated that *if* you choose to ban them, the ban must hold under
# the model's tendency to substitute — the runtime gate must catch both
# the original and the near-substitute.
#
# Background from the customer pain side: this hook was prompted by a
# 2026-05-20 r/ClaudeAI thread ("I told Claude to stop using em dashes. It
# happily obliged...") in which the operator reported the substitution
# failure ("Now Claude is using double hyphens in lieu of em dashes") and
# explicitly asked for runtime defences.
#
# Related Reports:
#   #60226 (@suwayama) — recognition-without-arrest framework, and
#                        substitution-by-default variant in the second
#                        comment of that thread
#   #60506 (@zean89)   — six-day drift across artefact emissions
#
# TRIGGER: PreToolUse
# MATCHER: Write|Edit
#
# HOW IT WORKS:
#   1. Reads PreToolUse input via stdin.
#   2. For Write/Edit, matches the target path against the configured
#      file-type filter (default: markdown, .md, .mdx, .markdown).
#   3. Scans the artefact content for em-dash (—) and the double-hyphen
#      substitute in prose context (space-dash-dash-space).
#   4. Skips code-block content (between fenced ``` blocks) and inline
#      code (between ` `), so command-line flags and code samples inside
#      a markdown file do not false-positive.
#   5. If any banned pattern survives the skip, exits 2 with a stderr
#      reminder naming the matched pattern and the substitution-by-default
#      mechanism. A content-hash cache (default 600s) lets a re-emission
#      pass through if the agent stands by the artefact deliberately.
#
# CONFIGURATION (environment variables):
#   CC_AI_SLOP_DISABLE              set to "1" to disable the gate
#   CC_AI_SLOP_STATE_DIR            default /tmp/cc-ai-slop-cache
#   CC_AI_SLOP_CACHE_TTL_SECONDS    default 600 — same-hash re-emit window
#   CC_AI_SLOP_FILE_PATTERNS        default built-in — regex of file paths
#                                                       to gate (case-insensitive)
#   CC_AI_SLOP_PUNCT_PATTERNS       default built-in — pipe-separated
#                                                       extended-regex patterns
#                                                       of banned punctuation
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Write|Edit",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/ai-slop-punctuation-arrest.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_AI_SLOP_DISABLE:-0}" = "1" ] && exit 0

# OPT-IN: this gate BLOCKS Write/Edit to markdown containing em-dash or "--",
# which are legitimate punctuation in normal prose (English and Japanese), so a
# default-on block would arrest ordinary documentation writing. Off unless
# explicitly enabled. Set CC_AI_SLOP_ENABLE=1 to turn it on.
[ "${CC_AI_SLOP_ENABLE:-0}" = "1" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

STATE_DIR="${CC_AI_SLOP_STATE_DIR:-/tmp/cc-ai-slop-cache}"
CACHE_TTL="${CC_AI_SLOP_CACHE_TTL_SECONDS:-600}"

# Default file filter: markdown variants
DEFAULT_FILES='\.(md|mdx|markdown|mkd|txt)$'
FILE_PATTERNS="${CC_AI_SLOP_FILE_PATTERNS:-$DEFAULT_FILES}"

# Default punctuation patterns:
#   em-dash:   the literal character —
#   double-hyphen substitute: space, dash, dash, space (in prose context)
#                            or word-dash-dash-word (attached substitute)
DEFAULT_PUNCT='—| -- |[[:alnum:]]--[[:alnum:]]'
PUNCT_PATTERNS="${CC_AI_SLOP_PUNCT_PATTERNS:-$DEFAULT_PUNCT}"

mkdir -p "$STATE_DIR" 2>/dev/null || true

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

case "$TOOL_NAME" in
    Write|Edit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# File-type filter
printf '%s' "$FILE_PATH" | grep -Eiq "$FILE_PATTERNS" || exit 0

# Extract the content (Write) or new_string (Edit)
ARTEFACT_BODY=""
if [ "$TOOL_NAME" = "Write" ]; then
    ARTEFACT_BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
else
    ARTEFACT_BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
fi
[ -z "$ARTEFACT_BODY" ] && exit 0

# Strip code blocks (```…```) and inline code (`…`) so command-line flags
# and code samples in the document do not false-positive.
BODY_FOR_SCAN=$(printf '%s' "$ARTEFACT_BODY" \
    | awk 'BEGIN{in_fence=0} /^```/{in_fence=!in_fence; next} !in_fence{print}' \
    | sed 's|`[^`]*`||g')

# Does the surviving prose carry a banned punctuation pattern?
if ! printf '%s' "$BODY_FOR_SCAN" | grep -Eq "$PUNCT_PATTERNS"; then
    exit 0
fi

# Hash dedup: if the same content was just re-emitted, the agent has
# considered the gate and stands by the artefact — let it pass.
HASH=$(printf '%s' "$ARTEFACT_BODY" | sha256sum 2>/dev/null | awk '{print $1}')
[ -z "$HASH" ] && exit 0

CACHE_FILE="$STATE_DIR/$HASH"
NOW=$(date +%s)
if [ -f "$CACHE_FILE" ]; then
    CACHED_AT=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - CACHED_AT))
    if [ "$AGE" -lt "$CACHE_TTL" ]; then
        exit 0
    fi
fi
echo "$NOW" > "$CACHE_FILE"
find "$STATE_DIR" -type f -mmin +1440 -delete 2>/dev/null || true

# Surface the first matched pattern for the reminder
MATCHED=$(printf '%s' "$BODY_FOR_SCAN" | grep -Eo "$PUNCT_PATTERNS" | head -1)

cat >&2 <<EOF
<system-reminder>
AI-SLOP PUNCTUATION DETECTED in $FILE_PATH — pattern matched: "$MATCHED"

This gate exists because banning em-dash (—) at the prose layer alone
fails under the substitution-by-default mechanism (@suwayama, #60226):
when the operator says "stop using em-dashes", the model often acknowledges
at the recognition layer and emits the near-substitute (double-hyphen,
" -- ") that satisfies the literal rule and violates the intent.

Both the original and the near-substitute are gated here.

To resolve:

  1. Replace em-dash (—) with a natural punctuation mark for the language
     and register: colon, comma, period, or semicolon depending on the
     pause and the syntactic role the dash was carrying.

  2. Replace double-hyphen substitutes (" -- " in prose) with the same
     natural punctuation. If a double-hyphen is appearing as a
     command-line flag inside a code block (\`--flag\`) or fenced code,
     wrap it as code — the gate's body scan strips code blocks and inline
     code before matching, so a properly-fenced flag will not trigger.

  3. If the punctuation is intentional (technical document quoting
     legitimate uses, retrospective analysis, etc.), re-emit the same
     content within ${CACHE_TTL}s and the hash-match will let it through
     once, or set CC_AI_SLOP_DISABLE=1 for the session.

To narrow the scope (e.g. only flag em-dash and not double-hyphens), set
CC_AI_SLOP_PUNCT_PATTERNS to a custom regex.
To narrow the file types (e.g. only README and CHANGELOG), set
CC_AI_SLOP_FILE_PATTERNS to a custom regex.
</system-reminder>
EOF

exit 2
