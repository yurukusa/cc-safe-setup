#!/bin/bash
# heredoc-backtick-approver.sh — Auto-approve backtick warnings in heredoc strings
#
# Solves: Backticks inside heredoc quoted strings trigger false-positive
#         permission prompt (#35183, 2 reactions).
#         `git commit -m "$(cat <<'EOF' ... \`code\` ... EOF)"` triggers
#         "Command contains backticks for command substitution" even though
#         backticks inside <<'EOF' are inert literal characters.
#
# How it works: PermissionRequest hook that checks if the backtick warning
#   is from a command containing a quoted heredoc (<<'EOF' or <<"EOF").
#   If so, auto-approves since the backticks are string content, not shell.
#
# TRIGGER: PermissionRequest
# MATCHER: "" (all permission requests)

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)
[ -z "$MESSAGE" ] && exit 0

# Only handle backtick/command substitution warnings
echo "$MESSAGE" | grep -qiE "backtick|command substitution" || exit 0

# Get the command that triggered the warning
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check if command contains a quoted heredoc
# <<'EOF' (single-quoted) or <<"EOF" (double-quoted) disable backtick expansion
if echo "$COMMAND" | grep -qE "<<'[A-Za-z_]+'" || echo "$COMMAND" | grep -qE '<<"[A-Za-z_]+"'; then
    # Backticks inside a quoted heredoc are literal — safe to approve
    echo '{"permissionDecision":"allow","permissionDecisionReason":"Backticks are literal characters inside quoted heredoc (<<'"'"'EOF'"'"')"}'
    exit 0
fi

# Also handle unquoted heredoc with git commit pattern
# git commit -m "$(cat <<EOF ... `code` ... EOF)" — common pattern
if echo "$COMMAND" | grep -qE 'git\s+commit.*<<\s*[A-Za-z_]+' && \
   echo "$COMMAND" | grep -qE '`[a-zA-Z_][a-zA-Z0-9_]*`'; then
    # Likely markdown formatting backticks in commit message
    echo '{"permissionDecision":"allow","permissionDecisionReason":"Backticks appear to be markdown formatting in commit message"}'
    exit 0
fi

exit 0
