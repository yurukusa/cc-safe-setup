#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Approve only when EVERY command position qualifies.
#
# The patterns below were anchored at `^\s*` and matched against the whole
# command string, so only the first command position was examined and the
# approval was then handed to the entire line: `docker ps && sudo rm -rf app`
# was approved on the strength of its first word. Measured 2026-08-03 against
# the shipped copy. Same defect as PR #937 (allowlist.sh) and PR #940
# (cd-git-allow.sh), here on the approving side, where the decision is an
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

DOCKER_SAFE_RE='^\s*docker\s+(build|compose|ps|images|logs|inspect|network\s+ls|volume\s+ls|exec|run)'
DOCKER_SAFE_RE="$DOCKER_SAFE_RE"'|^\s*docker-compose\s+(up|down|build|logs|ps|restart)'

cc_every_segment_matches "$DOCKER_SAFE_RE" "$CMD" || exit 0

if echo "$CMD" | grep -qE '^\s*docker\s+(build|compose|ps|images|logs|inspect|network\s+ls|volume\s+ls|exec|run)'; then
    echo '{"decision":"approve"}'
    exit 0
fi
if echo "$CMD" | grep -qE '^\s*docker-compose\s+(up|down|build|logs|ps|restart)'; then
    echo '{"decision":"approve"}'
    exit 0
fi
exit 0
