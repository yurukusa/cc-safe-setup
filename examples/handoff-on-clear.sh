#!/bin/bash
# handoff-on-clear.sh — Write a handoff note at /clear, before the context goes
#
# Solves: /clear wipes the conversation with no chance to act first, and no hook
#         can block it — slash commands never reach UserPromptSubmit (measured
#         2026-09-19 on 2.1.270; the table is in clear-command-confirm-guard.sh).
#         People ask for a PreClear event for exactly this (#95199).
#
# How it works: SessionEnd fires with reason="clear", and at that moment
#   transcript_path still points at a readable file — 271,593 bytes of it in the
#   run this was measured on. The conversation is not gone yet, so this hook
#   reads it and writes HANDOFF.md next to the project before the wipe.
#
#   This is "derive and save", never "hold on, are you sure". SessionEnd cannot
#   cancel the clear and gives no ordering guarantee against the wipe.
#
# TRIGGER: SessionEnd
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionEnd": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/handoff-on-clear.sh" }]
#     }]
#   }
# }

set -uo pipefail
INPUT=$(cat)

# Without jq there is nothing to read the event with. Say so rather than failing
# silently: a handoff that never gets written looks identical to one not needed.
if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING [handoff-on-clear]: jq not found - no handoff will be written. Install jq." >&2
  exit 0
fi

# Only /clear. The other SessionEnd reasons (prompt_input_exit, logout) end the
# session without the user losing context they expected to keep.
[ "$(printf '%s' "$INPUT" | jq -r '.reason // empty')" = "clear" ] || exit 0

tp=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
if [ -z "$tp" ] || [ ! -f "$tp" ]; then
  echo "WARNING [handoff-on-clear]: no readable transcript at '$tp' - nothing written." >&2
  exit 0
fi

out="${cwd:-.}/HANDOFF.md"
{
  printf '# Handoff (written at /clear, %s)\n\n' "$(date -Is)"
  printf -- '- transcript: `%s`\n' "$tp"
  printf -- '- turns: %s user / %s assistant\n\n' \
    "$(jq -rs '[.[] | select(.type=="user")] | length' "$tp" 2>/dev/null)" \
    "$(jq -rs '[.[] | select(.type=="assistant")] | length' "$tp" 2>/dev/null)"
  printf '## Last thing you asked for\n\n'
  jq -rs '[.[] | select(.type=="user") | .message.content] | last
          | if type=="array" then map(select(.type=="text").text) | join("\n") else . end' \
     "$tp" 2>/dev/null | head -c 1200
  printf '\n'
} > "$out"

echo "handoff-on-clear: wrote $out" >&2
exit 0
