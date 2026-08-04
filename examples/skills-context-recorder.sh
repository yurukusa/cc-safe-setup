#!/bin/bash
# skills-context-recorder.sh — Record active skill at each user prompt for hook integration
#
# Background:
#   Claude Code's Skills feature (v2.x) does not expose which skill is active
#   during a given tool call to PreToolUse / PostToolUse hooks. Issue #62108
#   asks for an `active_skill` field in hook input. Issue #62078 asks for an
#   env var exposing the current skill name. Neither is implemented.
#
#   The workaround is to record skill activations operator-side. When a user
#   invokes a skill via `/<skill-name>` at the start of their prompt, this hook
#   captures the name and persists it to a per-session log. Other hooks can
#   read the log to know the most recent skill in the current session — the
#   closest operator-side approximation of the active_skill field.
#
#   The hook also captures auto-loaded skills mentioned in the prompt via
#   `[skill: name]` markers (some skills inject this on activation, others
#   don't — this is best-effort and pairs with the slash-command path).
#
#   Reference:
#     #62108 — active_skill field request (PreToolUse hook input)
#     #62078 — env var request for current skill name
#     Skills cluster field guide: https://gist.github.com/yurukusa/d00b2d32505ef67572baacbd6fad3d77
#
# What this hook does:
#   On UserPromptSubmit, parse the prompt's first non-blank line for one of:
#     - `/<skill-name>` at column 0 (canonical slash-command invocation)
#     - `[skill: <skill-name>]` or `<skill name="...">` markers (skill self-announce)
#   When matched, append a 4-field pipe-delimited record to a per-session log:
#     TIMESTAMP_ISO8601 | SESSION_ID | SOURCE | SKILL_NAME
#   where SOURCE is `slash` (slash command), `marker` (in-prompt marker), or
#   `manual` (operator override via env var CC_ACTIVE_SKILL).
#
#   Default log: ~/.claude/skills-context.log (session-tagged in the SESSION_ID field).
#   Companion helper script (cc-active-skill) at the bottom of this file's docs
#   can be sourced to read "current skill for session X" from any other hook.
#
# When this hook does NOT record:
#   - CC_SKILLS_CONTEXT_RECORDER_DISABLE=1
#   - The user prompt does not contain a recognizable skill invocation pattern
#   - The user prompt is empty or unparseable
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "UserPromptSubmit": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/skills-context-recorder.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_SKILLS_CONTEXT_RECORDER_DISABLE=1   — never log
#   CC_SKILLS_CONTEXT_RECORDER_QUIET=1     — log silently (no stderr advisory)
#   CC_SKILLS_CONTEXT_LOG_PATH=<path>      — override default log location
#   CC_SKILLS_CONTEXT_MAX_LINES=<n>        — log rotation threshold (default 1000)
#   CC_ACTIVE_SKILL=<name>                 — operator override; recorded as source=manual
#
# Reading the log from another hook (workaround for the missing active_skill field):
#   most_recent_skill_for_session() {
#     local session_id="$1"
#     local log="${CC_SKILLS_CONTEXT_LOG_PATH:-$HOME/.claude/skills-context.log}"
#     grep "|${session_id}|" "$log" 2>/dev/null | tail -1 | awk -F'|' '{print $4}'
#   }
#
# Privacy: the hook records skill names only (no prompt content, no tool args).
# Skill names are human-chosen identifiers — typically short ASCII strings.
#
# The registration was missing from this header. The installer reads TRIGGER
# and MATCHER from here and falls back to PreToolUse / Bash when both are
# absent, so this hook was being registered at a moment where the field it
# reads is always empty: it installed, it appeared in the settings, and it
# did nothing. Measured 2026-08-04 across examples/: 14 files were like this.
# TRIGGER: UserPromptSubmit
# MATCHER: ""

set -u

# Disable path
if [ "${CC_SKILLS_CONTEXT_RECORDER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Extract user prompt and session ID. Fall back to grep when jq is missing so the
# hook stays useful in minimal environments.
if command -v jq >/dev/null 2>&1; then
  USER_PROMPT=$(printf '%s' "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null || echo "")
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
else
  USER_PROMPT=$(printf '%s' "$INPUT" | sed -n 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -z "$USER_PROMPT" ] && USER_PROMPT=$(printf '%s' "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

[ -z "$SESSION_ID" ] && SESSION_ID="no-session-id"

# Determine source and skill name. Priority: manual override → slash command →
# in-prompt marker. First match wins.
SOURCE=""
SKILL=""

# 1. Operator override via CC_ACTIVE_SKILL env var
if [ -n "${CC_ACTIVE_SKILL:-}" ]; then
  SOURCE="manual"
  SKILL="$CC_ACTIVE_SKILL"
fi

# 2. Slash command at start of first non-blank line. Leading whitespace on the
# first line is tolerated; the slash must be the first non-blank character.
if [ -z "$SKILL" ] && [ -n "$USER_PROMPT" ]; then
  FIRST_LINE=$(printf '%s' "$USER_PROMPT" | awk 'NF{print; exit}')
  TRIMMED=$(printf '%s' "$FIRST_LINE" | sed 's/^[[:space:]]*//')
  if printf '%s' "$TRIMMED" | grep -qE '^/[A-Za-z][A-Za-z0-9_:-]*'; then
    SKILL=$(printf '%s' "$TRIMMED" | grep -oE '^/[A-Za-z][A-Za-z0-9_:-]*' | sed 's|^/||' | head -c 64)
    SOURCE="slash"
  fi
fi

# 3. In-prompt marker (best-effort)
if [ -z "$SKILL" ] && [ -n "$USER_PROMPT" ]; then
  MARKER=$(printf '%s' "$USER_PROMPT" | grep -oE '\[skill:[[:space:]]*[A-Za-z][A-Za-z0-9_-]+\]' | head -1)
  if [ -n "$MARKER" ]; then
    SKILL=$(printf '%s' "$MARKER" | sed -E 's/\[skill:[[:space:]]*([A-Za-z][A-Za-z0-9_-]+)\]/\1/' | head -c 64)
    SOURCE="marker"
  fi
fi

# Strip pipe characters and newlines as a schema-preservation guard. Skill names
# are normally ASCII identifiers so this is a defensive measure.
SKILL=$(printf '%s' "$SKILL" | tr -d '|\n\r')
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -d '|\n\r' | head -c 80)

# No skill detected → silent exit (the common case)
[ -z "$SKILL" ] && exit 0

LOG_PATH="${CC_SKILLS_CONTEXT_LOG_PATH:-$HOME/.claude/skills-context.log}"
LOG_DIR=$(dirname "$LOG_PATH")
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
printf '%s|%s|%s|%s\n' "$TIMESTAMP" "$SESSION_ID" "$SOURCE" "$SKILL" >> "$LOG_PATH" 2>/dev/null || true

# Rotate when the log exceeds the configured threshold. Keep the most recent half
# so the workaround stays useful for cross-session lookback.
MAX_LINES="${CC_SKILLS_CONTEXT_MAX_LINES:-1000}"
if [ -f "$LOG_PATH" ]; then
  CURRENT_LINES=$(wc -l < "$LOG_PATH" 2>/dev/null || echo 0)
  if [ "$CURRENT_LINES" -gt "$MAX_LINES" ] 2>/dev/null; then
    KEEP=$((MAX_LINES / 2))
    [ "$KEEP" -lt 1 ] && KEEP=1
    tail -n "$KEEP" "$LOG_PATH" > "${LOG_PATH}.tmp" 2>/dev/null && mv "${LOG_PATH}.tmp" "$LOG_PATH" 2>/dev/null || true
  fi
fi

# Stderr advisory: one line summarizing the recorded activation. Silent when
# explicitly muted. Keeps the operator aware that the workaround is in effect
# without flooding the terminal.
if [ "${CC_SKILLS_CONTEXT_RECORDER_QUIET:-0}" != "1" ]; then
  printf '[skills-context-recorder] recorded skill=%s source=%s session=%s\n' \
    "$SKILL" "$SOURCE" "${SESSION_ID:0:12}" >&2
fi

exit 0
