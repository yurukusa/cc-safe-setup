#!/bin/bash
# ================================================================
# package-script-guard.sh — Warn when package.json scripts change
# ================================================================
# PURPOSE:
#   package.json scripts are critical infrastructure — they're
#   often wired into CI/CD. Claude sometimes modifies them without
#   understanding the downstream impact. This hook warns on changes.
#
# TRIGGER: PreToolUse  MATCHER: "Edit"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check package.json
case "$FILE" in
    */package.json|package.json) ;;
    *) exit 0 ;;
esac

OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
[ -z "$OLD" ] && exit 0

# Check if scripts section is being modified
if echo "$OLD" | grep -q '"scripts"' || echo "$NEW" | grep -q '"scripts"'; then
    echo "NOTE: Modifying package.json scripts section." >&2
    echo "These are often wired into CI/CD pipelines." >&2
    echo "Verify: npm test, npm run build still work after this change." >&2
fi

# Check if dependencies are being modified
if echo "$OLD" | grep -qE '"(dependencies|devDependencies|peerDependencies)"' || \
   echo "$NEW" | grep -qE '"(dependencies|devDependencies|peerDependencies)"'; then
    echo "NOTE: Modifying package.json dependencies." >&2
    echo "Run npm install after this change." >&2
fi

exit 0
