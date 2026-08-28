#!/bin/bash
# mcp-permissions-ask-warner.sh — Warn when permissions.ask has MCP entries
#
# Solves: github.com/anthropics/claude-code/issues/58289
#         "permissions.ask is ignored for MCP tools in default mode"
#
#         Reporter (2026-05-13, Claude Code 2.1.139 + Bedrock): MCP tool
#         entries in the `permissions.ask` array of `~/.claude/settings.json`
#         do not trigger a confirmation prompt. The MCP tool call executes
#         immediately, the same as if the entry were in `allow`. The user's
#         intent ("ask before running this MCP tool") diverges from the
#         system's behavior ("run without asking") with no visible signal.
#
# WHY THIS MATTERS:
#   permissions.ask is the gating mechanism users rely on to keep a human
#   in the loop for sensitive MCP tools (database writes, deployment, file
#   delete, payment). If this gating is silently bypassed, sensitive MCP
#   tools fire without the user's review. This is a textbook claim-verify
#   gap: the user believes "this is gated" while the system has already
#   run the tool. Worse, the MCP surface is where many irreversible
#   operations live (cloud resource changes, payment processing, message
#   sending).
#
# TRIGGER: SessionStart  MATCHER: ""
#
# HOW IT WORKS:
#   At session start:
#     1. Find the relevant settings.json files.
#        Default order: ~/.claude/settings.json, then $CLAUDE_PROJECT_DIR/.claude/settings.json
#     2. For each file, parse the permissions.ask array.
#     3. Filter entries to MCP tools (starting with "mcp__").
#     4. If any MCP entries are found, emit a clear warning listing them,
#        explaining the known bypass, and suggesting two workarounds:
#          (a) Move sensitive MCP entries from permissions.ask to permissions.deny
#              (deny still works correctly per the reporter)
#          (b) Use `--permission-mode plan` mode for the session if MCP-heavy
#
# CONFIGURATION:
#   CC_MCP_ASK_DISABLE=1     — disable the hook entirely
#   CC_MCP_ASK_ACTION        — "warn" (default) or "block" (exit 2)
#   CC_MCP_ASK_LOG           — log file path (default /tmp/cc-mcp-ask.log)
#   CC_MCP_ASK_FILES         — comma-separated settings.json paths to scan
#                              (default: $HOME/.claude/settings.json plus
#                              $CLAUDE_PROJECT_DIR/.claude/settings.json)
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/mcp-permissions-ask-warner.sh" }]
#     }]
#   }
# }

if [ "${CC_MCP_ASK_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-mcp-permissions-ask-warner-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [mcp-permissions-ask-warner]: jq not found - this hook cannot read your settings files and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

ACTION="${CC_MCP_ASK_ACTION:-warn}"
LOG_FILE="${CC_MCP_ASK_LOG:-/tmp/cc-mcp-ask.log}"

# Determine which settings.json files to scan
if [ -n "$CC_MCP_ASK_FILES" ]; then
  IFS=',' read -ra FILES <<< "$CC_MCP_ASK_FILES"
else
  FILES=()
  [ -f "$HOME/.claude/settings.json" ] && FILES+=("$HOME/.claude/settings.json")
  if [ -n "$CLAUDE_PROJECT_DIR" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/settings.json" ]; then
    FILES+=("$CLAUDE_PROJECT_DIR/.claude/settings.json")
  fi
fi

# Collect MCP entries across all files
MCP_ENTRIES=()
SOURCE_FILES=()

for f in "${FILES[@]}"; do
  f=$(echo "$f" | xargs)  # trim
  [ -z "$f" ] && continue
  [ ! -f "$f" ] && continue
  # Extract permissions.ask entries that look like MCP tools
  ENTRIES=$(jq -r '
    (.permissions.ask // [])
    | map(select(type == "string" and startswith("mcp__")))
    | .[]
  ' "$f" 2>/dev/null)
  if [ -n "$ENTRIES" ]; then
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      MCP_ENTRIES+=("$entry")
      SOURCE_FILES+=("$f")
    done <<< "$ENTRIES"
  fi
done

# No MCP ask entries → silent pass
if [ ${#MCP_ENTRIES[@]} -eq 0 ]; then
  exit 0
fi

# Log + emit
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
for i in "${!MCP_ENTRIES[@]}"; do
  echo "[$TIMESTAMP] mcp_in_ask entry=${MCP_ENTRIES[$i]} source=${SOURCE_FILES[$i]} action=$ACTION" >> "$LOG_FILE"
done

MSG="⚠️  permissions.ask contains MCP tool entries that may be silently bypassed"
MSG+=$'\n'
MSG+=$'\n'"  Affected entries:"
for i in "${!MCP_ENTRIES[@]}"; do
  MSG+=$'\n'"    - ${MCP_ENTRIES[$i]}  (in ${SOURCE_FILES[$i]})"
done
MSG+=$'\n'
MSG+=$'\n'"  Known bug: github.com/anthropics/claude-code/issues/58289"
MSG+=$'\n'"  In Claude Code 2.1.139 (and possibly other versions), permissions.ask"
MSG+=$'\n'"  entries for MCP tools (names starting with mcp__) do not trigger a"
MSG+=$'\n'"  confirmation prompt in default mode. The tool executes immediately,"
MSG+=$'\n'"  as if it were in permissions.allow. Reported on Bedrock (us.anthropic."
MSG+=$'\n'"  claude-opus-4-7), likely also affects other providers."
MSG+=$'\n'
MSG+=$'\n'"  Workarounds (pick one):"
MSG+=$'\n'"    1. Move the listed entries from permissions.ask to permissions.deny."
MSG+=$'\n'"       deny still gates correctly per the bug report. The tool will be"
MSG+=$'\n'"       refused outright; you can override case-by-case in the chat."
MSG+=$'\n'"    2. Run the session with --permission-mode plan, which forces an"
MSG+=$'\n'"       explicit plan-approval step before any tool execution."
MSG+=$'\n'"    3. Remove the entry from permissions.ask if the tool is acceptable"
MSG+=$'\n'"       to run without confirmation."
MSG+=$'\n'
MSG+=$'\n'"  This warning fires once per session start. To silence it after you've"
MSG+=$'\n'"  adopted a workaround, set CC_MCP_ASK_DISABLE=1 in your environment."

if [ "$ACTION" = "block" ]; then
  printf '%s\n' "$MSG" >&2
  exit 2
else
  printf '%s\n' "$MSG" >&2
  exit 0
fi
