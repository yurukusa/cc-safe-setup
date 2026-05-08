#!/bin/bash
# ================================================================
# mcp-startup-bloat-detector.sh — Warn when claude.ai connector
#   sync inflates the System tools context at session start.
# ================================================================
# PURPOSE:
#   Pro / Claude.ai-OAuth users inherit every connector configured
#   on their claude.ai account into every CLI session. The MCP
#   tool definitions and authentication entries each consume
#   ~250-330 tokens of context, and at scale they can dominate
#   the context window before the user has typed anything.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# WHY THIS MATTERS:
#   Issue #50062 (closed 2026-04-19) reported ~100k tokens of
#   silent connector bloat; the v2.1.14 fix added the
#   ENABLE_CLAUDEAI_MCP_SERVERS=false escape hatch.
#
#   Issue #57235 (filed 2026-05-08, v2.1.133) reports the same
#   pattern at 2.9M tokens — 29x larger — leaving /context at
#   1,460% before the first user turn. Either the v2.1.14 fix
#   regressed, or a new path bypasses it.
#
#   This detector reads claude mcp list and warns when the count
#   of claude.ai-prefixed connectors crosses a threshold, giving
#   users a chance to set ENABLE_CLAUDEAI_MCP_SERVERS=false
#   before the bloat hurts them.
#
# CONFIGURATION:
#   MCP_BLOAT_THRESHOLD_COUNT  number of claude.ai connectors to
#                              trigger warning (default: 5)
#   MCP_BLOAT_DETECTOR_DISABLE set to 1 to silence this hook
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/50062
#   https://github.com/anthropics/claude-code/issues/57235
# ================================================================

set -u

[ "${MCP_BLOAT_DETECTOR_DISABLE:-0}" = "1" ] && exit 0

THRESHOLD="${MCP_BLOAT_THRESHOLD_COUNT:-5}"
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date +%s)"

# One warning per session
WARN_LOG="$LOG_DIR/mcp-bloat-warned-$SESSION_ID"
[ -f "$WARN_LOG" ] && exit 0

# Need claude binary to inspect MCP state
if ! command -v claude >/dev/null 2>&1; then
    exit 0
fi

# Count claude.ai-prefixed connectors. The CLI prints one per line as:
#   claude.ai <Name>: <url> - <status>
MCP_OUTPUT=$(claude mcp list 2>/dev/null || true)
[ -z "$MCP_OUTPUT" ] && exit 0

COUNT=$(printf '%s\n' "$MCP_OUTPUT" | grep -cE '^claude\.ai[[:space:]]' || true)
COUNT=${COUNT:-0}

if [ "$COUNT" -ge "$THRESHOLD" ]; then
    EST_TOKENS=$((COUNT * 290))
    cat >&2 <<MSG
mcp-startup-bloat-detector: $COUNT claude.ai connectors auto-loaded
  (estimated ~${EST_TOKENS} tokens of context overhead at ~290 tokens each).

  If /context shows an unusually high "System tools" load, set
  ENABLE_CLAUDEAI_MCP_SERVERS=false in your shell, remove
  ~/.claude/.credentials.json, and re-run /login. OAuth stays;
  the connector sync is what gets disabled.

  Background: Issue #50062 (closed v2.1.14, ~100k tokens) and
  Issue #57235 (filed 2026-05-08 v2.1.133, ~2.9M tokens).
MSG
    touch "$WARN_LOG"
fi

exit 0
