#!/bin/bash
# env-var-check.sh — Warn when setting environment variables with secrets
#
# Solves: Claude hardcoding API keys or passwords into export commands
# that end up in shell history and process environment.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/env-var-check.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-env-var-check-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [env-var-check]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Check for export/set with sensitive-looking values
if echo "$COMMAND" | grep -qiE 'export\s+(API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIALS|AUTH)='; then
    echo "" >&2
    echo "⚠ SECURITY: Setting sensitive environment variable in shell" >&2
    echo "This will appear in shell history. Use .env files or secret managers instead." >&2
    echo "Command: $COMMAND" >&2
fi

# Check for hardcoded key patterns (sk-, pk-, ghp_, etc.)
if echo "$COMMAND" | grep -qE 'export\s+\w+=.*(ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|glpat-[a-zA-Z0-9]{20,})'; then
    echo "BLOCKED: Hardcoded API key detected in export command" >&2
    echo "Use: export VAR=\$(cat ~/.credentials/key)" >&2
    exit 2
fi

# OpenAI keys. 2026-08: いまの鍵は `sk-proj-` の形で区切りを含むため文字集合に `-` `_` を入れる。
# 入れると `disk-usage-…` `task-management-…` の中の `sk-` へ当たるので左の境界が要る。
# ★ただし `export\s+\w+=` が境界にしたい `=` を先に食ってしまうので、
#   同じ grep の中に書くと `export API_KEY=sk-…` に当たらなくなる（既存のテストで判明）。
#   そこで規則を切り出し、「`=` の直後」と「途中」を分けて書く。
if echo "$COMMAND" | grep -qE 'export\s+\w+=(sk-[A-Za-z0-9_-]{20,}|.*[^A-Za-z0-9]sk-[A-Za-z0-9_-]{20,})'; then
    echo "BLOCKED: Hardcoded API key detected in export command" >&2
    echo "Use: export VAR=\$(cat ~/.credentials/key)" >&2
    exit 2
fi

exit 0
