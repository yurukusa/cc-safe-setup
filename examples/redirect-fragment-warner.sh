#!/bin/bash
# redirect-fragment-warner.sh — Warn / block Bash commands using `2>&1`
# (Cluster 25 candidate, axis 25C — permission-engine `&` fragmentation hang)
#
# Background:
#   A Bash tool command containing `2>&1` triggers a multi-minute spinner
#   hang in the permission-evaluation layer. Token usage increments
#   continuously during the hang — implying a model-reinvocation loop
#   rather than an idle wait. The command itself eventually executes
#   correctly; the hang is purely in the permission step.
#
#   Hypothesised root cause: the permission engine splits Bash commands on
#   shell operators including `&`. The `&` inside `2>&1` fragments the
#   command into segments that are validated independently. That
#   fragmentation drops the command into a re-validation loop where each
#   fragment is re-checked, and the loop re-invokes the model on each
#   iteration — which is the source of the climbing token usage during
#   the visible hang.
#
#   Anchor case:
#     #64334 — Bash command with 2>&1 causes ~12min spinner hang with
#              token usage climbing during the stall
#
#   Cluster 25 sub-axes (4 + 1 overlap):
#     25A — late/empty tool-result delivery (substrate)
#     25B — echo-probe spam compensation (PR #556 shipped)
#     25C — 2>&1 permission-engine fragmentation hang (this hook)
#     25D — compounding cost (downstream of 25B/25C)
#     25E — empty-result triggered fabrication (Cluster 22 overlap)
#
#   This hook is a PreToolUse hook on Bash that:
#     - Matches `2>&1` in the command string (the trigger pattern)
#     - Warns with a rewrite suggestion (default) — `CC_BLOCK_2_REDIRECT=1`
#       to block by default for users who have been bitten once
#     - Allows operator override via `# ACCEPT 2>&1` marker in the command
#
#   The cost-impact justification (12-min hang with token billing climbing)
#   supports defaulting to warn rather than silent allow, and supports the
#   easy-toggle to block-by-default for users who have hit this.
#
# When this hook does NOT warn / block:
#   - CC_REDIRECT_FRAGMENT_DISABLE=1     — never warn or block
#   - CC_REDIRECT_FRAGMENT_QUIET=1       — silent (no stderr output)
#   - The command does not contain `2>&1`
#   - The command contains `# ACCEPT 2>&1` marker (operator override)
#
# When this hook BLOCKS (exit 2):
#   - CC_BLOCK_2_REDIRECT=1 is set
#   - the command contains `2>&1`
#   - the command does not contain the `# ACCEPT 2>&1` override marker
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/redirect-fragment-warner.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_REDIRECT_FRAGMENT_DISABLE=1  — never warn or block
#   CC_REDIRECT_FRAGMENT_QUIET=1    — silent (process but never write stderr)
#   CC_BLOCK_2_REDIRECT=1           — block (exit 2) instead of warn

set -u

if [ "${CC_REDIRECT_FRAGMENT_DISABLE:-}" = "1" ]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || true)
CMD=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi

if [ -z "$CMD" ]; then
    exit 0
fi

# Detect `2>&1` in the command (the trigger pattern)
if ! printf '%s\n' "$CMD" | grep -q '2>&1'; then
    exit 0
fi

# Operator override: `# ACCEPT 2>&1` marker disables the warning for this call
if printf '%s\n' "$CMD" | grep -Eq '#[[:space:]]*ACCEPT[[:space:]]+2>&1'; then
    exit 0
fi

# Build the rewrite suggestion: strip `2>&1` and keep the rest of the command
# (best-effort — the operator should review)
SUGGESTED=$(printf '%s\n' "$CMD" | sed 's/[[:space:]]*2>&1//g')

if [ "${CC_REDIRECT_FRAGMENT_QUIET:-}" = "1" ]; then
    if [ "${CC_BLOCK_2_REDIRECT:-}" = "1" ]; then
        exit 2
    fi
    exit 0
fi

if [ "${CC_BLOCK_2_REDIRECT:-}" = "1" ]; then
    cat >&2 <<EOF

BLOCKED: Bash command contains \`2>&1\`.

Pattern detected: the permission engine splits Bash commands on shell
operators including \`&\`. The \`&\` inside \`2>&1\` fragments the command
into segments that are validated independently, dropping the command
into a re-validation loop where each fragment is re-checked and the
loop re-invokes the model on each iteration. This produces the
multi-minute spinner hang with token usage climbing observed in #64334
(Cluster 25 axis 25C).

What to do instead:
  bad:  ${CMD}
  good: ${SUGGESTED}

If you genuinely need stderr captured, redirect it explicitly to a file
or to a separate stream the model reads separately.

Background: gist.github.com/yurukusa/5881286479969d5bac0323511dc33ab2
Anchor issue: github.com/anthropics/claude-code/issues/64334

To override once: include "# ACCEPT 2>&1" in the command.
To disable: export CC_REDIRECT_FRAGMENT_DISABLE=1
To downgrade to warn-only: unset CC_BLOCK_2_REDIRECT

EOF
    exit 2
fi

cat >&2 <<EOF

NOTICE: Bash command contains \`2>&1\`, which can trigger a multi-minute
permission-engine hang with token billing climbing during the stall
(Cluster 25 axis 25C, anchor #64334).

Suggested rewrite:
  ${SUGGESTED}

To block this pattern by default: export CC_BLOCK_2_REDIRECT=1
To override per-call: include "# ACCEPT 2>&1" in the command.

EOF

exit 0
