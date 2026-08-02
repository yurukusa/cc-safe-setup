#!/bin/bash
# protect-dotfiles.sh — Block destructive operations on home directory config files
#
# Solves: Claude Code overwriting .bashrc, deleting .aws/, running
# chezmoi/stow without diffing first (#37478, #33391)
#
# Covers: Edit/Write to dotfiles, Bash commands that modify them
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/protect-dotfiles.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-protect-dotfiles-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [protect-dotfiles]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# === Check 1: Edit/Write to dotfiles ===
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
    HOME_DIR=$(eval echo "~")
    PROTECTED_DOTFILES=(
        ".bashrc" ".bash_profile" ".bash_logout"
        ".zshrc" ".zprofile" ".zshenv"
        ".profile" ".login"
        ".gitconfig" ".gitignore_global"
        ".ssh/config" ".ssh/authorized_keys"
        ".aws/config" ".aws/credentials"
        ".npmrc" ".yarnrc"
        ".env" ".env.local" ".env.production"
    )
    for dotfile in "${PROTECTED_DOTFILES[@]}"; do
        if [[ "$FILE" == "${HOME_DIR}/${dotfile}" ]]; then
            echo "BLOCKED: Cannot modify ~/${dotfile}" >&2
            echo "This is a critical config file. Edit it manually." >&2
            exit 2
        fi
    done
    # Block writing to any ~/.ssh/ or ~/.aws/ or project .kiro/ files
    if [[ "$FILE" == "${HOME_DIR}/.ssh/"* || "$FILE" == "${HOME_DIR}/.aws/"* ]]; then
        echo "BLOCKED: Cannot modify files in ${FILE%/*}/" >&2
        exit 2
    fi
    # Protect .kiro/ directory (#40139 — Claude runtime silently deletes .kiro/)
    if [[ "$FILE" == *"/.kiro/"* ]]; then
        echo "BLOCKED: Cannot modify .kiro/ directory" >&2
        exit 2
    fi
fi

# === Check 2: Bash commands that modify dotfiles ===
if [[ "$TOOL" == "Bash" && -n "$CMD" ]]; then
    # Skip echo/printf (string output, not actual modification)
    if echo "$CMD" | grep -qE '^\s*(echo|printf|cat\s*<<)'; then
        exit 0
    fi

    # Block chezmoi/stow apply without --dry-run
    if echo "$CMD" | grep -qE '(chezmoi\s+(init|apply|update)|stow\s)' && \
       ! echo "$CMD" | grep -qE '(--dry-run|--diff|-n\b|diff)'; then
        echo "BLOCKED: Run 'chezmoi diff' or '--dry-run' first" >&2
        echo "Command: $CMD" >&2
        exit 2
    fi

    # Block rm on dotfile directories
    if echo "$CMD" | grep -qE 'rm\s.*\.(ssh|aws|gnupg|config|local)'; then
        echo "BLOCKED: Cannot delete dotfile directory" >&2
        exit 2
    fi

    # Block cp/mv overwriting dotfiles without backup
    if echo "$CMD" | grep -qE '(cp|mv)\s.*\.(bashrc|zshrc|profile|gitconfig)' && \
       ! echo "$CMD" | grep -qE '(--backup|-b)'; then
        echo "BLOCKED: Use --backup flag when overwriting dotfiles" >&2
        exit 2
    fi
fi

exit 0
