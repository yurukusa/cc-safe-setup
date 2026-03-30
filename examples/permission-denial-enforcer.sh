#!/bin/bash
# permission-denial-enforcer.sh — Block alternative write methods after permission denial
#
# Solves: After user denies Write permission, Claude circumvents by using
# Bash commands (pip install --target, path traversal to /tmp, etc.) to
# achieve the same write operation (#41103)
#
# How it works: Tracks when Write/Edit permissions are denied (via a
# temp file marker). When active, blocks Bash commands that perform
# write-equivalent operations: package installs, file creation via
# scripts, redirects to paths outside the project.
#
# The marker auto-expires after 5 minutes to avoid permanent lockout.
#
# Usage: Add TWO hooks — one PostToolUse to detect denials, one PreToolUse to enforce
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/permission-denial-enforcer.sh" }]
#     }],
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/permission-denial-enforcer.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PostToolUse+PreToolUse  MATCHER: "Write|Edit|Bash"

MARKER="/tmp/.cc-write-denied-$$"
MARKER_GLOB="/tmp/.cc-write-denied-*"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# --- PostToolUse path: detect Write/Edit denial ---
if [[ "$TOOL" == "Write" || "$TOOL" == "Edit" ]]; then
    # Check if the tool result indicates denial/block
    RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
    if echo "$RESULT" | grep -qiE 'denied|rejected|blocked|permission.*denied|user.*denied'; then
        # Create denial marker with timestamp
        echo "$(date +%s)" > "$MARKER"
        echo "Write permission denial detected. Write-equivalent Bash commands will be blocked for 5 minutes." >&2
    fi
    exit 0
fi

# --- PreToolUse path: enforce on Bash ---
[[ "$TOOL" != "Bash" ]] && exit 0

# Check if any denial marker exists and is recent (< 5 min)
ACTIVE=0
for f in $MARKER_GLOB; do
    [[ -f "$f" ]] || continue
    CREATED=$(cat "$f" 2>/dev/null)
    NOW=$(date +%s)
    AGE=$(( NOW - CREATED ))
    if [[ "$AGE" -lt 300 ]]; then
        ACTIVE=1
        break
    else
        rm -f "$f" 2>/dev/null
    fi
done

[[ "$ACTIVE" -eq 0 ]] && exit 0

# Denial is active — check for write-equivalent commands
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Block package installs (common bypass vector)
if echo "$CMD" | grep -qiE 'pip3?\s+install|npm\s+install|gem\s+install|cargo\s+install|go\s+install'; then
    echo "BLOCKED: Package install blocked — you denied Write permission earlier. Ask the user before retrying." >&2
    exit 2
fi

# Block file creation via Python/Node scripts
if echo "$CMD" | grep -qiE 'python3?\s+.*\.(py|sh)|node\s+.*\.js' && echo "$CMD" | grep -qiE 'create|write|save|output|generate'; then
    echo "BLOCKED: Script execution that creates files blocked — Write permission was denied." >&2
    exit 2
fi

# Block redirect/tee to outside project
if echo "$CMD" | grep -qiE '>\s*/tmp|>\s*/private|tee\s+/tmp|tee\s+/private|--target='; then
    echo "BLOCKED: Writing to /tmp or external paths blocked — Write permission was denied." >&2
    exit 2
fi

exit 0
