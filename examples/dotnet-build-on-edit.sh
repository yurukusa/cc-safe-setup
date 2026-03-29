#!/bin/bash
# ================================================================
# dotnet-build-on-edit.sh — Run dotnet build after C#/F# edits
#
# Checks compilation after editing .cs or .fs files.
# Warns on build errors but doesn't block.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.cs) || Edit(*.fs) || Write(*.cs) || Write(*.fs)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/dotnet-build-on-edit.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0

# Only check C#/F# files
case "$FILE" in
    *.cs|*.fs) ;;
    *) exit 0 ;;
esac

# Check if dotnet is available and we're in a .NET project
if command -v dotnet &>/dev/null; then
    # Find nearest .csproj or .fsproj
    DIR=$(dirname "$FILE")
    while [[ "$DIR" != "/" ]]; do
        if ls "$DIR"/*.csproj "$DIR"/*.fsproj 2>/dev/null | head -1 | grep -q .; then
            RESULT=$(cd "$DIR" && dotnet build --no-restore -q 2>&1 | tail -5)
            if [[ $? -ne 0 ]]; then
                echo "Build error after editing $(basename "$FILE"):" >&2
                echo "$RESULT" | head -5 >&2
            fi
            break
        fi
        DIR=$(dirname "$DIR")
    done
fi

exit 0
