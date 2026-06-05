#!/bin/bash
# runtime-binary-change-detector.sh — Alert when the Claude Code binary changes between sessions.
#
# Solves: Operators who customize their workflow (hooks, slash commands, skills,
#         system-prompt patches) can have behavior shift silently when the Claude
#         Code binary is updated. Public discussion of this pattern includes
#         matheusmoreira's Tell HN "Claude Code now allows Anthropic to remotely
#         inject system prompts" — operators want a between-session signal that
#         something changed, prompting a behavior re-verification before relying
#         on prior workflow assumptions.
#
# How it works: On SessionStart, compute a fingerprint of the resolved `claude`
#   binary (path + --version + size_mtime), compare against the fingerprint
#   stored from the previous session, and print an advisory warning to stderr if
#   they differ. State is stored at ~/.claude/runtime-binary-state.txt.
#
# This is an advisory hook (exit 0 in all cases); it never blocks. The signal
# tells the operator to verify hooks, slash commands, and skills still behave
# as expected after the binary changed.
#
# TRIGGER: SessionStart
# MATCHER: "" (all sessions)
#
# Env knobs:
#   CC_BINARY_DETECTOR_SILENT=1 — suppress the alert (useful in CI / automation
#                                 where the alert is logged elsewhere)

INPUT=$(cat 2>/dev/null || echo "{}")
EVENT=$(echo "$INPUT" | jq -r '.event // .hook_event_name // empty' 2>/dev/null)

# Only run on session start; let other events pass.
case "$EVENT" in
  session_start|SessionStart|"") ;;
  *) exit 0 ;;
esac

STATE_FILE="${HOME}/.claude/runtime-binary-state.txt"
mkdir -p "$(dirname "$STATE_FILE")"

# Locate the claude binary. Bail silently if it's not on PATH — this hook
# shouldn't error in environments where Claude Code is invoked by absolute
# path or through a wrapper.
CLAUDE_BIN=$(command -v claude 2>/dev/null)
[ -z "$CLAUDE_BIN" ] && exit 0

# Resolve symlinks so version managers (asdf / volta / nvm) don't produce a
# spurious change every session from re-shimmed paths.
RESOLVED_BIN=$(readlink -f "$CLAUDE_BIN" 2>/dev/null || echo "$CLAUDE_BIN")

# Version string (best-effort; some wrappers reject --version).
VERSION=$("$RESOLVED_BIN" --version 2>/dev/null | head -1 | tr -d '\r' | head -c 200)
[ -z "$VERSION" ] && VERSION="version-unavailable"

# Size + mtime as a lightweight content fingerprint. Full sha256 would be more
# correct but is overkill at SessionStart latency; size+mtime catches every
# update path that swaps the binary (npm install, brew upgrade, manual replace).
if SIZE_MTIME=$(stat -c "%s_%Y" "$RESOLVED_BIN" 2>/dev/null); then
  :
elif SIZE_MTIME=$(stat -f "%z_%m" "$RESOLVED_BIN" 2>/dev/null); then
  :
else
  SIZE_MTIME="stat-unavailable"
fi

CURRENT_STATE="${RESOLVED_BIN}|${VERSION}|${SIZE_MTIME}"

# First-session bootstrap: record state, no warning.
if [ ! -f "$STATE_FILE" ]; then
  printf "%s\n" "$CURRENT_STATE" > "$STATE_FILE"
  exit 0
fi

PREV_STATE=$(head -1 "$STATE_FILE" 2>/dev/null)

if [ "$PREV_STATE" != "$CURRENT_STATE" ] && [ "${CC_BINARY_DETECTOR_SILENT:-}" != "1" ]; then
  # Decompose for readability.
  PREV_VER=$(printf "%s" "$PREV_STATE" | awk -F'|' '{print $2}')
  CURR_VER=$(printf "%s" "$CURRENT_STATE" | awk -F'|' '{print $2}')

  {
    echo "⚠ Claude Code binary changed since the previous session."
    if [ "$PREV_VER" != "$CURR_VER" ]; then
      echo "   ${PREV_VER}  →  ${CURR_VER}"
    else
      echo "   Same --version string, but the binary's size or mtime moved."
      echo "   Path: ${RESOLVED_BIN}"
    fi
    echo "   Release notes: https://github.com/anthropics/claude-code/releases"
    echo "   Verify before relying on prior behavior:"
    echo "     1. Your custom hooks still fire on the expected events"
    echo "     2. Slash commands return the same shape"
    echo "     3. Skills load with the same precedence"
    echo "     4. System-prompt patches (if any) survived the update"
    echo "   Silence with: export CC_BINARY_DETECTOR_SILENT=1"
  } >&2
fi

# Always update state. Even on silent-mode the new fingerprint should be stored
# so the next non-silent session compares against the correct baseline.
printf "%s\n" "$CURRENT_STATE" > "$STATE_FILE"

exit 0
