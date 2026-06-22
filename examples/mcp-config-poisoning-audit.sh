#!/bin/bash
# ================================================================
# mcp-config-poisoning-audit.sh — Read-only audit for supply-chain
#   poisoning of your Claude Code config (NOT prevention of Claude's
#   own edits — that's hook-tamper-guard / mcp-config-freeze)
# ================================================================
# PURPOSE:
#   A malicious npm package's post-install script, or a malicious MCP
#   server, can rewrite ~/.claude.json / ~/.claude/settings.json
#   *outside* Claude Code entirely — so no PreToolUse hook ever fires.
#   Two reported shapes (June 2026 wave + Mitiga Labs / CVE-2025-59536):
#     - An injected hook (e.g. SessionStart) whose command calls out to
#       the network or evals a payload, to exfiltrate keys on next open.
#     - An mcpServers entry whose endpoint is rewritten to a localhost
#       proxy or an unfamiliar external host, so authenticated MCP
#       traffic (and OAuth tokens) is routed through attacker infra.
#   The existing guards PREVENT Claude from editing config and FREEZE
#   mid-session additions, but nothing AUDITS config that was already
#   poisoned from outside. This fills that gap.
#
# HOW IT WORKS: SessionStart hook. Read-only. Scans the config files,
#   flags hook commands containing network/eval indicators and
#   mcpServers entries pointing at external/localhost-proxy endpoints,
#   and prints a warning. It never edits or deletes anything (some of
#   these payloads retaliate by wiping the home dir if tampered with —
#   so this only reports; you review and remediate by hand).
#   Always exits 0 (advisory; never blocks the session).
#
# See: CVE-2025-59536 (RCE via malicious hooks in repo settings),
#      CVE-2026-21852 (key exfil via env override), and the Mitiga
#      Labs ~/.claude.json MCP-routing-rewrite disclosure.
#
# TRIGGER: SessionStart
# MATCHER: "" (SessionStart has no matcher)
#
# Configuration:
#   CC_MCP_AUDIT_OFF=1            — disable
#   CC_MCP_AUDIT_TRUSTED_HOSTS    — colon-separated host substrings to
#                                   treat as expected (e.g. "githubcopilot.com:api.githubcopilot")
# ================================================================

set -uo pipefail

[ "${CC_MCP_AUDIT_OFF:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0   # fail open: no jq, no audit

HOME_DIR="${HOME:-/root}"
CANDIDATES=(
    "$HOME_DIR/.claude.json"
    "$HOME_DIR/.claude/settings.json"
    "$HOME_DIR/.claude/settings.local.json"
    ".claude/settings.json"
    ".claude/settings.local.json"
    ".mcp.json"
)

# Network / code-exec indicators that almost never belong in a legit
# hook command. Kept conservative to avoid noise.
NET_EXEC_RE='curl |wget |\bnc \b|netcat|/dev/tcp/|node +-e|node +--eval|python3? +-c|deno +eval|base64 +-d|base64 +--decode|\beval +"|\beval +\$|bash +-i|sh +-i|powershell +-enc|Invoke-WebRequest|iwr '

TRUSTED="${CC_MCP_AUDIT_TRUSTED_HOSTS:-}"

findings=0
note() { echo "  ⚠ $*" >&2; findings=$((findings + 1)); }

is_trusted() {
    # $1 = string to test; returns 0 if it contains a trusted substring
    [ -n "$TRUSTED" ] || return 1
    local IFS=':' t
    for t in $TRUSTED; do
        [ -n "$t" ] && case "$1" in *"$t"*) return 0;; esac
    done
    return 1
}

audit_file() {
    local f="$1"
    [ -f "$f" ] || return 0
    jq -e . "$f" >/dev/null 2>&1 || return 0   # invalid JSON: other guards handle it

    # 1) Hook commands (any event) containing network/exec indicators.
    #    .hooks is { Event: [ { hooks: [ { command } ] } ] }
    local cmds
    cmds=$(jq -r '
        (.hooks // {}) | to_entries[] | .key as $ev
        | (.value // []) | .[]? | (.hooks // []) | .[]?
        | select(.command != null) | "\($ev)\t\(.command)"
    ' "$f" 2>/dev/null)
    if [ -n "$cmds" ]; then
        while IFS=$'\t' read -r ev cmd; do
            [ -z "$cmd" ] && continue
            if printf '%s' "$cmd" | grep -qiE "$NET_EXEC_RE"; then
                is_trusted "$cmd" && continue
                note "[$f] hook '$ev' runs a network/exec command: ${cmd:0:90}"
            fi
        done <<< "$cmds"
    fi

    # 2) mcpServers endpoints: external URLs / IP literals / localhost proxies.
    #    Entry may carry a "url" (http transport) or "command"+"args" (stdio).
    # Use the unit separator (0x1f) — empty fields must NOT collapse, and
    # tab is IFS-whitespace so consecutive tabs around an empty url would
    # merge and shift every field.
    local servers
    servers=$(jq -r '
        (.mcpServers // .mcp_servers // {}) | to_entries[]
        | "\(.key)\((.value.url // ""))\((.value.command // ""))\(((.value.args // []) | join(" ")))"
    ' "$f" 2>/dev/null)
    if [ -n "$servers" ]; then
        while IFS=$'\x1f' read -r name url cmd args; do
            [ -z "$name" ] && continue
            local blob="$url $cmd $args"
            is_trusted "$blob" && continue
            # external http(s) endpoint
            if printf '%s' "$url" | grep -qiE '^https?://'; then
                case "$url" in
                    http://127.0.0.1*|http://localhost*|http://[::1]*)
                        note "[$f] MCP server '$name' routes through a localhost proxy: $url" ;;
                    *)
                        note "[$f] MCP server '$name' uses an external HTTP endpoint: $url" ;;
                esac
            fi
            # raw IP literal or pipe-to-shell hidden in command/args
            if printf '%s' "$cmd $args" | grep -qiE "$NET_EXEC_RE"; then
                note "[$f] MCP server '$name' command contains a network/exec indicator: ${cmd} ${args}"
            fi
        done <<< "$servers"
    fi
}

for f in "${CANDIDATES[@]}"; do
    audit_file "$f"
done

if [ "$findings" -gt 0 ]; then
    {
        echo ""
        echo "⚠ cc-safe-setup: possible Claude Code config poisoning ($findings finding(s) above)."
        echo "  A malicious npm post-install or MCP server can rewrite ~/.claude.json /"
        echo "  settings.json from outside Claude, so no PreToolUse hook catches it."
        echo "  This is a READ-ONLY warning — verify each item by hand. Do NOT blindly delete"
        echo "  (some payloads retaliate). If any is unexpected:"
        echo "    1) update Claude Code (CVE-2025-59536 / CVE-2026-21852 are patched in current builds)"
        echo "    2) rotate the OAuth tokens / API keys reachable from that config"
        echo "    3) remove the injected hook/server entry by hand and review recent npm installs"
        echo "  Silence expected entries with CC_MCP_AUDIT_TRUSTED_HOSTS, or CC_MCP_AUDIT_OFF=1."
    } >&2
fi

exit 0
