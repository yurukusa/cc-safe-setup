#!/bin/bash
# output-secret-mask.sh — Warn when tool output looks like it contained a secret
#
# Solves: Commands like `env`, `printenv`, `cat .env` expose secrets in tool output.
#         Claude then has secrets in its context window, increasing leak risk.
#
# CORRECTION 2026-08-13 — read this before relying on the name.
#   This file used to claim it "masks secret values" and that "the masked output
#   is what Claude sees in its context". It never did that. `[MASKED]` appeared
#   only in this comment; there is no substitution anywhere in the body, and
#   running it against a real key produces one line on stderr and nothing else.
#   The name promised a control that did not exist, which is worse than no hook:
#   someone reads "output-secret-mask", installs it, and believes secrets are
#   being stripped out of the context window. They are not.
#
#   The premise is also not implementable at this event. PostToolUse fires
#   *after* the tool result exists; it validates output, it does not rewrite what
#   the model already received (see SETTINGS_REFERENCE.md, PostToolUse row).
#   So this hook has been corrected to describe what it does, rather than
#   implementing a promise the event cannot keep.
#
# What it actually does: scans the tool result for secret-shaped strings and
#   writes one warning to stderr. Detection only. The secret is already in the
#   context by the time this runs.
#
# What to use instead, if you need the secret to never reach the context:
#   block the command before it runs (a PreToolUse guard on `env` / `printenv` /
#   `cat .env`), or keep secrets out of files the agent reads at all.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/output-secret-mask.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PostToolUse  MATCHER: "Bash"

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)

[ -z "$OUTPUT" ] && exit 0

# Check if output contains secret-like patterns
NEEDS_MASK=false

# AWS keys
echo "$OUTPUT" | grep -qE 'AKIA[0-9A-Z]{16}' && NEEDS_MASK=true
# GitHub tokens
echo "$OUTPUT" | grep -qE '(ghp_|gho_|ghs_|ghr_)[A-Za-z0-9_]{20,}' && NEEDS_MASK=true
# OpenAI/Anthropic keys.
# The prefix has to START a token. Without the left boundary this also fired on
# ordinary English words that end in "sk" before a separator — task-, ask-,
# risk-, disk-, desk- — so any path built from one of those, followed by twenty
# more word characters, was reported as a leaked key. The same defect was fixed
# in write-secret-guard.sh on 2026-08-13. A warning that cries on ordinary
# output is a warning people learn to ignore, so precision matters here as much
# as coverage.
echo "$OUTPUT" | grep -qE '(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}' && NEEDS_MASK=true
# Slack tokens
echo "$OUTPUT" | grep -qE '(xoxb-|xoxp-)[0-9A-Za-z-]{20,}' && NEEDS_MASK=true
# Generic secrets in env output (KEY=value pattern with high-entropy value)
echo "$OUTPUT" | grep -qiE '(API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|AUTH)=[^\s]{8,}' && NEEDS_MASK=true

if [ "$NEEDS_MASK" = true ]; then
    echo "WARNING: Tool output may contain secrets. Consider using environment variables instead of printing them." >&2
fi

exit 0
