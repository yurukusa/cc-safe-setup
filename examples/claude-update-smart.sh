#!/usr/bin/env bash
# claude-update-smart.sh — skip 226 MB tarball download when already up-to-date
# Why: `claude update` downloads the full ~226 MB release tarball on every
#      invocation, even when the installed version is already latest (Issue
#      #51243, opened 2026-04-20, platform:wsl, status:open). A typical
#      connection sees ~30 s wall time per update check and silently burns
#      metered bandwidth.
# Fix: Before calling `claude update`, query the npm registry (~2 KB response)
#      for the latest version. If the installed `claude --version` matches,
#      exit 0 with "up to date" message and skip the download entirely. Cache
#      the registry lookup for 1 h to avoid repeated small queries.
# Install:
#   cp examples/claude-update-smart.sh ~/bin/claude-update  # shadow the real one
#   chmod +x ~/bin/claude-update
# Or alias in your shell rc:
#   alias claude-update='bash ~/path/to/claude-update-smart.sh'
#
# Environment overrides (for tests and offline use):
#   CLAUDE_UPDATE_SMART_LOCAL=x.y.z    force-reported local version
#   CLAUDE_UPDATE_SMART_LATEST=x.y.z   force-reported latest version
#   CLAUDE_UPDATE_SMART_CACHE=<path>   override cache location
#   CLAUDE_UPDATE_SMART_TTL=<seconds>  override cache TTL (default 3600)
#   CLAUDE_UPDATE_SMART_NO_EXEC=1      print the decision but do not call `claude update`

set -u

CACHE="${CLAUDE_UPDATE_SMART_CACHE:-${HOME}/.cache/claude-update-smart.json}"
TTL="${CLAUDE_UPDATE_SMART_TTL:-3600}"

mkdir -p "$(dirname "$CACHE")" 2>/dev/null

# Early bailout: if `claude` CLI is not installed at all and no LOCAL override is
# in scope, the hook has nothing to do. Common in CI runners and dev containers
# without Claude Code installed. The `${VAR+x}` test distinguishes "unset" (no
# scope) from "set to empty" (test fixtures asserting exit-127 fallback).
if ! command -v claude >/dev/null 2>&1 && [ -z "${CLAUDE_UPDATE_SMART_LOCAL+x}" ]; then
  echo "claude-update-smart: claude CLI not installed (advisory: nothing to update)" >&2
  exit 0
fi

# Resolve LOCAL version.
if [ -n "${CLAUDE_UPDATE_SMART_LOCAL:-}" ]; then
  LOCAL="$CLAUDE_UPDATE_SMART_LOCAL"
else
  LOCAL=$(claude --version 2>/dev/null | awk '{print $1}')
fi

if [ -z "${LOCAL:-}" ]; then
  echo "claude-update-smart: 'claude' not found or --version failed; falling through" >&2
  if [ "${CLAUDE_UPDATE_SMART_NO_EXEC:-0}" = "1" ]; then
    exit 127
  fi
  exec claude update "$@"
fi

# Resolve LATEST version (cache → npm → GitHub Releases).
LATEST=""
if [ -n "${CLAUDE_UPDATE_SMART_LATEST:-}" ]; then
  LATEST="$CLAUDE_UPDATE_SMART_LATEST"
else
  NOW=$(date +%s)
  CACHED_TIME=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  AGE=$((NOW - CACHED_TIME))
  if [ -s "$CACHE" ] && [ "$AGE" -lt "$TTL" ]; then
    LATEST=$(jq -r '.latest // empty' "$CACHE" 2>/dev/null)
  fi
  if [ -z "$LATEST" ]; then
    LATEST=$(npm view @anthropic-ai/claude-code version 2>/dev/null | tr -d '[:space:]')
  fi
  if [ -z "$LATEST" ]; then
    LATEST=$(curl -s --max-time 5 https://api.github.com/repos/anthropics/claude-code/releases/latest \
             | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
  fi
  if [ -n "$LATEST" ]; then
    printf '{"latest":"%s","checked_at":%s}\n' "$LATEST" "$NOW" > "$CACHE" 2>/dev/null
  fi
fi

if [ -z "$LATEST" ]; then
  echo "claude-update-smart: could not determine latest version (no network?); falling through" >&2
  if [ "${CLAUDE_UPDATE_SMART_NO_EXEC:-0}" = "1" ]; then
    echo "decision=fallthrough local=$LOCAL latest=unknown"
    exit 2
  fi
  exec claude update "$@"
fi

if [ "$LOCAL" = "$LATEST" ]; then
  echo "Claude Code is up to date ($LOCAL) — skipped 226 MB download (see #51243)"
  if [ "${CLAUDE_UPDATE_SMART_NO_EXEC:-0}" = "1" ]; then
    echo "decision=skip local=$LOCAL latest=$LATEST"
  fi
  exit 0
fi

echo "Update available: $LOCAL → $LATEST — running 'claude update'..."
if [ "${CLAUDE_UPDATE_SMART_NO_EXEC:-0}" = "1" ]; then
  echo "decision=update local=$LOCAL latest=$LATEST"
  exit 0
fi
exec claude update "$@"
