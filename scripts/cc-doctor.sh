#!/bin/bash
# cc-doctor.sh — One-shot health check for a Claude Code install.
#
# Run this when something feels off: high context use, frozen sessions,
# unexplained quota burn. The script is read-only; it does not modify
# config, hooks, or settings. It prints a list of facts and a list of
# concerns based on those facts, then exits 0.
#
# Run with:
#   bash <(curl -fsSL https://raw.githubusercontent.com/yurukusa/cc-safe-setup/main/scripts/cc-doctor.sh)
# or, after `git clone`:
#   bash scripts/cc-doctor.sh

set -u

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

CONCERNS=()

note() { printf '%b\n' "$*"; }
ok()   { printf '%b%s%b %s\n' "$GREEN" "✓" "$NC" "$1"; }
warn() { printf '%b%s%b %s\n' "$YELLOW" "!" "$NC" "$1"; CONCERNS+=("$1"); }
bad()  { printf '%b%s%b %s\n' "$RED" "✗" "$NC" "$1"; CONCERNS+=("$1"); }

note "${BOLD}cc-doctor${NC} ${DIM}(read-only, $(date -u +%Y-%m-%dT%H:%M:%SZ))${NC}"
note ""

# --- Section 1: Claude Code binary ---
note "${BOLD}Claude Code${NC}"
if command -v claude >/dev/null 2>&1; then
    VERSION=$(claude --version 2>/dev/null | head -1)
    if [ -n "$VERSION" ]; then
        ok "claude installed: $VERSION"
        # Flag known-bad versions
        if [[ "$VERSION" =~ 2\.1\.133 ]]; then
            warn "v2.1.133 has the Pro-OAuth context bloat regression (#57235). If /context is over 1M tokens, set ENABLE_CLAUDEAI_MCP_SERVERS=false and re-login."
        fi
    else
        warn "claude found but --version returned nothing"
    fi
else
    bad "claude binary not in PATH"
fi
note ""

# --- Section 2: credentials ---
note "${BOLD}Authentication${NC}"
CREDS="$HOME/.claude/.credentials.json"
if [ -f "$CREDS" ]; then
    ok "credentials.json exists"
    # Check for OAuth scopes that trigger MCP sync
    if command -v jq >/dev/null 2>&1; then
        SCOPES=$(jq -r '.claudeAiOauth.scopes // [] | join(",")' "$CREDS" 2>/dev/null || echo "")
        if echo "$SCOPES" | grep -q 'user:mcp_servers'; then
            warn "OAuth has user:mcp_servers scope - claude.ai connectors will auto-sync into the CLI. If /context is bloated, set ENABLE_CLAUDEAI_MCP_SERVERS=false."
        else
            ok "OAuth scopes look minimal (no user:mcp_servers)"
        fi
    fi
else
    note "  ${DIM}credentials.json not present (using API key auth or not logged in)${NC}"
fi
note ""

# --- Section 3: MCP connector load ---
note "${BOLD}MCP connector load${NC}"
if command -v claude >/dev/null 2>&1; then
    MCP_OUT=$(claude mcp list 2>/dev/null || echo "")
    if [ -n "$MCP_OUT" ]; then
        AI_COUNT=$(printf '%s\n' "$MCP_OUT" | grep -cE '^claude\.ai[[:space:]]' || true)
        AI_COUNT=${AI_COUNT:-0}
        TOTAL_COUNT=$(printf '%s\n' "$MCP_OUT" | grep -cE ': https?://| node | python ' || true)
        TOTAL_COUNT=${TOTAL_COUNT:-0}
        ok "MCP servers reachable: $TOTAL_COUNT total, $AI_COUNT from claude.ai"
        if [ "$AI_COUNT" -ge 5 ]; then
            EST=$((AI_COUNT * 290))
            warn "$AI_COUNT claude.ai connectors auto-loaded (~${EST} tokens of context overhead). Set ENABLE_CLAUDEAI_MCP_SERVERS=false to disable, OAuth login is preserved."
        fi
    else
        note "  ${DIM}claude mcp list returned nothing (claude not running or daemon down)${NC}"
    fi
else
    note "  ${DIM}skipped (claude not in PATH)${NC}"
fi
note ""

# --- Section 4: settings.json hooks ---
note "${BOLD}Hooks${NC}"
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    if command -v jq >/dev/null 2>&1; then
        HOOK_COUNT=$(jq -r '[.hooks // {} | to_entries[] | .value[]?] | length' "$SETTINGS" 2>/dev/null || echo "0")
        ok "$HOOK_COUNT hook entries in ~/.claude/settings.json"
        if [ "$HOOK_COUNT" -lt 3 ]; then
            warn "Few or no hooks installed. Run 'npx cc-safe-setup --shield' to add the recommended baseline."
        fi
    else
        note "  ${DIM}settings.json present (jq not installed; cannot count hooks)${NC}"
    fi
else
    bad "no ~/.claude/settings.json - hooks won't run. Run 'npx cc-safe-setup' to bootstrap."
fi
note ""

# --- Section 5: stale temp settings files ---
note "${BOLD}Temp files${NC}"
CURRENT_UID=$(id -u)
FOREIGN=$(find /tmp -maxdepth 1 -name 'claude-settings-*.json' -type f 2>/dev/null | while read -r f; do
    OWNER_UID=$(stat -c '%u' "$f" 2>/dev/null) || continue
    if [ "$OWNER_UID" != "$CURRENT_UID" ]; then
        echo "$f"
    fi
done)
if [ -n "$FOREIGN" ]; then
    warn "Foreign-owned /tmp/claude-settings-*.json found (Issue #57224 collision risk):"
    while IFS= read -r f; do
        OWNER=$(stat -c '%U' "$f" 2>/dev/null || echo "?")
        printf '    %s  (owner: %s)\n' "$f" "$OWNER"
    done <<< "$FOREIGN"
else
    ok "no foreign-owned claude-settings-*.json in /tmp"
fi
note ""

# --- Section 6: disk space for sessions ---
note "${BOLD}Disk${NC}"
SESSIONS_DIR="$HOME/.claude/projects"
if [ -d "$SESSIONS_DIR" ]; then
    SIZE_MB=$(du -sm "$SESSIONS_DIR" 2>/dev/null | awk '{print $1}')
    SIZE_MB=${SIZE_MB:-0}
    if [ "$SIZE_MB" -gt 5000 ]; then
        warn "Session history is ${SIZE_MB}MB - consider archiving old projects."
    elif [ "$SIZE_MB" -gt 1000 ]; then
        ok "Session history: ${SIZE_MB}MB"
    else
        ok "Session history: ${SIZE_MB}MB"
    fi
fi
note ""

# --- Summary ---
note "${BOLD}Summary${NC}"
if [ ${#CONCERNS[@]} -eq 0 ]; then
    ok "No concerns. Your Claude Code install looks healthy from the outside."
else
    note "${YELLOW}${#CONCERNS[@]} concern$([ ${#CONCERNS[@]} -eq 1 ] && echo "" || echo "s") flagged above.${NC}"
    note "Each line is read-only observation; nothing was changed."
    note "Apply the documented fixes from the messages, then re-run cc-doctor."
fi
note ""
note "${DIM}Source: github.com/yurukusa/cc-safe-setup${NC}"

exit 0
