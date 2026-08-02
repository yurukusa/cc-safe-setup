#!/bin/bash
# mcp-misdiagnosis-arrest.sh — Catch the assistant misdiagnosing a silently-
# dropped MCP connector as "the connector isn't installed", and surface the
# actual recovery path before the operator wastes a reinstall round-trip.
#
# Solves: #60428 ("Slack MCP tools silently deactivate mid-session ~1h
# uptime; claude mcp list still reports Connected").
#
# In that case, an installed MCP connector (Slack, in the reported instance)
# silently drops out of the model's deferred-tool registry after ~1 hour of
# uptime. The model then attempts a tool call, gets a missing-tool result,
# and — guided by current docs/skill prompts — frequently suggests the
# operator "install the Connector" as the remediation. The reporter
# documents this as the secondary issue:
#
#   "That's wrong: the Connector *is* already installed, it was working in
#    this session, and the suggestion sends users on a 30-second wild goose
#    chase before they realize the real fix is restart / new chat /
#    plugin toggle."
#
# The actual recovery path the reporter verified (2026-05-19):
#
#   1. Open a new chat in the same Claude Code window (re-binds tools in the
#      original session without losing context).
#   2. Toggle the Connector's Plugin off → on in Customize → Personal plugins.
#   3. Restart Claude Code (loses session).
#   4. /clear (nukes context — not a real fix).
#
# What does NOT restore the tools: /mcp, /compact, /resume, /config, waiting.
#
# This hook runs on Stop, scans the assistant's most recent turn for
# misdiagnosis patterns ("you need to install the X Connector", "the X
# Plugin isn't installed", "the MCP server seems missing"), cross-references
# against ~/.claude/settings.json to confirm the named connector IS
# installed, and — if so — emits an advisory with the correct recovery path.
#
# Advisory-default (exit 0 + stderr). Strict mode (exit 2) is opt-in via
# CC_MCP_MISDIAGNOSIS_MODE=strict.
#
# Related Issues:
#   #60428 — Slack MCP tools silently deactivate (the primary)
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_MCP_MISDIAGNOSIS_MODE       "strict" → exit 2 when misdiagnosis is
#                                  detected against an installed connector.
#                                  Default: advisory (exit 0).
#   CC_MCP_MISDIAGNOSIS_DISABLE    "1" → skip the gate entirely.
#   CC_MCP_SETTINGS_PATH           Override the settings.json path used to
#                                  confirm connector installation. Default:
#                                  ~/.claude/settings.json. Tests use this
#                                  to point at a fixture file.
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/mcp-misdiagnosis-arrest.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-mcp-misdiagnosis-arrest-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [mcp-misdiagnosis-arrest]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

[ "${CC_MCP_MISDIAGNOSIS_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

SETTINGS_PATH="${CC_MCP_SETTINGS_PATH:-$HOME/.claude/settings.json}"

# Extract the assistant's last message text. Stop-hook input shape varies
# across Claude Code versions; try several keys (matching the precedent set
# in closure-word-verify-gate.sh).
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

[ -z "$ASSISTANT_TEXT" ] && exit 0

# Misdiagnosis patterns. The shape we want to catch is:
#   "<thing> Connector/Plugin/MCP server isn't installed / needs to be
#    installed / is missing / not configured"
# We intentionally over-match a little; the false-positive cost is a
# stderr advisory, the false-negative cost is the operator on a reinstall
# wild goose chase.
MISDIAG_PATTERN='(([Cc]onnector|[Pp]lugin|[Mm]CP[[:space:]]+[Ss]erver)[[:space:]]+(isn'\''t|is[[:space:]]+not|needs[[:space:]]+to[[:space:]]+be|appears[[:space:]]+to[[:space:]]+be|seems[[:space:]]+to[[:space:]]+be|is)[[:space:]]+(installed|configured|missing|unavailable|set[[:space:]]+up)|need[[:space:]]+to[[:space:]]+install[[:space:]]+the[[:space:]]+[A-Za-z][A-Za-z0-9_-]*[[:space:]]+(Connector|Plugin)|install[[:space:]]+the[[:space:]]+[A-Za-z][A-Za-z0-9_-]*[[:space:]]+(Connector|Plugin)[[:space:]]+(first|to[[:space:]]+use|before)|[Mm]CP[[:space:]]+(tool|tools)[[:space:]]+(are|aren'\''t|is|isn'\''t)[[:space:]]+(missing|unavailable|registered|available))'

if ! printf '%s' "$ASSISTANT_TEXT" | grep -Eq "$MISDIAG_PATTERN"; then
    exit 0
fi

# Misdiagnosis language matched. Now check: is any MCP connector / plugin
# actually installed? If yes, the misdiagnosis is wrong and we should warn.
# If no installed connectors, the assistant's "isn't installed" claim might
# be correct — stay silent rather than false-positive.

if [ ! -r "$SETTINGS_PATH" ]; then
    # No readable settings to confirm against — refuse to false-positive.
    exit 0
fi

# Look for any of:
#   * an enabledPlugins entry like "slack@claude-plugins-official": true
#   * an mcpServers entry (any key under .mcpServers)
#   * a plugins block with any entry
INSTALLED_CONNECTORS=$(jq -r '
    [
      (.enabledPlugins // {} | to_entries | map(select(.value == true) | .key)),
      (.mcpServers // {} | keys),
      (.plugins // {} | keys)
    ] | add | unique | .[]
' "$SETTINGS_PATH" 2>/dev/null)

if [ -z "$INSTALLED_CONNECTORS" ]; then
    # Nothing installed → assistant's "isn't installed" may be correct.
    exit 0
fi

# Try to extract the specific connector name the assistant referenced, so
# we can match it against the installed set (most precise warning). If we
# cannot extract a name, we still warn — any installed connector means the
# generic "you need to install one" advice is at least partly wrong.
NAMED_CONNECTOR=$(printf '%s' "$ASSISTANT_TEXT" \
    | grep -Eio '(install[[:space:]]+the[[:space:]]+)?[A-Za-z][A-Za-z0-9_-]*[[:space:]]+(Connector|Plugin|MCP[[:space:]]+Server)' \
    | head -1 \
    | sed -E 's/^install[[:space:]]+the[[:space:]]+//I; s/[[:space:]]+(Connector|Plugin|MCP[[:space:]]+Server)$//I')

NAMED_MATCH=""
if [ -n "$NAMED_CONNECTOR" ]; then
    # Case-insensitive substring match against installed connector keys.
    NAMED_LOWER=$(printf '%s' "$NAMED_CONNECTOR" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r installed; do
        installed_lower=$(printf '%s' "$installed" | tr '[:upper:]' '[:lower:]')
        if printf '%s' "$installed_lower" | grep -Fq "$NAMED_LOWER"; then
            NAMED_MATCH="$installed"
            break
        fi
    done <<EOF
$INSTALLED_CONNECTORS
EOF
fi

# Build advisory.
{
    echo "<system-reminder>"
    echo "MCP MISDIAGNOSIS LIKELY — the assistant's last turn suggested an MCP"
    echo "connector/plugin needs to be installed, but the operator's settings"
    echo "already show installed MCP connectors:"
    echo ""
    printf '%s\n' "$INSTALLED_CONNECTORS" | sed 's/^/  - /'
    echo ""
    if [ -n "$NAMED_MATCH" ]; then
        echo "Specifically, '$NAMED_MATCH' is already installed and configured."
    elif [ -n "$NAMED_CONNECTOR" ]; then
        echo "The named connector '$NAMED_CONNECTOR' was not found in settings,"
        echo "but other connectors are installed — double-check the name before"
        echo "recommending a reinstall."
    fi
    echo ""
    echo "Known pattern (#60428): MCP connectors can silently drop out of the"
    echo "session's deferred-tool registry after ~1h uptime while 'claude mcp"
    echo "list' continues to report 'Connected'. The model then misdiagnoses"
    echo "this as missing installation."
    echo ""
    echo "Actual recovery path (verified 2026-05-19):"
    echo "  1. Open a new chat in the same Claude Code window."
    echo "     (Re-binds tools in the original session without losing context.)"
    echo "  2. Toggle the connector's Plugin off → on in Customize → Personal"
    echo "     plugins."
    echo "  3. Restart Claude Code (loses session)."
    echo ""
    echo "What does NOT restore them: /mcp, /compact, /resume, /config, waiting,"
    echo "or reinstalling the connector."
    echo ""
    echo "Before sending the assistant's last turn to the operator, replace the"
    echo "installation advice with the recovery steps above."
    echo ""
    echo "To disable this gate (for genuinely uninstalled-connector flows),"
    echo "set CC_MCP_MISDIAGNOSIS_DISABLE=1 in your environment."
    echo "</system-reminder>"
} >&2

if [ "${CC_MCP_MISDIAGNOSIS_MODE:-advisory}" = "strict" ]; then
    exit 2
fi
exit 0
