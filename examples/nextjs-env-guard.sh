#!/bin/bash
# ================================================================
# nextjs-env-guard.sh — Prevent exposing server secrets in Next.js
# client code
#
# Solves: Claude accidentally using server-only env vars in client
# components. In Next.js, only NEXT_PUBLIC_* vars are available
# client-side. Using process.env.SECRET_KEY in a client component
# fails silently (undefined) or leaks to the browser bundle.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.tsx) || Edit(*.jsx) || Write(*.tsx) || Write(*.jsx)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/nextjs-env-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0

# Only check in Next.js projects
[[ ! -f "next.config.js" ]] && [[ ! -f "next.config.mjs" ]] && [[ ! -f "next.config.ts" ]] && exit 0

# Check if file is a client component
IS_CLIENT=0
if head -5 "$FILE" | grep -q "'use client'\|\"use client\""; then
    IS_CLIENT=1
fi

# Also check common client paths
if echo "$FILE" | grep -qE '(app|pages)/.*\.(tsx|jsx)$' && [[ "$IS_CLIENT" -eq 0 ]]; then
    # Could be either - skip unless explicitly client
    exit 0
fi

if [[ "$IS_CLIENT" -eq 1 ]]; then
    # Find process.env references that aren't NEXT_PUBLIC_
    LEAKS=$(grep -n 'process\.env\.' "$FILE" | grep -v 'NEXT_PUBLIC_' | head -5)
    if [[ -n "$LEAKS" ]]; then
        echo "WARNING: Server env vars used in client component." >&2
        echo "File: $(basename "$FILE")" >&2
        echo "$LEAKS" >&2
        echo "" >&2
        echo "Only NEXT_PUBLIC_* vars are available client-side." >&2
        echo "Server secrets will be undefined or leak to the bundle." >&2
    fi
fi

exit 0
