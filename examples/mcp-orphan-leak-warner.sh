#!/bin/bash
# mcp-orphan-leak-warner.sh — At session start, warn if leaked MCP / sub-agent
#   server processes from earlier sessions are still alive and piling up, before
#   they exhaust RAM/swap into an OOM / kernel panic.
#
# Solves a recurring May–June 2026 class (anthropics/claude-code #64366, #68647,
# #68933, #61748, …): MCP servers and sub-agent children outlive the
# session that spawned them — reparented to PID 1 — and accumulate until the box
# swaps to death or kernel-panics. This is *process/memory* exhaustion, distinct
# from MCP token/context bloat. The actionable moment is the start of your NEXT
# session, before you spawn more.
#
# Precision: ADVISORY ONLY. This hook never kills anything. Being reparented to
# PID 1 is not sufficient to call a process an orphan (legitimate daemons are
# PID-1-parented too), so it flags a process ONLY when it is BOTH (a) reparented
# to PID 1 AND (b) matches an MCP/agent-server command signature, and even then
# it only *reports*. You decide what to reap. It also stays silent unless the
# leak is real (>= MIN_COUNT orphans), to avoid nagging.
#
# TRIGGER: SessionStart

MIN_COUNT=${CC_MCP_ORPHAN_MIN_COUNT:-3}   # warn only at/above this many orphans
MIN_AGE=${CC_MCP_ORPHAN_MIN_AGE:-300}     # seconds; ignore freshly-started servers

# MCP / agent-server signatures: how Claude Code spawns MCP servers (npx/uvx
# launchers, @modelcontextprotocol packages, *mcp-server* binaries). Tuned to
# avoid matching editors, shells, or your own long-running daemons.
SIG='@modelcontextprotocol|mcp-server-|modelcontextprotocol|[/ ]mcp([ _-]|$)|uvx[^|]*mcp|npx[^|]*mcp'

read -r COUNT TOTAL_KB < <(ps -eo ppid=,etimes=,rss=,args= 2>/dev/null \
  | awk -v sig="$SIG" -v minage="$MIN_AGE" '
      $1==1 && $2>=minage {
        args=""; for(i=4;i<=NF;i++) args=args (i>4?" ":"") $i
        if (args ~ sig) { c++; kb+=$3 }
      }
      END { print c+0, kb+0 }')

[ "${COUNT:-0}" -lt "$MIN_COUNT" ] && exit 0

{
  echo "NOTE: $COUNT leaked MCP / sub-agent server process(es) from earlier sessions"
  echo "are still alive (~$((TOTAL_KB/1024)) MB resident, reparented to PID 1). Left to"
  echo "pile up these can exhaust RAM/swap into an OOM or kernel panic (#64366, #68647)."
  echo "Review them:    ps -o pid,etimes,rss,args -p \$(pgrep -f 'mcp-server-|@modelcontextprotocol')"
  echo "Reap safely:    kill the ones you recognize as dead-session leftovers."
  echo "Prevent a panic: cap memory for heavy sessions:  ( ulimit -v 8000000; claude )"
} >&2

exit 0
