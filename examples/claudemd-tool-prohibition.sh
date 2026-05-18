#!/bin/bash
# claudemd-tool-prohibition.sh — Block tool calls that the operator's CLAUDE.md
# explicitly prohibits.
#
# Solves: harness-side recognition-without-arrest at the system-prompt layer
#   (issue #60323). The harness injects a `<system-reminder>` suggesting
#   TaskCreate even when the operator's CLAUDE.md says "Do NOT use TaskCreate".
#   The model then has to choose between (a) violating the operator's rule or
#   (b) spending output tokens on a meta-acknowledgment of the conflict.
#
# This hook resolves the conflict deterministically at the runtime layer:
#   it reads the operator's CLAUDE.md, extracts tools the operator has
#   prohibited, and blocks any PreToolUse call to a prohibited tool with
#   a clear message about which rule it violated. The model's articulation
#   of the rule is no longer load-bearing because the hook enforces the
#   rule directly.
#
# How prohibitions are declared in CLAUDE.md
# The hook accepts three common operator-natural formats. Tool names must be
# inside backticks for unambiguous extraction.
#
#   Format 1 — inline prose:
#     Do NOT use `TaskCreate` for session-local work.
#     do not call `TaskList` in this project.
#     never use `TaskUpdate`.
#
#   Format 2 — Japanese prose:
#     `TaskCreate` を使うな
#     `TaskList` の使用は禁止
#
#   Format 3 — list under a "Forbidden Tools" / 禁止 header (within 20 lines):
#     ## Forbidden Tools
#     - `TaskCreate`
#     - `TaskList`
#
# TRIGGER: PreToolUse
# MATCHER: ""
#
# Configuration:
#   CC_TOOL_PROHIBITION_DISABLE=1   Disable the hook entirely.
#   CC_TOOL_PROHIBITION_WARN=1      Advisory mode: warn to stderr but exit 0
#                                   instead of blocking. Default: block (exit 2).
#   CC_CLAUDEMD_PATH=/path/to/file  Override CLAUDE.md search path.

set -u

[ "${CC_TOOL_PROHIBITION_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

# Find CLAUDE.md. Search order: explicit override, project CLAUDE.md, parent
# directory, user-global ~/.claude/CLAUDE.md.
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

# Extract prohibited tool names from CLAUDE.md.
# We collect tool names in two passes:
#   Pass 1 — prose patterns matching "do not use `X`" / "禁止" / etc.
#   Pass 2 — list items under headers that mention forbidden / prohibited / 禁止.
FORBIDDEN_LIST=""

# Pass 1: prose prohibitions
PROSE=$(grep -iE '(do[ -]not (use|call)|never (use|call)|禁止|を使うな|使用は禁止)' "$CLAUDEMD" 2>/dev/null || true)
if [ -n "$PROSE" ]; then
    # Extract backtick-quoted tokens from these lines
    EXTRACTED=$(printf '%s\n' "$PROSE" | grep -oE '`[A-Za-z][A-Za-z0-9_-]+`' 2>/dev/null | sed 's/`//g' | sort -u || true)
    if [ -n "$EXTRACTED" ]; then
        FORBIDDEN_LIST="$EXTRACTED"
    fi
fi

# Pass 2: list items under "Forbidden Tools" / "Prohibited Tools" / "禁止" headers
# (only the 20 lines following the header are scanned)
HEADER_LINES=$(grep -inE '^#+ +(forbidden tools|prohibited tools|禁止する道具|使用禁止)' "$CLAUDEMD" 2>/dev/null | cut -d: -f1 || true)
if [ -n "$HEADER_LINES" ]; then
    for ln in $HEADER_LINES; do
        SECTION=$(sed -n "${ln},$((ln+20))p" "$CLAUDEMD" 2>/dev/null || true)
        ITEMS=$(printf '%s\n' "$SECTION" | grep -E '^[ ]*[-*] +`[A-Za-z][A-Za-z0-9_-]+`' 2>/dev/null | grep -oE '`[A-Za-z][A-Za-z0-9_-]+`' | sed 's/`//g' || true)
        if [ -n "$ITEMS" ]; then
            FORBIDDEN_LIST="${FORBIDDEN_LIST}${FORBIDDEN_LIST:+$'\n'}${ITEMS}"
        fi
    done
fi

[ -z "$FORBIDDEN_LIST" ] && exit 0

# Normalise and check whether the active tool is in the forbidden set.
FORBIDDEN_LIST=$(printf '%s\n' "$FORBIDDEN_LIST" | sort -u)

if printf '%s\n' "$FORBIDDEN_LIST" | grep -qFx -- "$TOOL_NAME"; then
    if [ "${CC_TOOL_PROHIBITION_WARN:-0}" = "1" ]; then
        echo "⚠ claudemd-tool-prohibition: tool '$TOOL_NAME' is prohibited by $CLAUDEMD" >&2
        echo "  Continuing (advisory mode). Set CC_TOOL_PROHIBITION_WARN=0 to block." >&2
        exit 0
    fi
    echo "BLOCKED: tool '$TOOL_NAME' is prohibited by your CLAUDE.md ($CLAUDEMD)." >&2
    echo "  The harness injected a suggestion or workflow that conflicts with your operator-scope rule." >&2
    echo "  See issue #60323 for the failure shape (system-reminder vs CLAUDE.md prohibition)." >&2
    echo "  To allow this call temporarily, run with CC_TOOL_PROHIBITION_WARN=1 (advisory) or CC_TOOL_PROHIBITION_DISABLE=1." >&2
    exit 2
fi

exit 0
