#!/bin/bash
# shell-config-truncation-guard.sh — Block writes that would truncate shell config files
#
# Solves: Claude Code installer auto-update truncating ~/.bash_profile and
# ~/.zshrc to 0 bytes, destroying all user shell configuration (#49615).
# Also catches Claude itself attempting to overwrite these files with
# minimal or empty content.
#
# How it works: PreToolUse hook intercepts Write/Bash operations targeting
# shell config files. If the new content would be significantly shorter
# than the existing file (>60% reduction), the operation is blocked.
# Empty/near-empty writes are always blocked.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|Write"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/shell-config-truncation-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Shell config files to protect
PROTECTED_FILES=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.profile"
    "$HOME/.zshenv"
)

check_file_truncation() {
    local target_file="$1"
    local new_size="$2"

    for protected in "${PROTECTED_FILES[@]}"; do
        if [ "$target_file" = "$protected" ] || [ "$(realpath "$target_file" 2>/dev/null)" = "$(realpath "$protected" 2>/dev/null)" ]; then
            if [ ! -f "$protected" ]; then
                return 0
            fi
            local current_size
            current_size=$(wc -c < "$protected" 2>/dev/null || echo 0)

            # Block if writing 0 bytes or near-empty (< 10 bytes)
            if [ "$new_size" -lt 10 ] && [ "$current_size" -gt 50 ]; then
                echo "BLOCKED: Attempted to truncate $protected to $new_size bytes (current: $current_size bytes)" >&2
                echo "This would destroy your shell configuration. See: github.com/anthropics/claude-code/issues/49615" >&2
                exit 2
            fi

            # Block if >60% size reduction
            if [ "$current_size" -gt 100 ]; then
                local threshold=$((current_size * 40 / 100))
                if [ "$new_size" -lt "$threshold" ]; then
                    echo "BLOCKED: Write to $protected would reduce size by >60% ($current_size → $new_size bytes)" >&2
                    echo "If intentional, back up first: cp $protected ${protected}.bak" >&2
                    exit 2
                fi
            fi
            return 0
        fi
    done
    return 0
}

if [ "$TOOL" = "Write" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
    if [ -n "$FILE_PATH" ]; then
        NEW_SIZE=${#CONTENT}
        check_file_truncation "$FILE_PATH" "$NEW_SIZE"
    fi
elif [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$COMMAND" ] && exit 0

    # Detect redirect truncation: > ~/.bashrc, >~/.zshrc, etc.
    for protected in "${PROTECTED_FILES[@]}"; do
        base=$(basename "$protected")
        # Match: > file, >file, truncate file, : > file, echo "" > file
        if echo "$COMMAND" | grep -qE "(^|[;&|])\s*(>|truncate\s+-s\s*0|:\s*>)\s*~?(/[^;]*)?${base}"; then
            echo "BLOCKED: Command would truncate $protected" >&2
            echo "If intentional, back up first: cp $protected ${protected}.bak" >&2
            exit 2
        fi
    done
fi

exit 0
