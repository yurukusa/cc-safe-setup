#!/bin/bash
# auto-approve-gradle.sh — Auto-approve Gradle build/test commands
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
# Approve only when EVERY command position qualifies.
#
# The pattern below was anchored at `^\s*` and matched against the whole command
# string, so only the first command position was examined and the approval was
# then handed to the entire line: `gradle build && sudo rm -rf app` was approved
# on the strength of its first word. Measured 2026-08-03. Same defect as
# PR #937 / #940 / #941, on the approving side, where the decision is an
# explicit approval rather than a missed block.
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

if cc_every_segment_matches '^\s*(gradle|gradlew|./gradlew)\s+(build|test|check|assemble|clean|compileJava|compileKotlin|lint)(\s|$)' "$COMMAND"; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"gradle command auto-approved"}}'
fi
exit 0
