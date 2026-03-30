#!/bin/bash
# ================================================================
# deployment-verify-guard.sh — Warn if committing without post-deploy verification
# ================================================================
# PURPOSE:
#   Claude Code sometimes reports "deployment successful" without
#   actually verifying the deployment works. This hook tracks deploy
#   commands and checks that functional verification was performed
#   before the next git commit.
#
# How it works:
#   1. When a deploy command is detected, logs timestamp to a marker file
#   2. When verification commands (test, curl, log grep) run, clears the marker
#   3. When git commit is attempted after a deploy without verification,
#      emits a warning (non-blocking, exit 0)
#
# See: https://github.com/anthropics/claude-code/issues/40861
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Configuration:
#   CC_DEPLOY_COMMANDS — regex pattern for deploy commands
#   Default: "systemctl restart|docker restart|docker-compose up|deploy|kubectl apply|terraform apply|heroku push"
#
#   CC_VERIFY_COMMANDS — regex pattern for verification commands
#   Default: "curl|wget|test |pytest|npm test|jest|mocha|rspec|go test|cargo test|make test|grep.*log|tail.*log|journalctl|docker logs|health"
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

MARKER="/tmp/cc-deploy-pending-$$"

# Configurable deploy command patterns
DEPLOY_PATTERN="${CC_DEPLOY_COMMANDS:-systemctl\s+restart|docker\s+restart|docker-compose\s+up|docker\s+compose\s+up|\bdeploy\b|kubectl\s+apply|terraform\s+apply|heroku\s+.*push|fly\s+deploy}"

# Configurable verify command patterns
VERIFY_PATTERN="${CC_VERIFY_COMMANDS:-\bcurl\b|\bwget\b|\btest\s|\bpytest\b|npm\s+test|\bjest\b|\bmocha\b|\brspec\b|go\s+test|cargo\s+test|make\s+test|grep.*log|tail.*log|\bjournalctl\b|docker\s+logs|\bhealth}"

# Skip echo/printf
echo "$COMMAND" | grep -qE '^\s*(echo|printf)\s' && exit 0

# Check if this is a deploy command
if echo "$COMMAND" | grep -qiE "$DEPLOY_PATTERN"; then
    date +%s > "$MARKER"
    echo "Deploy detected. Verification will be required before commit." >&2
    exit 0
fi

# Check if this is a verification command — clear the deploy marker
if echo "$COMMAND" | grep -qiE "$VERIFY_PATTERN"; then
    if [ -f "$MARKER" ]; then
        rm -f "$MARKER"
    fi
    exit 0
fi

# Check if this is a git commit after an unverified deploy
if echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
    if [ -f "$MARKER" ]; then
        DEPLOY_TIME=$(cat "$MARKER" 2>/dev/null || echo "unknown")
        echo "WARNING: Committing after deployment without verification." >&2
        echo "" >&2
        echo "A deploy command was run (at timestamp $DEPLOY_TIME) but no" >&2
        echo "verification command was detected since then." >&2
        echo "" >&2
        echo "Recommended verifications:" >&2
        echo "  curl http://localhost:<port>/health" >&2
        echo "  npm test / pytest / go test" >&2
        echo "  docker logs <container> | tail" >&2
        echo "  journalctl -u <service> --since '5 min ago'" >&2
        echo "" >&2
        echo "See: https://github.com/anthropics/claude-code/issues/40861" >&2
        # Non-blocking — just warn
        rm -f "$MARKER"
    fi
fi

exit 0
