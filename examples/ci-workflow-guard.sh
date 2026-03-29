#!/bin/bash
# ci-workflow-guard.sh — Prevent dangerous CI/CD workflow modifications
#
# Solves: Claude modifying CI workflows to add `--no-verify`, skip tests,
#         disable security scanning, or add overly broad permissions.
#         A compromised workflow can exfiltrate secrets or deploy malicious code.
#
# How it works: PostToolUse hook on Edit/Write that checks workflow files
#   for dangerous patterns after modification.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in Edit|Write) ;; *) exit 0 ;; esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check CI workflow files
case "$FILE" in
    .github/workflows/*.yml|.github/workflows/*.yaml) ;;
    .gitlab-ci.yml|.circleci/config.yml|Jenkinsfile) ;;
    */.github/workflows/*.yml) ;;
    *) exit 0 ;;
esac

[ -f "$FILE" ] || exit 0

WARNINGS=""

# Check for dangerous patterns
if grep -qE 'permissions:\s*write-all|permissions:\s*\{[^}]*contents:\s*write' "$FILE" 2>/dev/null; then
    WARNINGS="${WARNINGS}  - Broad write permissions detected\n"
fi

if grep -qE '--no-verify|--skip-tests|--no-check|SKIP_CI|skip ci|\[ci skip\]' "$FILE" 2>/dev/null; then
    WARNINGS="${WARNINGS}  - Test/verification skip detected\n"
fi

if grep -qE 'curl.*\|.*sh|wget.*\|.*bash|bash\s*<\(curl' "$FILE" 2>/dev/null; then
    WARNINGS="${WARNINGS}  - Remote script execution (curl|sh) detected\n"
fi

if grep -qE 'dangerously-skip-permissions|--force|--no-verify' "$FILE" 2>/dev/null; then
    WARNINGS="${WARNINGS}  - Safety bypass flags detected\n"
fi

if [ -n "$WARNINGS" ]; then
    echo "WARNING: Potentially dangerous CI workflow changes:" >&2
    echo "  File: $FILE" >&2
    echo -e "$WARNINGS" >&2
    echo "  Review these changes carefully before committing." >&2
fi

exit 0
