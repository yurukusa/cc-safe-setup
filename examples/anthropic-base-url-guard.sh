#!/bin/bash
# anthropic-base-url-guard.sh — Block execution when ANTHROPIC_BASE_URL is suspicious
#
# Solves: #51123 — Setting ANTHROPIC_BASE_URL to a local proxy bypasses
#         allowManagedHooksOnly enforcement. This hook detects when the
#         URL points to non-standard endpoints and warns/blocks.
#
# WHY THIS MATTERS:
#   Enterprise admins set allowManagedHooksOnly: true to restrict hooks.
#   A developer can set ANTHROPIC_BASE_URL=http://localhost:4010 and
#   bypass ALL managed hook restrictions. This hook is the defense layer.
#
# TRIGGER: PreToolUse  MATCHER: ""
#
# CONFIGURATION:
#   CC_ALLOWED_BASE_URLS — comma-separated allowlist (default: api.anthropic.com)
#   CC_BASE_URL_ACTION — "warn" or "block" (default: warn)

INPUT=$(cat)

# Default allowlist: only official Anthropic API
ALLOWED="${CC_ALLOWED_BASE_URLS:-https://api.anthropic.com}"
ACTION="${CC_BASE_URL_ACTION:-warn}"

# Get current ANTHROPIC_BASE_URL
CURRENT_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"

# Check if URL is in allowlist
is_allowed() {
  local url="$1"
  IFS=',' read -ra URLS <<< "$ALLOWED"
  for allowed_url in "${URLS[@]}"; do
    # Trim whitespace
    allowed_url=$(echo "$allowed_url" | xargs)
    if [[ "$url" == "$allowed_url"* ]]; then
      return 0
    fi
  done
  return 1
}

# If URL is default/allowed, pass through silently
if is_allowed "$CURRENT_URL"; then
  exit 0
fi

# URL is non-standard — take action
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log the event
LOG_FILE="${CC_BASE_URL_LOG:-/tmp/cc-base-url-violations.log}"
echo "[$TIMESTAMP] ANTHROPIC_BASE_URL=$CURRENT_URL tool=$TOOL action=$ACTION" >> "$LOG_FILE"

if [[ "$ACTION" == "block" ]]; then
  echo '{"decision":"block","reason":"ANTHROPIC_BASE_URL points to non-standard endpoint ('"$CURRENT_URL"'). This may bypass managed hook restrictions. Set CC_ALLOWED_BASE_URLS to allowlist this endpoint."}' >&2
  exit 2
else
  # Warn but allow
  echo "⚠️  WARNING: ANTHROPIC_BASE_URL=$CURRENT_URL (non-standard)" >&2
  echo "   This may bypass allowManagedHooksOnly restrictions (#51123)" >&2
  echo "   Set CC_BASE_URL_ACTION=block to enforce, or CC_ALLOWED_BASE_URLS to allowlist" >&2
  exit 0
fi
