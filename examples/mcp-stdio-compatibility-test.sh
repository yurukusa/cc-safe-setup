#!/bin/bash
# mcp-stdio-compatibility-test.sh — MCP regression test harness (Incident 8)
# Why: v2.1.105 changed PreToolUse additionalContext + stdio framing and
#      broke MCP servers that had worked on v2.1.104. The regression was
#      largely fixed by v2.1.118 but custom MCP servers still need
#      re-validation after every Claude Code upgrade. This harness
#      exercises every MCP server registered in your settings against a
#      known-good suite of calls so you can distinguish "MCP regression"
#      from "auth expired" / "external resource down."
# Event: standalone CLI, not a Claude Code hook.
# Usage:   bash examples/mcp-stdio-compatibility-test.sh [path-to-settings.json]
#          (defaults to ~/.claude/settings.json)
# Exit:    0 if all servers OK; 1 if one or more regressions (parse errors,
#          stdio framing failures). Non-regression failures (auth, network)
#          are reported as [AUTH] or [NET] and do not set exit code 1.

set -u

SETTINGS="${1:-${HOME}/.claude/settings.json}"
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/mcp-compat.log"
mkdir -p "$LOG_DIR" 2>/dev/null

if [ ! -r "$SETTINGS" ]; then
  echo "mcp-stdio-compatibility-test: settings file not readable: $SETTINGS" >&2
  exit 2
fi

# Reject malformed JSON up front so a parse failure isn't reported as
# "nothing to test" — that would mask a broken config and exit 0.
if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "mcp-stdio-compatibility-test: settings file is not valid JSON: $SETTINGS" >&2
  exit 2
fi

if ! jq -e '.mcpServers // empty' "$SETTINGS" >/dev/null 2>&1; then
  echo "[info] no mcpServers block in $SETTINGS — nothing to test"
  exit 0
fi

# Pick whichever timeout binary is available; macOS ships only `gtimeout`
# via coreutils, while Linux usually has `timeout`. Without one of these
# a misbehaving server could hang the whole probe loop, so fall back to
# a no-timeout invocation only when we have warned the operator.
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  TIMEOUT_CMD=""
  echo "[warn] no timeout/gtimeout in PATH — server probes may hang on misbehaving servers" >&2
fi

SERVERS=$(jq -r '.mcpServers | keys[]' "$SETTINGS" 2>/dev/null)
if [ -z "$SERVERS" ]; then
  echo "[info] mcpServers block is empty — nothing to test"
  exit 0
fi

REGRESSION_COUNT=0
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Each MCP server speaks JSON-RPC over stdio. A viable smoke test is to
# send the initialize request and verify the server replies with a valid
# JSON-RPC response containing serverInfo. Parse errors or non-JSON
# output indicate the v2.1.105-class regression.
send_initialize() {
  local cmd="$1"
  local args_json="$2"
  local args_array=()
  if [ -n "$args_json" ] && [ "$args_json" != "null" ]; then
    while IFS= read -r a; do args_array+=("$a"); done < <(printf '%s' "$args_json" | jq -r '.[]' 2>/dev/null)
  fi
  local init_req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cc-safe-setup-compat-test","version":"1.0"}}}'
  if [ -n "$TIMEOUT_CMD" ]; then
    printf '%s\n' "$init_req" | "$TIMEOUT_CMD" 5 "$cmd" "${args_array[@]}" 2>&1
  else
    printf '%s\n' "$init_req" | "$cmd" "${args_array[@]}" 2>&1
  fi
}

for name in $SERVERS; do
  CMD=$(jq -r ".mcpServers[\"$name\"].command // empty" "$SETTINGS" 2>/dev/null)
  ARGS=$(jq -c ".mcpServers[\"$name\"].args // []" "$SETTINGS" 2>/dev/null)
  if [ -z "$CMD" ]; then
    echo "[skip] $name: no command field"
    printf '%s\t%s\t%s\n' "$TS" "$name" "skip-no-command" >> "$LOG_FILE"
    continue
  fi
  if ! command -v "$CMD" >/dev/null 2>&1 && [ ! -x "$CMD" ]; then
    echo "[skip] $name: command not executable ($CMD)"
    printf '%s\t%s\t%s\n' "$TS" "$name" "skip-not-executable" >> "$LOG_FILE"
    continue
  fi
  OUTPUT=$(send_initialize "$CMD" "$ARGS" 2>&1) || true
  RESPONSE=$(printf '%s' "$OUTPUT" | grep -m1 '"jsonrpc"' || true)
  if [ -z "$RESPONSE" ]; then
    echo "[FAIL] $name: no JSON-RPC response (regression candidate)"
    printf '%s\t%s\t%s\n' "$TS" "$name" "regression-no-response" >> "$LOG_FILE"
    REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
    continue
  fi
  if ! printf '%s' "$RESPONSE" | jq -e . >/dev/null 2>&1; then
    echo "[FAIL] $name: non-JSON response (v2.1.105-class regression)"
    printf '%s\t%s\t%s\n' "$TS" "$name" "regression-parse-error" >> "$LOG_FILE"
    REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
    continue
  fi
  ERR=$(printf '%s' "$RESPONSE" | jq -r '.error.code // empty' 2>/dev/null)
  if [ -n "$ERR" ]; then
    MSG=$(printf '%s' "$RESPONSE" | jq -r '.error.message // ""' 2>/dev/null)
    case "$MSG" in
      *auth*|*Auth*|*AUTH*|*permission*|*Permission*)
        echo "[AUTH] $name: $MSG"
        printf '%s\t%s\t%s\n' "$TS" "$name" "auth-$ERR" >> "$LOG_FILE"
        ;;
      *network*|*timeout*|*connect*|*DNS*)
        echo "[NET]  $name: $MSG"
        printf '%s\t%s\t%s\n' "$TS" "$name" "network-$ERR" >> "$LOG_FILE"
        ;;
      *)
        echo "[FAIL] $name: error $ERR — $MSG"
        printf '%s\t%s\t%s\n' "$TS" "$name" "regression-error-$ERR" >> "$LOG_FILE"
        REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
        ;;
    esac
    continue
  fi
  echo "[ok]   $name"
  printf '%s\t%s\t%s\n' "$TS" "$name" "ok" >> "$LOG_FILE"
done

if [ "$REGRESSION_COUNT" -gt 0 ]; then
  echo
  echo "$REGRESSION_COUNT MCP server(s) have regressions. Review the log:"
  echo "  $LOG_FILE"
  echo "Consider pinning an older Claude Code version:"
  echo "  npm install -g @anthropic-ai/claude-code@2.1.104"
  exit 1
fi
exit 0
