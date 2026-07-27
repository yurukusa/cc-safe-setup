#!/bin/bash
# verify-after-publish-reminder.sh — Remind to verify persisted state after publish commands
#
# Solves: "Silent failure" where a publish command reports success but the
#         content is not actually visible at the destination. Examples observed:
#         - Zenn GitHub sync rate-limited the article but `git push` reported success
#         - Tweet auto-tool reported failure while the tweet was actually live in broken form
#         - Gumroad CDP form-input updated the DOM value but React state was untouched,
#           so Save click serialized the old state
#
# How it works: After the user runs a Bash command that looks like a publish action,
#   the hook reads the candidate URL from stdout (if visible) and reminds the user to
#   verify the persisted state through a second channel (re-fetch the public URL, hit
#   the article API, or inspect the dashboard). The hook does NOT block — it emits a
#   reminder so the user catches silent-success failures before logging completion.
#
# Detected publish patterns:
#   - git push (anywhere)
#   - hashnode-publish, qiita-post, zenn-update, hatena-post, tweet-post
#   - npm publish, cargo publish, pip publish, gh release create
#   - cdp-bridge eval ... Save changes
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
#
# CONFIG:
#   CC_PUBLISH_VERIFY_DISABLE=1   # Disable the reminder entirely
#
# This is defense-in-depth, not a complete safeguard. The reminder text is logged to
# the agent's transcript so the agent sees it on the next turn and is prompted to run
# the verification before claiming success.

set -euo pipefail

[ "${CC_PUBLISH_VERIFY_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Patterns that indicate a publish-like action
PUBLISH_PATTERNS='git[[:space:]]+push|hashnode-publish|qiita-post|zenn-update|hatena-post|tweet-post|note-publish|note-update|npm[[:space:]]+publish|cargo[[:space:]]+publish|pip[[:space:]]+publish|twine[[:space:]]+upload|gh[[:space:]]+release[[:space:]]+create|cdp-bridge[[:space:]].*[Ss]ave[[:space:]]+changes'

if ! printf '%s\n' "$COMMAND" | grep -qE "$PUBLISH_PATTERNS"; then
    exit 0
fi

# Identify which platform was published to (best effort)
PLATFORM="unknown"
case "$COMMAND" in
    *hashnode-publish*) PLATFORM="Hashnode" ;;
    *qiita-post*) PLATFORM="Qiita" ;;
    *zenn-update*|*zenn-cc-book*) PLATFORM="Zenn" ;;
    *hatena-post*) PLATFORM="hatena" ;;
    *tweet-post*) PLATFORM="X (Twitter)" ;;
    *note-publish*|*note-update*) PLATFORM="note" ;;
    *npm*publish*) PLATFORM="npm" ;;
    *cargo*publish*) PLATFORM="crates.io" ;;
    *pip*publish*|*twine*upload*|*twine[[:space:]]upload*) PLATFORM="PyPI" ;;
    *gh*release*create*) PLATFORM="GitHub Release" ;;
    *git*push*) PLATFORM="git remote (may trigger downstream publish via GitHub sync)" ;;
    *Save*changes*) PLATFORM="dashboard (Gumroad / Ko-fi / other SaaS)" ;;
esac

cat >&2 <<EOF
=== verify-after-publish-reminder ===
A publish-like action was just executed against: ${PLATFORM}

The tool's "success" response is not the same as "the content is live and correct".

Before logging this as completed, verify the persisted state through a second channel:

  1. Re-fetch the public URL or page and confirm HTTP 200 + correct content
  2. Query the platform's API (article API, product API, etc.) for the new state
  3. Inspect the platform dashboard for any rate-limit, deployment-failure, or "blocked"
     notification

Common silent-failure modes to check:
  - Rate-limit rejection (Zenn 24h window, Twitter 4-8h cadence, API throttle 429)
  - React-controlled input that did not update internal state (DOM looked right,
    Save serialized old data)
  - GitHub sync queued but not yet deployed
  - Cloudflare / anti-bot intercept that hid content from non-logged-in viewers

If verification fails, treat the publish as NOT done and re-attempt — do not log success
based on the local command return value alone.

(Set CC_PUBLISH_VERIFY_DISABLE=1 to suppress this reminder.)
EOF

# Non-blocking reminder (exit 0). The text appears in the transcript and reminds the
# agent on the next turn.
exit 0
