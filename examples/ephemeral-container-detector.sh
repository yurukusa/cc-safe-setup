#!/bin/bash
# ephemeral-container-detector.sh — Warn operators when Claude Code is
# starting inside an ephemeral container where MCP approval state will not
# persist across container recreations.
#
# Solves: #61141 — "[BUG] MCP connector permissions lost on every startup
# in remote/container routines"
# Reporter: routine running inside an ephemeral container (Docker / devcontainer
# / Codespaces). The container's HOME tree is regenerated on every startup, so
# `~/.claude/settings.json` and `mcpServers` approval state are silently wiped.
# The operator re-approves on first tool call, then loses those approvals at
# the next container boot. The recovery loop — write to settings.json — itself
# requires Write approval, producing a blocking approval loop.
#
# This hook does NOT attempt to fix the persistence; that requires the
# operator to mount a persistent volume at the relevant .claude directory or
# bake an approved settings.json into the container image. Instead the hook
# surfaces the silent-reset risk on SessionStart so the operator notices it
# BEFORE the first MCP tool call, rather than after the third approval prompt.
#
# Detection runs in two layers. Layer 1: is this an ephemeral runtime?
#   - /.dockerenv exists
#   - /proc/1/cgroup mentions docker, containerd, kubepods, or lxc
#   - $CONTAINER, $DEVCONTAINER, $CODESPACES, $REMOTE_CONTAINERS env set
#   - HOSTNAME matches a short hex pattern typical of container IDs
# Layer 2: does ~/.claude/ look like it just got recreated?
#   - settings.json missing OR
#   - settings.json has mcpServers configured but no enabledMcpjsonServers /
#     approval state entries (suggests state was wiped)
#
# Both layers must hit. Layer 1 alone is too noisy (many container users have
# correctly mounted ~/.claude/ from a persistent volume). Layer 2 alone is too
# noisy (a fresh local install also looks like this). Together, the combination
# is a strong signal that the operator is about to walk into the #61141 loop.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_EPHEMERAL_CONTAINER_DISABLE   set to "1" to disable
#   CC_CLAUDE_HOME                   default $HOME/.claude
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/ephemeral-container-detector.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_EPHEMERAL_CONTAINER_DISABLE:-0}" = "1" ] && exit 0

CLAUDE_HOME="${CC_CLAUDE_HOME:-$HOME/.claude}"

# --------------------------------------------------------------------------
# Layer 1 — is this an ephemeral runtime?
# --------------------------------------------------------------------------
container_signals=()

[ -f /.dockerenv ] && container_signals+=("/.dockerenv file present")

if [ -r /proc/1/cgroup ]; then
    if grep -qE 'docker|containerd|kubepods|lxc' /proc/1/cgroup 2>/dev/null; then
        container_signals+=("/proc/1/cgroup names a container runtime")
    fi
fi

[ -n "${CONTAINER:-}" ] && container_signals+=("CONTAINER env set: ${CONTAINER}")
[ -n "${DEVCONTAINER:-}" ] && container_signals+=("DEVCONTAINER env set")
[ -n "${CODESPACES:-}" ] && container_signals+=("CODESPACES env set")
[ -n "${REMOTE_CONTAINERS:-}" ] && container_signals+=("REMOTE_CONTAINERS env set")

# Short hex hostnames (e.g. 7b3a1f8d2c4e) are typical of Docker container IDs.
HOST="${HOSTNAME:-$(hostname 2>/dev/null || echo "")}"
if [ -n "$HOST" ] && printf '%s' "$HOST" | grep -qE '^[0-9a-f]{8,12}$'; then
    container_signals+=("hostname looks like a container ID: ${HOST}")
fi

[ ${#container_signals[@]} -eq 0 ] && exit 0

# --------------------------------------------------------------------------
# Layer 2 — does ~/.claude/ look freshly recreated?
# --------------------------------------------------------------------------
SETTINGS="${CLAUDE_HOME}/settings.json"
reset_signal=""

if [ ! -f "$SETTINGS" ]; then
    reset_signal="settings.json is missing at ${SETTINGS}"
elif command -v jq >/dev/null 2>&1; then
    # If mcpServers is configured but no approvals are registered, the
    # operator will hit an approval prompt on the first MCP tool call and
    # those approvals will not survive the next container recreation.
    mcp_configured=$(jq -r '
        (.mcpServers // {} | length) +
        (.projects // {} | to_entries[]?.value.mcpServers // {} | length)
    ' "$SETTINGS" 2>/dev/null | awk '{s+=$1} END{print s+0}')
    enabled_servers=$(jq -r '
        (.enabledMcpjsonServers // []) | length
    ' "$SETTINGS" 2>/dev/null || echo 0)

    if [ "${mcp_configured:-0}" -gt 0 ] && [ "${enabled_servers:-0}" -eq 0 ]; then
        reset_signal="${mcp_configured} mcpServers configured but enabledMcpjsonServers is empty"
    fi
fi

[ -z "$reset_signal" ] && exit 0

# --------------------------------------------------------------------------
# Both layers hit — emit the advisory.
# --------------------------------------------------------------------------
{
    echo ""
    echo "[ephemeral-container-detector] MCP approval state may not persist across container recreations."
    echo ""
    echo "Container signals:"
    for s in "${container_signals[@]}"; do
        echo "  - $s"
    done
    echo ""
    echo "Reset signal:"
    echo "  - $reset_signal"
    echo ""
    echo "Why this matters (anthropics/claude-code#61141):"
    echo "  An ephemeral container regenerates its HOME tree on every boot."
    echo "  MCP approvals you grant in this session will be wiped on the next"
    echo "  container start. The self-repair path (writing settings.json) also"
    echo "  triggers an approval prompt, producing a blocking re-approval loop."
    echo ""
    echo "Mitigations (pick one):"
    echo "  1. Mount a persistent volume at ${CLAUDE_HOME} so settings.json survives."
    echo "  2. Bake an approved settings.json into the container image and"
    echo "     declare it read-only so the runtime treats approvals as final."
    echo "  3. Pre-approve specific MCP servers via enabledMcpjsonServers in"
    echo "     a settings file under version control."
    echo ""
    echo "Set CC_EPHEMERAL_CONTAINER_DISABLE=1 to silence this warning."
    echo ""
} >&2

exit 0
