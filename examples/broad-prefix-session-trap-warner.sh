#!/bin/bash
# ================================================================
# broad-prefix-session-trap-warner.sh — Cluster 6 Axis 8
# Warn before a broad static `ask` rule is session-approved
# ================================================================
# PURPOSE:
#   Cluster 6 Axis 8 (surfaced 2026-05-26 via #62437).
#
#   When a static ask rule like `Bash(docker --host:*)` exists in
#   settings.json and the operator selects "Approve always for
#   this session" on the first matching command, the matching
#   engine caches the approval. Subsequent commands that match the
#   SAME pattern then bypass the PreToolUse hook chain entirely —
#   the hook's `permissionDecision: deny` output is never reached.
#
#   The trap is broad-prefix session approval. A single approval
#   of `docker --host=unix:///var/run/docker.sock ps` silently
#   whitelists `docker --host=unix:///var/run/docker.sock rm -f *`
#   for the rest of the session, even though a PreToolUse hook is
#   actively trying to deny destructive `docker rm` commands.
#
#   This hook fires on every PreToolUse for matching commands so
#   that the first session-level approval is at least visible:
#   the operator sees the trap articulated before they click
#   "Always" and inadvertently shadow their own deny logic.
#
# DETECTION:
#   PreToolUse on Bash. For each Bash command, check if it matches
#   any configured broad-prefix pattern. A broad prefix is one
#   where the same root command can introduce both safe and
#   destructive subcommands (docker, gcloud, aws, kubectl, helm,
#   terraform, rm -rf, dd, mkfs). If matched, advise the operator
#   to use "Approve once" rather than "Approve always for this
#   session".
#
# OUTPUT:
#   stderr advisory naming the matched prefix and the deny-bypass
#   trap, plus a JSON additionalContext block summarising the same
#   for the model. Exit 0 always (advisory, not blocking) so the
#   permission gate still owns the actual decision.
#
# CONFIGURATION:
#   CC_BROAD_PREFIX_PATTERNS — colon-separated grep -E patterns
#                              matched against the Bash command.
#                              Default covers common broad-prefix
#                              admin tools.
#   CC_BROAD_PREFIX_DISABLE  — set to 1 to suppress entirely
#                              (operator already aware of trap).
#   CC_BROAD_PREFIX_SILENT   — set to 1 to skip JSON output but
#                              still emit stderr advisory.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/62437
#   https://github.com/anthropics/claude-code/issues/30519 (meta)
#   https://github.com/anthropics/claude-code/issues/39523 (meta)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
# ================================================================

set -u

INPUT=$(cat 2>/dev/null || echo "{}")

[ "${CC_BROAD_PREFIX_DISABLE:-0}" = "1" ] && exit 0

# Default broad prefixes. The principle: the same root command can
# introduce a safe read-only invocation OR a destructive one, so
# session-wide approval of the prefix is the trap.
DEFAULT_PATTERNS='docker( |$):gcloud( |$):aws( |$):kubectl( |$):helm( |$):terraform( |$):rm +-[rRf]:dd( |$):mkfs'
PATTERNS="${CC_BROAD_PREFIX_PATTERNS:-$DEFAULT_PATTERNS}"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

MATCHED_PATTERN=""
IFS=':' read -ra PATTERN_ARR <<< "$PATTERNS"
for pat in "${PATTERN_ARR[@]}"; do
    [ -z "$pat" ] && continue
    if printf '%s' "$COMMAND" | grep -qE "$pat"; then
        MATCHED_PATTERN="$pat"
        break
    fi
done

[ -z "$MATCHED_PATTERN" ] && exit 0

MSG="broad-prefix command detected: '$MATCHED_PATTERN' matches this command. Cluster 6 Axis 8 trap (#62437): if you select 'Approve always for this session' on the upcoming prompt, the matching engine caches the approval for the prefix — and subsequent commands matching the same prefix will bypass the PreToolUse hook chain entirely (your hook's permissionDecision: deny will never fire).

Recommendation: select 'Approve once' for this invocation. Reserve 'Always' for narrow, fully-qualified commands (not broad prefixes like '$MATCHED_PATTERN').

Trap mechanics: a session approval of 'docker ps' silently whitelists 'docker rm -f *' for the rest of the session even if a PreToolUse hook is actively denying destructive docker subcommands. Related: meta-issue #30519, bypass-mode meta #39523."

echo "[broad-prefix-session-trap-warner] $MSG" >&2

if [ "${CC_BROAD_PREFIX_SILENT:-0}" != "1" ]; then
    jq -n --arg msg "$MSG" '
    {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": $msg
        }
    }' 2>/dev/null || true
fi

exit 0
