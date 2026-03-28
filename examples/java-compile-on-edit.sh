#!/bin/bash
# ================================================================
# java-compile-on-edit.sh — Check Java compilation after edits
#
# Runs javac syntax check or Maven/Gradle compile after Java file
# edits. Warns on compilation errors but doesn't block.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.java) || Write(*.java)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/java-compile-on-edit.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.java ]] && exit 0

# Try project build tools first
if [[ -f "pom.xml" ]] && command -v mvn &>/dev/null; then
    RESULT=$(mvn compile -q 2>&1 | tail -5)
    [[ $? -ne 0 ]] && echo "Maven compile error after editing $(basename "$FILE"):" >&2 && echo "$RESULT" >&2
elif [[ -f "build.gradle" || -f "build.gradle.kts" ]] && command -v gradle &>/dev/null; then
    RESULT=$(gradle compileJava -q 2>&1 | tail -5)
    [[ $? -ne 0 ]] && echo "Gradle compile error after editing $(basename "$FILE"):" >&2 && echo "$RESULT" >&2
elif command -v javac &>/dev/null && [[ -f "$FILE" ]]; then
    RESULT=$(javac -Xlint:all "$FILE" 2>&1)
    [[ $? -ne 0 ]] && echo "Java compilation error in $(basename "$FILE"):" >&2 && echo "$RESULT" | head -5 >&2
fi

exit 0
