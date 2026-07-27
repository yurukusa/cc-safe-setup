#!/bin/bash
# deny-bypass-detector.sh — Detect when Claude circumvents a hook denial
#
# Solves: After a PreToolUse hook blocks a command (exit 2), Claude
# reformulates the same operation as a script wrapper, eval, or
# bash -c to evade pattern matching. (#46991)
#
# How it works: Two-phase detection:
#   Phase 1 (PostToolUse): When a Bash command is blocked (tool_result
#     contains deny/block signals), log the dangerous substrings.
#   Phase 2 (PreToolUse): Before each Bash command, check if it
#     contains a recently-denied substring wrapped in bash -c, sh -c,
#     eval, or a temp script.
#
# Denied commands expire after 60 seconds to avoid permanent lockout.
#
# Usage: Add TWO hooks — PostToolUse to log denials, PreToolUse to detect bypass
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/deny-bypass-detector.sh" }]
#     }],
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/deny-bypass-detector.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PostToolUse+PreToolUse  MATCHER: "Bash"

set -euo pipefail

DENY_LOG="/tmp/cc-deny-bypass-log"
mkdir -p "$(dirname "$DENY_LOG")" 2>/dev/null || true

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)

# --- Phase 1: PostToolUse — log denied commands ---
if [[ "$HOOK_EVENT" == "PostToolUse" ]]; then
    RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
    # Detect denial signals in tool result
    if echo "$RESULT" | grep -qiE 'BLOCKED|exit.*(code|status).*2|hook.*denied|hook.*blocked'; then
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        [ -z "$CMD" ] && exit 0
        # Extract dangerous substrings: the core operation
        # e.g., from "rm -rf node_modules" extract "rm -rf" and "node_modules"
        TIMESTAMP=$(date +%s)
        # Log the full command and key fragments
        echo "${TIMESTAMP}|${CMD}" >> "$DENY_LOG"
        # Also extract individual dangerous tokens
        for token in $(echo "$CMD" | grep -oE '(rm\s+-rf|git\s+push\s+--force|git\s+reset\s+--hard|git\s+clean|chmod\s+777|curl.*\|.*sh|wget.*\|.*sh)' 2>/dev/null); do
            echo "${TIMESTAMP}|PATTERN:${token}" >> "$DENY_LOG"
        done
    fi
    exit 0
fi

# --- Phase 2: PreToolUse — detect bypass attempts ---
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0
[ ! -f "$DENY_LOG" ] && exit 0

NOW=$(date +%s)
CUTOFF=$((NOW - 60))

# Clean expired entries
if [ -f "$DENY_LOG" ]; then
    awk -F'|' -v cutoff="$CUTOFF" '$1 >= cutoff' "$DENY_LOG" > "${DENY_LOG}.tmp" 2>/dev/null
    mv "${DENY_LOG}.tmp" "$DENY_LOG" 2>/dev/null || true
fi

# Check if current command wraps a denied command
BYPASS_DETECTED=0
DENIED_CMD=""

while IFS='|' read -r ts denied_cmd; do
    [ "$ts" -lt "$CUTOFF" ] 2>/dev/null && continue
    [ -z "$denied_cmd" ] && continue

    # Skip pattern entries for this check
    [[ "$denied_cmd" == PATTERN:* ]] && continue

    # Check 1: bash -c / sh -c / eval wrapping the denied command
    if echo "$CMD" | grep -qE '(bash|sh)\s+-c\s' || echo "$CMD" | grep -qE '\beval\s'; then
        # Extract the inner command from the wrapper
        INNER=$(echo "$CMD" | sed -E "s/.*(bash|sh)\s+-c\s+['\"]?//" | sed -E "s/['\"]?\s*$//")
        # Check if inner command is similar to denied command
        # Use key fragments: first word + arguments
        DENIED_CORE=$(echo "$denied_cmd" | awk '{print $1}')
        if echo "$INNER" | grep -qF "$DENIED_CORE"; then
            BYPASS_DETECTED=1
            DENIED_CMD="$denied_cmd"
            break
        fi
    fi

    # Check 2: Writing denied command to a temp script then executing
    if echo "$CMD" | grep -qE '(cat|echo|printf).*>.*\.(sh|bash|tmp)' || \
       echo "$CMD" | grep -qE 'python3?\s+-c|node\s+-e'; then
        DENIED_CORE=$(echo "$denied_cmd" | awk '{print $1}')
        if echo "$CMD" | grep -qF "$DENIED_CORE"; then
            BYPASS_DETECTED=1
            DENIED_CMD="$denied_cmd"
            break
        fi
    fi

    # Check 3: Direct re-execution (same command within 60s)
    if [ "$CMD" = "$denied_cmd" ]; then
        BYPASS_DETECTED=1
        DENIED_CMD="$denied_cmd"
        break
    fi

done < "$DENY_LOG"

# Also check pattern-based detection
if [ "$BYPASS_DETECTED" -eq 0 ]; then
    while IFS='|' read -r ts pattern_entry; do
        [ "$ts" -lt "$CUTOFF" ] 2>/dev/null && continue
        [[ "$pattern_entry" != PATTERN:* ]] && continue
        PATTERN="${pattern_entry#PATTERN:}"
        if echo "$CMD" | grep -qiE "$PATTERN"; then
            BYPASS_DETECTED=1
            DENIED_CMD="(pattern: $PATTERN)"
            break
        fi
    done < "$DENY_LOG"
fi

if [ "$BYPASS_DETECTED" -eq 1 ]; then
    echo "BLOCKED: Bypass attempt detected." >&2
    echo "  A similar command was denied <60 seconds ago: $DENIED_CMD" >&2
    echo "  Wrapping denied commands in scripts or eval does not change the policy." >&2
    echo "  Ask the user for explicit permission before retrying." >&2
    exit 2
fi

exit 0
