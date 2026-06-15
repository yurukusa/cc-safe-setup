#!/bin/bash
# cc-safe-setup demo — hooks stopping real disasters. Every block shown is
# the actual example hook running, with its real exit code and message.
EX="$HOME/projects/cc-loop/cc-safe-setup/examples"
G=$'\033[32m'; R=$'\033[31m'; C=$'\033[36m'; D=$'\033[2m'; B=$'\033[1m'; Y=$'\033[33m'; NC=$'\033[0m'
pause() { sleep "${1:-1.0}"; }

# Setup (real): a project with source files the AI is about to wipe, and a
# real credential-shaped file. Done before the visible part.
PROJ=$(mktemp -d -t demo-proj-XXXX)
mkdir -p "$PROJ/src"; for i in $(seq 1 15); do echo "export const m$i = () => {}" > "$PROJ/src/mod$i.ts"; done

run_hook() { # name, hookfile, command-json, command-display
  printf '  %s$%s %sclaude%s wants to run:  %s%s%s\n' "$D" "$NC" "$C" "$NC" "$R" "$4" "$NC"; pause 0.8
  printf '  %s↳ PreToolUse hook: %s%s\n' "$D" "$2" "$NC"; pause 0.9
  local out ec
  out=$(printf '%s' "$3" | bash "$EX/$2" 2>&1); ec=$?
  printf '%s\n' "$out" | sed "s/^/    $R/; s/$/$NC/"
  if [ "$ec" -eq 2 ]; then
    printf '  %s✓ blocked — exit %s, the action never runs.%s\n\n' "$G" "$ec" "$NC"
  else
    printf '  %s(exit %s)%s\n\n' "$D" "$ec" "$NC"
  fi
  pause 1.3
}

clear
printf '%s%scc-safe-setup%s %s— hooks that stop Claude Code before the damage%s\n' "$B" "$C" "$NC" "$D" "$NC"
printf '%severy block below is the real example hook, with its real exit code%s\n\n' "$D" "$NC"
pause 1.3

printf '%s1) The AI reaches for a recursive delete over your source tree%s\n' "$B" "$NC"; pause 0.5
run_hook "delete" "bulk-file-delete-guard.sh" \
  "{\"tool_input\":{\"command\":\"rm -rf $PROJ/src\"}}" \
  "rm -rf $PROJ/src"

printf '%s2) The AI tries to read a credential file "to debug the auth"%s\n' "$B" "$NC"; pause 0.5
run_hook "creds" "credential-file-cat-guard.sh" \
  '{"tool_input":{"command":"cat ~/.netrc"}}' \
  "cat ~/.netrc"

printf '%sThe hooks run on every tool call — even while you are away from the keyboard.%s\n' "$B" "$NC"
printf '%s~800 example hooks, MIT-licensed:%s %sgithub.com/yurukusa/cc-safe-setup%s\n' "$D" "$NC" "$C" "$NC"
pause 2.2
rm -rf "$PROJ" 2>/dev/null
