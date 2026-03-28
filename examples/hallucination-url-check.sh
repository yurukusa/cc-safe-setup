#!/bin/bash
# ================================================================
# hallucination-url-check.sh — Detect potentially hallucinated URLs
# in generated code and documentation
#
# Solves: Claude generating fake URLs, package names, or API
# endpoints that don't exist. Common in documentation, README
# files, and code comments.
#
# Checks URLs in written files against basic validity patterns.
# Warns on suspicious patterns like made-up domains.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/hallucination-url-check.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0

# Only check documentation and config files
case "$FILE" in
    *.md|*.rst|*.txt|*.html|*.json|*.yaml|*.yml) ;;
    *) exit 0 ;;
esac

# Extract URLs from the file
URLS=$(grep -oP 'https?://[^\s\)\]"'\'']+' "$FILE" 2>/dev/null | sort -u | head -10)
[[ -z "$URLS" ]] && exit 0

WARNINGS=""
for URL in $URLS; do
    # Skip known-good domains
    case "$URL" in
        *github.com/*|*npmjs.com/*|*docs.anthropic.com/*|*code.claude.com/*) continue ;;
        *stackoverflow.com/*|*developer.mozilla.org/*|*wikipedia.org/*) continue ;;
        *google.com/*|*example.com/*|*localhost*) continue ;;
    esac

    # Check for suspicious patterns
    # 1. Very long random-looking paths
    if echo "$URL" | grep -qP '/[a-z]{20,}'; then
        WARNINGS="${WARNINGS}  ⚠ Suspicious long path: $URL\n"
    fi
    # 2. Domains with version numbers that look fake
    if echo "$URL" | grep -qP 'v\d+\.\d+\.\d+\.\d+'; then
        WARNINGS="${WARNINGS}  ⚠ Unusual version in URL: $URL\n"
    fi
done

if [[ -n "$WARNINGS" ]]; then
    echo "NOTE: Potentially hallucinated URLs detected in $(basename "$FILE"):" >&2
    echo -e "$WARNINGS" >&2
    echo "Verify these URLs exist before publishing." >&2
fi

exit 0
