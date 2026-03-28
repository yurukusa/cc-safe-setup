#!/bin/bash
# binary-upload-guard.sh — Block committing binary files to git
#
# Solves: Claude adds binary files (images, compiled binaries, archives)
#         to git, bloating the repository. Once committed, binaries
#         are in git history forever (even if deleted later).
#
# How it works: PreToolUse hook on Bash that checks git add/commit
#   commands for binary file extensions.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git add/commit commands
echo "$COMMAND" | grep -qE 'git\s+(add|commit)' || exit 0

# Binary file extensions to block
BINARY_EXT='\.(exe|dll|so|dylib|bin|obj|o|a|lib|class|jar|war|ear|pyc|pyo|whl|egg|tar|gz|bz2|xz|zip|rar|7z|iso|dmg|pkg|deb|rpm|msi|app|apk|ipa|pdf|doc|docx|xls|xlsx|ppt|pptx|sqlite|db|mdb|wasm)(\s|$|")'

# Check if the command references binary files
if echo "$COMMAND" | grep -qiE "$BINARY_EXT"; then
    MATCHED=$(echo "$COMMAND" | grep -oiE "[^ \"']+${BINARY_EXT}" | head -3)
    echo "⚠ Binary file detected in git command:" >&2
    echo "  $MATCHED" >&2
    echo "  Binary files bloat git history permanently." >&2
    echo "  Consider: .gitignore, git-lfs, or external storage." >&2
    # Warn but don't block (some binaries are intentional)
fi

# Block large archives being added
if echo "$COMMAND" | grep -qE 'git\s+add.*\.(tar\.gz|zip|rar|7z|iso|dmg)\b'; then
    echo "BLOCKED: Large archive file in git add" >&2
    echo "  Archives should not be committed to git." >&2
    echo "  Use .gitignore or external storage." >&2
    exit 2
fi

exit 0
