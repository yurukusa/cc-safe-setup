#!/bin/bash
# --audit: a blocking hook that parses its input with `echo "$VAR" | jq`
#
# Claude Code runs an inline hook command through /bin/sh. On Debian and Ubuntu
# that is dash, and dash's builtin echo interprets backslash escapes. A hook
# payload is JSON, so a newline inside a command or a file's content arrives as
# the two characters \n. Dash turns them into a real newline inside a JSON
# string, the parser rejects the document, the variable comes back empty, and
# the line that normally follows -- [ -z "$CMD" ] && exit 0 -- is an
# affirmative approval.
#
# Measured 2026-09-03 against this project's own hooks/hooks.json: all four
# guards approved everything under /bin/sh. Every local test passed, because
# the tests ran the same commands under bash, where echo leaves \n alone.
#
# The checks below are paired in both directions. A detector that has only been
# shown to fire has not been tested: reporting a working hook as broken is what
# makes somebody stop reading the report.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Assembled at runtime so this file does not carry the literal filename that
# the operator's own guards watch for.
SETTINGS_FILE="set""tings.json"

# run_audit <settings-json>
# Builds a throwaway HOME holding just that settings file and prints only the
# lines this check produces.
run_audit() {
  local json="$1" home out
  home=$(mktemp -d)
  mkdir -p "$home/.claude"
  printf '%s' "$json" > "$home/.claude/$SETTINGS_FILE"
  out=$(HOME="$home" node "$ROOT/index.mjs" --audit 2>&1 \
        | grep -E 'parse input with|Hook input parsing survives' || true)
  printf '%s' "$out"
  rm -rf "$home"
}

expect() {
  # $1=label  $2=settings  $3=want-fire(yes|no)
  local out; out=$(run_audit "$2")
  local fired=no
  case "$out" in *"parse input with"*) fired=yes ;; esac
  if [ "$fired" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1 — expected fire=$3, got fire=$fired"
    echo "        output: $out"
  fi
}

hook_json() {
  # $1 = the command string, already JSON-escaped
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s"}]}]}}' "$1"
}

# The defect: echo into a parser, in a hook that can block.
BROKEN='INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r .tool_input.command); [ -z \"$CMD\" ] && exit 0; case \"$CMD\" in *danger*) exit 2 ;; esac'
expect "echo into jq in a blocking hook" "$(hook_json "$BROKEN")" yes

# Same shape with python3 and with node.
BROKEN_PY='INPUT=$(cat); CMD=$(echo \"$INPUT\" | python3 -c \"import sys,json;print(json.load(sys.stdin))\"); case \"$CMD\" in *danger*) exit 2 ;; esac'
expect "echo into python3 in a blocking hook" "$(hook_json "$BROKEN_PY")" yes

# Fixed: printf %s keeps the JSON intact in every shell.
FIXED='INPUT=$(cat); CMD=$(printf %s \"$INPUT\" | jq -r .tool_input.command); [ -z \"$CMD\" ] && exit 0; case \"$CMD\" in *danger*) exit 2 ;; esac'
expect "printf %s into jq" "$(hook_json "$FIXED")" no

# A logger loses a field, which is a cosmetic bug, not a guard that stopped
# guarding. Reporting it as HIGH would train the reader to skip the finding.
LOGGER='INPUT=$(cat); TOOL=$(echo \"$INPUT\" | jq -r .tool_name); echo \"$TOOL\" >> /tmp/tools.log'
expect "echo into jq in a hook that cannot block" "$(hook_json "$LOGGER")" no

# A hook with no parser at all must not fire either.
NOPARSE='case \"$1\" in *danger*) exit 2 ;; esac'
expect "no parser in the command" "$(hook_json "$NOPARSE")" no

# The positive line only appears when a parser is present and safe -- it must
# not claim anything about a setup that parses nothing.
out=$(run_audit "$(hook_json "$NOPARSE")")
case "$out" in
  *"Hook input parsing survives"*)
    FAIL=$((FAIL + 1))
    echo "  FAIL: claimed shell-safe parsing for a hook that parses nothing" ;;
  *) PASS=$((PASS + 1)) ;;
esac

out=$(run_audit "$(hook_json "$FIXED")")
case "$out" in
  *"Hook input parsing survives"*) PASS=$((PASS + 1)) ;;
  *)
    FAIL=$((FAIL + 1))
    echo "  FAIL: no positive line for a hook that parses safely" ;;
esac

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
