#!/bin/bash
# ================================================================
# subagent-blast-radius-guard.sh — Surface and gate the files a
#   sub-agent actually writes, at the moment it writes them
# ================================================================
# PURPOSE:
#   Existing sub-agent hooks in this repo (subagent-scope-validator,
#   subagent-tool-allowlist-enforcer, subagent-boundary-precheck,
#   subagent-destructive-git-guard, ...) all fire on the PARENT's
#   PreToolUse for the Agent/Task tool. They inspect the delegation
#   PROMPT and nudge the operator to state boundaries before the
#   sub-agent starts. None of them see what the sub-agent then
#   actually does. Once the sub-agent is running, its individual
#   Write/Edit calls are unguarded at the execution layer.
#
#   This hook closes that gap. It fires on the sub-agent's own
#   Write/Edit calls and keys off the `agent_id` / `agent_type`
#   fields that Claude Code adds to the PreToolUse payload for
#   sub-agent-originated tool calls (verified on v2.1.161: a
#   sub-agent's Write call carries agent_id+agent_type; the main
#   thread's calls do not). When agent_id is present, the write
#   came from a sub-agent, and this hook can surface it or block it
#   — without ever touching the human-supervised main agent's writes.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"
#
# WHY THIS MATTERS:
#   #65152 (2026-06-03) — a sub-agent asked only to "run these two
#   shell commands" autonomously used Write/Edit on 15 files,
#   including production database migration files, and the operator
#   only discovered the blast radius after the fact. The same shape
#   recurs in #63356 and #45108: a narrowly-scoped delegation turns
#   into a wide, partly-irreversible set of writes, and there is no
#   per-write signal the operator sees in time to intervene.
#
#   The fix the parent-side nudge hooks cannot provide is a signal
#   (or a stop) at the instant the sub-agent writes a high-blast
#   file. That is what this hook adds.
#
# WHAT IT DOES:
#   * Main-thread writes (no agent_id): exit 0 immediately. This hook
#     deliberately never interferes with the supervised main agent.
#   * Sub-agent writes (agent_id present): apply CC_SUBAGENT_WRITE_GUARD:
#       off       — do nothing (exit 0).
#       warn      — (default) warn on a "flagged" write (sensitive
#                   path, or outside the allowlist when one is set);
#                   silent on ordinary writes. Always exit 0.
#       warn-all  — warn on EVERY sub-agent write (full blast-radius
#                   visibility). Always exit 0.
#       block     — exit 2 (block) on a flagged write; ordinary
#                   sub-agent writes pass silently.
#
#   A write is "flagged" when it matches the high-blast sensitive
#   pattern (migrations, IaC state, .env / secrets, prod config, DB
#   schema, lockfiles, CI workflows) OR — if CC_SUBAGENT_WRITE_ALLOW
#   is set — when it falls outside every allowed path prefix.
#
# CONFIG:
#   CC_SUBAGENT_WRITE_GUARD     off | warn (default) | warn-all | block
#   CC_SUBAGENT_WRITE_ALLOW     space/colon-separated path prefixes the
#                               sub-agent may write under (e.g.
#                               "src/feature-x/ docs/"). Writes outside
#                               all prefixes are flagged. Match is a
#                               literal prefix on the file_path Claude
#                               passes (usually an absolute cwd path).
#   CC_SUBAGENT_WRITE_SENSITIVE extra ERE appended (alternation) to the
#                               built-in sensitive pattern.
#
# DESIGN NOTES (why these defaults):
#   * Default is warn, not block: blocking a sub-agent mid-run can
#     wedge legitimate fan-out work and break headless/CI. Visibility
#     of the dangerous writes is the safe default; blocking is opt-in,
#     matching memory-write-guard's opt-in philosophy.
#   * Fail-open on malformed input / missing jq: a safety hook must
#     never be the thing that breaks the session.
#   * Edit|Write only (not Bash): destructive Bash by anyone is already
#     covered by rm-safety-net / destructive-guard / git guards
#     regardless of agent_id. The genuinely uncovered gap is the
#     sub-agent's structured file writes.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/65152
#   https://github.com/anthropics/claude-code/issues/63356
#   https://github.com/anthropics/claude-code/issues/45108
# ================================================================

set -u

INPUT=$(cat)

MODE="${CC_SUBAGENT_WRITE_GUARD:-warn}"
[ "$MODE" = "off" ] && exit 0

# agent_id is present only for sub-agent-originated tool calls. No
# agent_id => main-thread write => never our concern.
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$AGENT_ID" ] && exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="subagent"

# High-blast / hard-to-reverse destinations a narrowly-scoped sub-agent
# should not be silently rewriting.
SENSITIVE_ERE='(^|/)migrations?/|(^|/)migrate/|\.tf$|\.tfstate|(^|/)terraform/|(^|/)\.env|secrets?\.(ya?ml|json|env)|(^|/)credentials|(^|/)(prod|production)\.(ya?ml|yml|json|env|toml)|(^|/)config/(prod|production)|schema\.(sql|prisma|rb)$|(^|/)db/schema|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|poetry\.lock|Gemfile\.lock)$|(^|/)\.github/workflows/|(^|/)\.gitlab-ci\.yml$'
if [ -n "${CC_SUBAGENT_WRITE_SENSITIVE:-}" ]; then
    SENSITIVE_ERE="${SENSITIVE_ERE}|${CC_SUBAGENT_WRITE_SENSITIVE}"
fi

is_sensitive=0
if printf '%s' "$FILE" | grep -qE "$SENSITIVE_ERE"; then
    is_sensitive=1
fi

# Allowlist: if set, a write outside every prefix is out-of-scope.
out_of_scope=0
REASON=""
if [ -n "${CC_SUBAGENT_WRITE_ALLOW:-}" ]; then
    out_of_scope=1
    # Split on whitespace and colons.
    OLD_IFS="$IFS"; IFS=': '
    for prefix in $CC_SUBAGENT_WRITE_ALLOW; do
        [ -z "$prefix" ] && continue
        case "$FILE" in
            "$prefix"*) out_of_scope=0 ;;
        esac
    done
    IFS="$OLD_IFS"
fi

flagged=0
if [ "$is_sensitive" -eq 1 ]; then
    flagged=1
    REASON="high-blast path (migration / IaC / secret / prod config / schema / lockfile / CI)"
fi
if [ "$out_of_scope" -eq 1 ]; then
    flagged=1
    if [ -n "$REASON" ]; then
        REASON="$REASON; outside CC_SUBAGENT_WRITE_ALLOW"
    else
        REASON="outside CC_SUBAGENT_WRITE_ALLOW ($CC_SUBAGENT_WRITE_ALLOW)"
    fi
fi

SHORT_ID=$(printf '%s' "$AGENT_ID" | cut -c1-8)

emit_warn() {
    echo "subagent-blast-radius-guard: sub-agent [$AGENT_TYPE#$SHORT_ID] is writing $FILE${1:+ — $1}" >&2
}

case "$MODE" in
    warn-all)
        if [ "$flagged" -eq 1 ]; then emit_warn "$REASON"; else emit_warn ""; fi
        exit 0
        ;;
    block)
        if [ "$flagged" -eq 1 ]; then
            echo "BLOCKED: sub-agent [$AGENT_TYPE#$SHORT_ID] attempted to write $FILE" >&2
            echo "Reason: $REASON." >&2
            echo "A narrowly-delegated sub-agent should not write this. Re-delegate with an explicit scope, write it from the supervised main thread, or set CC_SUBAGENT_WRITE_GUARD=warn to allow with a warning." >&2
            exit 2
        fi
        exit 0
        ;;
    *)  # warn (default)
        [ "$flagged" -eq 1 ] && emit_warn "$REASON"
        exit 0
        ;;
esac
