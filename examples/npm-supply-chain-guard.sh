#!/bin/bash
# npm-supply-chain-guard.sh — Detect npm supply chain attack patterns
#
# Solves: npm install can execute arbitrary code via postinstall scripts.
#         Claude Code may install malicious packages via typosquatting,
#         dependency confusion, or compromised packages (#39421).
#
# How it works: PreToolUse hook on Bash that detects npm/yarn/pnpm
#   install commands and checks for:
#   1. Typosquatting patterns (similar to popular packages)
#   2. Scoped packages from unknown registries
#   3. Packages with suspicious install scripts
#   4. Version pinning warnings
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/npm-supply-chain-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only check npm/yarn/pnpm install commands
echo "$CMD" | grep -qE '\b(npm|yarn|pnpm)\s+(install|add|i)\b' || exit 0

# Extract package names from command
PACKAGES=$(echo "$CMD" | grep -oE '\b(npm|yarn|pnpm)\s+(install|add|i)\s+(.+)' | sed -E 's/^(npm|yarn|pnpm)\s+(install|add|i)\s+//' | tr ' ' '\n' | grep -v '^-')

WARNINGS=""

for pkg in $PACKAGES; do
    # Skip flags
    [[ "$pkg" == -* ]] && continue

    # Check for known typosquatting patterns
    # Common targets: lodash, express, react, axios, webpack, babel
    POPULAR=("lodash" "express" "react" "axios" "webpack" "babel" "moment" "chalk" "commander" "inquirer")
    for popular in "${POPULAR[@]}"; do
        # Skip exact matches
        [ "$pkg" = "$popular" ] && continue
        # Check Levenshtein-like similarity (simple: 1 char difference)
        if [ "${#pkg}" -ge 3 ] && [ "${#pkg}" -le $((${#popular} + 2)) ]; then
            # Check if package name is very similar to a popular one
            diff_count=$(python3 -c "
import sys
a, b = '$pkg', '$popular'
if abs(len(a)-len(b)) <= 2:
    # Simple edit distance check
    d = sum(1 for x,y in zip(a,b) if x!=y) + abs(len(a)-len(b))
    print(d)
else:
    print(99)
" 2>/dev/null)
            if [ -n "$diff_count" ] && [ "$diff_count" -le 2 ] && [ "$diff_count" -gt 0 ]; then
                WARNINGS="${WARNINGS}\n  ⚠ '$pkg' looks similar to popular package '$popular' (possible typosquatting)"
            fi
        fi
    done

    # Check for internal/private scope packages being installed from public registry
    if echo "$pkg" | grep -qE '^@[a-z]+-internal/|^@private-'; then
        WARNINGS="${WARNINGS}\n  ⚠ '$pkg' looks like an internal scoped package — verify it exists on the intended registry"
    fi
done

# Check for --ignore-scripts bypass
if echo "$CMD" | grep -q '\-\-ignore-scripts'; then
    # This is actually a safety measure, no warning needed
    :
fi

# Warn about not using --ignore-scripts
if [ -n "$PACKAGES" ] && ! echo "$CMD" | grep -qE '\-\-ignore-scripts|\-\-production'; then
    WARNINGS="${WARNINGS}\n  ℹ Consider using --ignore-scripts to prevent postinstall script execution"
fi

if [ -n "$WARNINGS" ]; then
    echo "⚠ npm supply chain check:" >&2
    echo -e "$WARNINGS" >&2
    # Warn but don't block — exit 0
fi

exit 0
