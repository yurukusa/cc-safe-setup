#!/bin/bash
# strip-coauthored-by.sh — Warn about (or block) unwanted commit-message trailers
#
# Solves two trailers Claude appends to commits without the user asking:
#   1. Co-Authored-By: ...Claude/Anthropic — branding without consent.
#      See: https://github.com/anthropics/claude-code/issues/29999
#   2. Claude-Session: https://claude.ai/code/session_<id> — leaks a PRIVATE
#      session identifier into commit history, which is published to public
#      repos. Data minimisation should apply by default.
#      See: https://github.com/anthropics/claude-code/issues/69669
#
# Mechanism: this is a PreToolUse hook, which can BLOCK a tool call (exit 2)
# but cannot rewrite it — so it cannot silently strip the trailer. Instead it
# bounces the commit back so the model removes the trailer before committing.
#   - Session-id leak: blocked by default (exit 2) — it is a privacy issue.
#   - Co-Authored-By:  warn-only (exit 0) — it is a preference, user decides.
# Note: only the `git commit -m "<msg>"` form carries the message in the
# command string. Commits via an editor or `-F <file>` are not visible here.
#
# TRIGGER: PreToolUse
# MATCHER: Bash
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git commit *)",
#         "command": "~/.claude/hooks/strip-coauthored-by.sh"
#       }]
#     }]
#   }
# }
#
# Config:
#   CC_ALLOW_COAUTHOR=1         allow Co-Authored-By trailers (default: 0 = warn)
#   CC_ALLOW_SESSION_TRAILER=1  allow the session-id URL trailer (default: 0 = block)

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-strip-coauthored-by-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [strip-coauthored-by]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only inspect git commit commands. Match at the start or after a chaining
# operator (so `cd repo && git commit ...` is covered too).
echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+commit' || exit 0

# 1. Private session-id leak — block by default (privacy issue).
#    The harness emits `Claude-Session: https://claude.ai/code/session_<id>`.
if echo "$COMMAND" | grep -qiE 'claude\.ai/code/session|Claude-Session:'; then
    if [ "${CC_ALLOW_SESSION_TRAILER:-0}" != "1" ]; then
        echo "✖ Blocked: commit message contains a private Claude session URL" >&2
        echo "  (Claude-Session: https://claude.ai/code/session_...)." >&2
        echo "  This publishes a private session identifier to your repo history." >&2
        echo "  Remove that trailer from the commit message, then retry." >&2
        echo "  Set CC_ALLOW_SESSION_TRAILER=1 to allow it. See issue #69669." >&2
        exit 2
    fi
fi

# 2. Co-Authored-By branding — warn only (the user decides).
if echo "$COMMAND" | grep -qiE 'Co-Authored-By.*(Claude|Anthropic|noreply@anthropic)'; then
    if [ "${CC_ALLOW_COAUTHOR:-0}" = "1" ]; then
        exit 0
    fi
    echo "⚠ Co-Authored-By trailer detected in commit message" >&2
    echo "  Set CC_ALLOW_COAUTHOR=1 to allow, or remove the trailer." >&2
    echo "  See: https://github.com/anthropics/claude-code/issues/29999" >&2
    # Warn but don't block — user can decide
    exit 0
fi

exit 0
