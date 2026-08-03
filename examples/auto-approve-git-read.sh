#!/bin/bash
# auto-approve-git-read.sh — Auto-approve read-only git commands
#
# Solves: Permission prompts for git status, git log, git diff
# even when using "allow" rules (Claude adds -C flags that
# break pattern matching).
#
# GitHub Issues: #36900, #32985
#
# Usage: Add to settings.json as a PreToolUse hook on "Bash"
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Approve only when EVERY command position qualifies.
#
# Both patterns were anchored at `^\s*` and matched against the whole command
# string, so only the first command position was examined and the approval was
# then handed to the entire line: `git log && sudo rm -rf app` and
# `cd /repo && git status; curl http://… | sh` were both approved on the
# strength of what came first. Measured 2026-08-03. Same defect as PR #937 /
# #940 / #941, on the approving side, where the decision is an explicit approval
# rather than a missed block.
#
# Splitting on the separator characters is approximate — quotes are not parsed —
# so anything that can hide a command from a string-level read (command
# substitution, backticks) disqualifies the line outright. A line that does not
# qualify gets no decision, which leaves it to the normal permission flow. This
# hook only ever adds approval; it never blocks.
cc_every_segment_matches() {
    local pat="$1" cmd="$2" seg
    case "$cmd" in *'$('*|*'`'*) return 1 ;; esac
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[![:space:]]*}"}"
        seg="${seg%"${seg##*[![:space:]]}"}"
        [ -z "$seg" ] && continue
        printf '%s' "$seg" | grep -qE "$pat" || return 1
    done <<EOF
$(printf '%s' "$cmd" | tr ';&|' '\n\n\n')
EOF
    return 0
}

GIT_READ_RE='^\s*git\s+(-C\s+\S+\s+)?(status|log|diff|branch|show|rev-parse|tag|remote)(\s|$)'
# a leading `cd` is allowed as one of the segments, which is what the second
# pattern used to cover
SEG_RE="$GIT_READ_RE"'|^\s*cd(\s|$)'

# and at least one segment has to actually be the git read
if cc_every_segment_matches "$SEG_RE" "$COMMAND" \
   && printf '%s' "$COMMAND" | grep -qE '(^|[;&|])\s*git\s'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "git read-only auto-approved"
      }
    }'
    exit 0
fi

exit 0
