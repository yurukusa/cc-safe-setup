#!/bin/bash
# fire.sh — fire one Claude Code hook by hand and print what it decided.
#
# Why this exists: installing a hook and having a hook are not the same thing.
# The only evidence that a guard works is that it exits 2 when you hand it the
# operation it is supposed to refuse. This script hands it that operation.
#
# Usage:
#   ./fire.sh <hook-script> <tool-name> <json-field>=<value> [more=fields...]
#
# Examples:
#   ./fire.sh ~/.claude/hooks/rm-safety-net.sh Bash command="rm -rf \$HOME/projects"
#   ./fire.sh ~/.claude/hooks/env-write-guard.sh Write file_path=/home/me/app/.env
#
# Exit codes you will see printed:
#   2  the hook refused the operation   <- what a working guard does
#   0  the hook allowed the operation   <- if you expected a refusal, it is not working
#   1  the hook itself errored          <- it is not protecting you either
#
# Two flags matter for the audit:
#   --bare   run with a PATH that has no jq, no python3 and no node.
#            Many hooks parse the tool-call JSON with one of those. On a
#            minimal container or a fresh CI image they are absent, and a hook
#            that cannot parse its input often exits 0 (allow) instead of 2.
#   --home   run with a throwaway HOME so the hook cannot touch your real
#            ~/.claude while you are testing. On by default.
#
set -u

BARE=0
for a in "$@"; do [ "$a" = "--bare" ] && BARE=1; done
ARGS=(); for a in "$@"; do [ "$a" = "--bare" ] || ARGS+=("$a"); done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [ $# -lt 2 ]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

HOOK="$1"; TOOL="$2"; shift 2

if [ ! -f "$HOOK" ]; then
  echo "fire.sh: no such hook: $HOOK" >&2
  exit 64
fi

# Build the tool-call JSON that Claude Code would send on stdin.
# Values are passed through a JSON string escaper so quotes and backslashes survive.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
fields=""
for kv in "$@"; do
  k="${kv%%=*}"; v="${kv#*=}"
  [ -n "$fields" ] && fields="$fields,"
  fields="$fields\"$(esc "$k")\":\"$(esc "$v")\""
done
PAYLOAD="{\"tool_name\":\"$(esc "$TOOL")\",\"tool_input\":{$fields}}"

SANDBOX_HOME=$(mktemp -d)
cleanup() {
  [ -n "${FAKEBIN:-}" ] && [ -d "$FAKEBIN" ] && { find "$FAKEBIN" -maxdepth 1 -type l -delete 2>/dev/null; rmdir "$FAKEBIN" 2>/dev/null; }
  rmdir "$SANDBOX_HOME" 2>/dev/null || true
}
trap cleanup EXIT

FAKEBIN=""
if [ "$BARE" = "1" ]; then
  # A PATH with the shell tools a hook needs to run at all, but without any
  # JSON parser. This is what a slim container looks like.
  FAKEBIN=$(mktemp -d)
  for c in bash sh env printf echo grep sed awk tr cat cut head tail sort uniq wc dirname basename mktemp rmdir find ln test true false date id whoami; do
    p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$FAKEBIN/$c" 2>/dev/null
  done
  for j in jq python3 python node; do
    if PATH="$FAKEBIN" command -v "$j" >/dev/null 2>&1; then
      echo "fire.sh: --bare failed: $j is still reachable" >&2; exit 70
    fi
  done
fi

OUT=$(mktemp); trap 'rm -f "$OUT" 2>/dev/null; cleanup' EXIT
if [ "$BARE" = "1" ]; then
  printf '%s' "$PAYLOAD" | HOME="$SANDBOX_HOME" PATH="$FAKEBIN" bash "$HOOK" >"$OUT" 2>&1
else
  printf '%s' "$PAYLOAD" | HOME="$SANDBOX_HOME" bash "$HOOK" >"$OUT" 2>&1
fi
CODE=$?

echo "hook   : $HOOK"
echo "input  : $PAYLOAD"
[ "$BARE" = "1" ] && echo "mode   : --bare (no jq, no python3, no node)"
echo "exit   : $CODE  $( [ "$CODE" = 2 ] && echo '(refused)' || { [ "$CODE" = 0 ] && echo '(allowed)' || echo '(hook error)'; } )"
if [ -s "$OUT" ]; then
  echo "message:"
  sed 's/^/  /' "$OUT" | head -20
fi
exit "$CODE"
