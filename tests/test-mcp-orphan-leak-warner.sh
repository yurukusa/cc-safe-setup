#!/bin/bash
# Tests for mcp-orphan-leak-warner.sh
HOOK="$(cd "$(dirname "$0")/../examples" && pwd)/mcp-orphan-leak-warner.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1" result="$2"
  if [ "$result" = "pass" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; FAIL=$((FAIL + 1)); fi
}

# Spawn N fake "orphan" MCP servers: setsid detaches them so they reparent to
# PID 1, and exec -a gives them an MCP-signature argv. Track PIDs to clean up.
# Truly orphan the fake server: a subshell backgrounds it and exits immediately,
# so the sleep reparents to PID 1 (what the hook keys on). exec -a gives it an
# MCP-signature argv. A plain `setsid ... &` would NOT work — the test shell
# stays alive, so the child keeps PPID=test-shell, not 1.
spawn() {
  ( setsid bash -c "exec -a \"$1\" sleep 120" & ) 2>/dev/null
}
cleanup() {
  for p in $(ps -eo pid,comm 2>/dev/null | awk '$2=="sleep"{print $1}'); do
    # only kill sleeps whose argv we set (MCP signature)
    args=$(ps -o args= -p "$p" 2>/dev/null)
    case "$args" in *modelcontextprotocol*|*mcp-server*) kill -TERM "$p" 2>/dev/null ;; esac
  done
}

# run hook; print "exit|stderr_line_count". MIN_AGE=0 so young fakes count.
run() {
  local err rc
  err=$(printf '{}' | CC_MCP_ORPHAN_MIN_AGE=0 bash "$HOOK" 2>&1 1>/dev/null); rc=$?
  echo "$rc|$(printf '%s' "$err" | grep -c .)"
}

echo "Testing mcp-orphan-leak-warner.sh"
echo "================================="

# 1. No orphans → silent (exit 0, no stderr).
cleanup; sleep 1
R=$(run)
[ "${R%%|*}" = "0" ] && [ "${R##*|}" = "0" ] && run_test "no orphans → silent" pass || run_test "no orphans → silent ($R)" fail

# 2. Below threshold (2 < default 3) → still silent.
spawn "npx @modelcontextprotocol/server-a mcp"; spawn "uvx mcp-server-b"; sleep 1
R=$(run)
[ "${R%%|*}" = "0" ] && [ "${R##*|}" = "0" ] && run_test "2 orphans (< min 3) → silent" pass || run_test "below threshold → silent ($R)" fail

# 3. At threshold (3) → warns (non-empty stderr, still exit 0 advisory).
spawn "node mcp-server-c modelcontextprotocol"; sleep 1
R=$(run)
[ "${R%%|*}" = "0" ] && [ "${R##*|}" -gt 0 ] && run_test "3 orphans → warns (advisory, exit 0)" pass || run_test "at threshold → warns ($R)" fail

# 4. Never kills: the orphans are still alive after the hook ran.
ALIVE=$(ps -eo args= 2>/dev/null | grep -cE 'mcp-server-|@modelcontextprotocol')
[ "$ALIVE" -ge 3 ] && run_test "advisory only — orphans not killed" pass || run_test "advisory only ($ALIVE alive)" fail

# 5. A legitimate PID-1 daemon WITHOUT an MCP signature is not counted.
setsid bash -c 'exec -a "node /opt/myapp/server.js --port 9999" sleep 120' & disown
sleep 1
BEFORE=$(printf '{}' | CC_MCP_ORPHAN_MIN_AGE=0 bash "$HOOK" 2>&1 1>/dev/null | grep -oE '^NOTE: [0-9]+' | grep -oE '[0-9]+')
# killing the non-MCP daemon should not change the count
NONMCP=$(ps -eo pid,args= 2>/dev/null | grep 'myapp/server.js' | grep -v grep | awk '{print $1}' | head -1)
[ -n "${BEFORE:-}" ] && [ "${BEFORE}" = "3" ] && run_test "non-MCP PID-1 daemon excluded (count stays 3)" pass || run_test "non-MCP excluded (count=${BEFORE:-?})" fail
[ -n "$NONMCP" ] && kill -TERM "$NONMCP" 2>/dev/null

cleanup; sleep 1
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
