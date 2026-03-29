#!/bin/bash
# mcp-orphan-process-guard.sh — Detect orphaned MCP server processes
#
# Solves: MCP server containers not stopped when Claude Code exits (#29058).
#         Docker containers and background processes accumulate over sessions.
#
# How it works: Stop hook that checks for running MCP-related processes
#   and warns about potential orphans.
#
# TRIGGER: Stop
# MATCHER: ""

set -euo pipefail

# Check for running MCP-related processes
ORPHANS=""

# Docker containers with MCP-like names
if command -v docker &>/dev/null; then
  MCP_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'mcp|claude|anthropic' || true)
  if [ -n "$MCP_CONTAINERS" ]; then
    ORPHANS="${ORPHANS}Docker containers: ${MCP_CONTAINERS}\n"
  fi
fi

# Node/Python processes that might be MCP servers
MCP_PROCS=$(ps aux 2>/dev/null | grep -iE 'mcp.*server|@modelcontextprotocol' | grep -v grep || true)
if [ -n "$MCP_PROCS" ]; then
  COUNT=$(echo "$MCP_PROCS" | wc -l)
  ORPHANS="${ORPHANS}MCP processes: ${COUNT} running\n"
fi

if [ -n "$ORPHANS" ]; then
  echo "WARNING: Potential orphaned MCP processes detected:" >&2
  echo -e "$ORPHANS" >&2
  echo "Consider stopping them: docker stop <name> or kill <pid>" >&2
fi

exit 0
