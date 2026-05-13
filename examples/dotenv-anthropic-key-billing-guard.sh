#!/bin/bash
# dotenv-anthropic-key-billing-guard.sh — Warn when project .env contains ANTHROPIC_API_KEY
#
# Solves: Reddit r/ClaudeAI 1tbaq2d (314 points, 86 comments as of 2026-05-13)
#         "If your project has an ANTHROPIC_API_KEY in any .env file,
#          Claude Code will silently bill your API account instead of your Max plan."
#         User reported 9 auto-recharge events totaling ~$187 USD loss.
#         Anthropic support confirmed: "this is intentional functionality."
#
# WHY THIS MATTERS:
#   When .env contains ANTHROPIC_API_KEY=sk-ant-..., Claude Code shells inherit
#   the variable and the model client prefers the env var over the Max plan
#   subscription credentials. The user sees no warning, no UI indicator;
#   billing silently routes to the API account and prepaid funds get
#   consumed (and are non-refundable per Anthropic policy).
#
#   This is the exact "claim-verify gap" pattern: the user's mental model
#   ("I'm on Max plan, billing is fixed") diverges from system reality
#   (env var overrides Max plan, billing is per-token).
#
# TRIGGER: SessionStart  MATCHER: ""
#
# CONFIGURATION:
#   CC_DOTENV_AK_FILES — comma-separated filenames to check
#                        (default: .env,.env.local,.env.development,.env.production,.env.dev)
#   CC_DOTENV_AK_ACTION — "warn" or "block" (default: warn)
#   CC_DOTENV_AK_LOG — log file path (default: /tmp/cc-dotenv-ak-warnings.log)
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/dotenv-anthropic-key-billing-guard.sh" }]
#     }]
#   }
# }

FILES="${CC_DOTENV_AK_FILES:-.env,.env.local,.env.development,.env.production,.env.dev}"
ACTION="${CC_DOTENV_AK_ACTION:-warn}"
LOG_FILE="${CC_DOTENV_AK_LOG:-/tmp/cc-dotenv-ak-warnings.log}"

# Determine project root: prefer CLAUDE_PROJECT_DIR, fall back to PWD
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$PROJECT_ROOT" ] || exit 0

FOUND_FILES=()

IFS=',' read -ra PATTERNS <<< "$FILES"
for pat in "${PATTERNS[@]}"; do
  pat=$(echo "$pat" | xargs)  # trim whitespace
  [ -z "$pat" ] && continue
  candidate="$PROJECT_ROOT/$pat"
  if [ -f "$candidate" ]; then
    # Match a non-empty assignment (allow optional spaces, optional export, optional quotes)
    # Skip lines that are commented out (start with #)
    if grep -qE '^[[:space:]]*(export[[:space:]]+)?ANTHROPIC_API_KEY[[:space:]]*=[[:space:]]*["'"'"']?[^[:space:]"'"'"'#][^"'"'"'#]*' "$candidate" 2>/dev/null; then
      FOUND_FILES+=("$candidate")
    fi
  fi
done

# If no offending files, pass through silently
if [ ${#FOUND_FILES[@]} -eq 0 ]; then
  exit 0
fi

# Found offending file(s) — log and notify
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
for f in "${FOUND_FILES[@]}"; do
  echo "[$TIMESTAMP] $f contains ANTHROPIC_API_KEY action=$ACTION" >> "$LOG_FILE"
done

# Build human-readable message
MSG="⚠️  ANTHROPIC_API_KEY detected in project .env file(s):"
for f in "${FOUND_FILES[@]}"; do
  MSG+=$'\n'"     - $f"
done
MSG+=$'\n'
MSG+=$'\n'"  Claude Code shell tools inherit env vars from the project, and the"
MSG+=$'\n'"  client prefers ANTHROPIC_API_KEY over the Max plan subscription."
MSG+=$'\n'"  Result: API charges may silently consume prepaid funds while you"
MSG+=$'\n'"  believe you are on the flat-rate Max plan. Refunds are not offered"
MSG+=$'\n'"  for funds already consumed."
MSG+=$'\n'
MSG+=$'\n'"  Mitigations:"
MSG+=$'\n'"    1. Remove the ANTHROPIC_API_KEY line from the .env file, OR"
MSG+=$'\n'"    2. Set ANTHROPIC_API_KEY= (empty) at the start of your shell session, OR"
MSG+=$'\n'"    3. Move the key to a separate file that is not auto-sourced."
MSG+=$'\n'
MSG+=$'\n'"  Reference: reddit.com/r/ClaudeAI/comments/1tbaq2d/  ($187 loss reported)"

if [ "$ACTION" = "block" ]; then
  # SessionStart cannot truly block, but exit 2 surfaces error to user.
  printf '%s\n' "$MSG" >&2
  exit 2
else
  printf '%s\n' "$MSG" >&2
  exit 0
fi
