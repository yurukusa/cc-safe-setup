#!/bin/bash
# fabricated-command-detector.sh — Detect command-shaped tokens in the final
# assistant response that were never invoked as Bash tool calls in the session.
#
# Solves: substitution-by-default at the response layer (issue #60340).
#   In #60340, a security-research reproduction shipped with `./exploit` as
#   the command in the assistant's writeup, while the operator's actual
#   reproduction command (`./chage_pwn root`) was established through dozens
#   of Bash tool calls. The model never invoked `./exploit` — it generated
#   a plausible-looking parallel command and substituted it into the response.
#
# How it works: Stop hook that reads the latest assistant turn from the
#   session transcript, extracts command-shaped tokens (./xxx, git xxx,
#   bash xxx, etc.) from inline code spans, and cross-references each one
#   against the Bash tool calls that actually occurred in the session.
#   Tokens that look like commands but were never invoked are flagged as
#   possible fabrication.
#
# This hook is advisory by default — it warns to stderr and exits 0.
# It does not block the response. Set CC_FABRICATED_CMD_BLOCK=1 to make
# unverified tokens cause a non-zero exit (use for high-stakes contexts
# like security reproductions).
#
# TRIGGER: Stop
# MATCHER: ""
#
# Configuration:
#   CC_FABRICATED_CMD_DISABLE=1    Disable the hook completely.
#   CC_FABRICATED_CMD_BLOCK=1      Exit non-zero (exit 2) when fabricated
#                                  tokens are detected. Default: advisory.
#   CC_FABRICATED_CMD_ALLOW=regex  Pattern of tokens to ignore (e.g. for
#                                  hypothetical example commands). Matched
#                                  with `grep -E` against the token text.
#   CC_FABRICATED_CMD_MAX=20       Maximum tokens to scan per response.
#                                  Default 20. Cap protects performance on
#                                  very long responses.

set -u

[ "${CC_FABRICATED_CMD_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Extract the LAST assistant message text content from the transcript.
# Transcript is jsonl: one event per line. Look for the last assistant
# message and concatenate its text content blocks.
LAST_ASSISTANT=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"role":"assistant"' || true)
[ -z "$LAST_ASSISTANT" ] && exit 0

# Try a few schemas for the assistant text. Newer transcripts wrap content
# as an array of typed blocks; older ones may use a flat text field.
RESPONSE_TEXT=$(printf '%s' "$LAST_ASSISTANT" | jq -r '
  if .message.content then
    (.message.content | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end)
  elif .content then
    (.content | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end)
  else
    empty
  end
' 2>/dev/null)

[ -z "$RESPONSE_TEXT" ] && exit 0

# Extract command-shaped tokens from backtick inline code in the response.
# Patterns that look like operator commands the response is asserting were
# (or are to be) run:
#   - ./xxx and ./xxx_yyy and ./bin/xxx (relative executables)
#   - git <subcommand> ... (git invocations)
#   - bash <script>, sh <script> (shell-script invocations)
#   - npm/pnpm/yarn run <task>
#   - python <script>, node <script>
MAX_TOKENS="${CC_FABRICATED_CMD_MAX:-20}"
ALLOW_PATTERN="${CC_FABRICATED_CMD_ALLOW:-}"

# Extract inline code spans (backtick-fenced single-line content)
TOKENS=$(printf '%s\n' "$RESPONSE_TEXT" \
  | grep -oE '`[^`]+`' 2>/dev/null \
  | sed -e 's/^`//' -e 's/`$//' \
  | grep -E '^(\./|git[[:space:]]+[a-z]+|bash[[:space:]]+[^[:space:]]|sh[[:space:]]+[^[:space:]]|npm[[:space:]]+run|pnpm[[:space:]]+run|yarn[[:space:]]+run|python[[:space:]]+[^[:space:]]+\.py|node[[:space:]]+[^[:space:]]+\.[mc]?js)' 2>/dev/null \
  | sort -u \
  | head -n "$MAX_TOKENS")

[ -z "$TOKENS" ] && exit 0

# Apply ALLOW filter if set
if [ -n "$ALLOW_PATTERN" ]; then
  TOKENS=$(printf '%s\n' "$TOKENS" | grep -Ev "$ALLOW_PATTERN" 2>/dev/null || true)
fi

[ -z "$TOKENS" ] && exit 0

# Extract all Bash tool-call commands from the entire transcript.
# Look at tool_use events with name=Bash and pull their command input.
INVOKED_COMMANDS=$(grep -h '"name":"Bash"' "$TRANSCRIPT" 2>/dev/null \
  | jq -r '
    if .message.content then
      (.message.content[]? | select(.type == "tool_use" and .name == "Bash") | .input.command // empty)
    elif .content then
      (.content[]? | select(.type == "tool_use" and .name == "Bash") | .input.command // empty)
    else empty end
  ' 2>/dev/null)

# Compare each candidate token against the invoked commands.
# A token is "verified" if its command-shaped form appears as a substring
# of any invoked command (matches the literal sequence the operator ran).
UNVERIFIED=""
while IFS= read -r token; do
  [ -z "$token" ] && continue
  # Escape token for fixed-string match
  if ! printf '%s' "$INVOKED_COMMANDS" | grep -Fq -- "$token" 2>/dev/null; then
    UNVERIFIED="${UNVERIFIED}${UNVERIFIED:+$'\n'}${token}"
  fi
done <<< "$TOKENS"

[ -z "$UNVERIFIED" ] && exit 0

# Emit advisory listing unverified tokens.
echo "⚠ fabricated-command-detector: command-shaped tokens in the response were not invoked as Bash tool calls in this session:" >&2
printf '%s\n' "$UNVERIFIED" | while IFS= read -r line; do
  [ -n "$line" ] && echo "  - $line" >&2
done
echo "  Verify each token before relying on the response as an operational record." >&2
echo "  See issue #60340 for the failure shape (substitution-by-default at the response layer)." >&2

if [ "${CC_FABRICATED_CMD_BLOCK:-0}" = "1" ]; then
  exit 2
fi

exit 0
