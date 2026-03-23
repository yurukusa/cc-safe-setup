#!/bin/bash
# ================================================================
# commit-quality-gate.sh — Enforce commit message quality
# ================================================================
# PURPOSE:
#   Claude Code generates commit messages that are often too long,
#   too vague ("update code"), or contain the full diff summary.
#   This hook enforces minimum quality standards.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# CHECKS:
#   1. Subject line length (max 72 chars, warn at 50)
#   2. No vague subjects ("update", "fix", "changes", "misc")
#   3. No mega-commits (subject line shouldn't list 5+ changes)
#   4. Body line length (max 72 chars per line)
#   5. No empty subject line
#
# CONFIGURATION:
#   CC_COMMIT_MAX_SUBJECT=72
#   CC_COMMIT_WARN_SUBJECT=50
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
    exit 0
fi

# Skip --amend (modifying existing) and --allow-empty
if echo "$COMMAND" | grep -qE '\-\-amend|\-\-allow-empty'; then
    exit 0
fi

# Extract commit message
MSG=""
if echo "$COMMAND" | grep -qE '\-m\s'; then
    # -m "message" or -m 'message'
    MSG=$(echo "$COMMAND" | grep -oP "\-m\s+['\"]?\K[^'\"]+(?=['\"]?)" | head -1)
fi

if [[ -z "$MSG" ]]; then
    exit 0  # No inline message (might use editor)
fi

MAX_SUBJECT="${CC_COMMIT_MAX_SUBJECT:-72}"
WARN_SUBJECT="${CC_COMMIT_WARN_SUBJECT:-50}"

# Get subject line (first line before any newline)
SUBJECT=$(echo "$MSG" | head -1)
SUBJECT_LEN=${#SUBJECT}

# Check 1: Empty subject
if [[ -z "$SUBJECT" ]] || [[ "$SUBJECT_LEN" -lt 3 ]]; then
    echo "WARNING: Commit subject is empty or too short." >&2
    exit 0  # Warn only
fi

# Check 2: Subject too long
if [[ "$SUBJECT_LEN" -gt "$MAX_SUBJECT" ]]; then
    echo "WARNING: Commit subject is $SUBJECT_LEN chars (max $MAX_SUBJECT)." >&2
    echo "Subject: $(echo "$SUBJECT" | head -c 80)..." >&2
    echo "Tip: Keep the subject under $MAX_SUBJECT chars. Use the body for details." >&2
fi

# Check 3: Vague subjects
SUBJECT_LOWER=$(echo "$SUBJECT" | tr '[:upper:]' '[:lower:]')
VAGUE_PATTERNS="^(update|fix|change|misc|wip|tmp|test|stuff|things|minor|cleanup)$|^(update|fix|change)\s+(code|file|stuff|things)$"
if echo "$SUBJECT_LOWER" | grep -qiE "$VAGUE_PATTERNS"; then
    echo "WARNING: Commit subject is too vague: \"$SUBJECT\"" >&2
    echo "Be specific about what changed and why." >&2
fi

# Check 4: Mega-commit (too many changes listed)
COMMA_COUNT=$(echo "$SUBJECT" | grep -o ',' | wc -l)
AND_COUNT=$(echo "$SUBJECT_LOWER" | grep -o ' and ' | wc -l)
if [[ $((COMMA_COUNT + AND_COUNT)) -ge 4 ]]; then
    echo "WARNING: Commit subject lists many changes. Consider splitting into smaller commits." >&2
    echo "Subject: $(echo "$SUBJECT" | head -c 80)" >&2
fi

exit 0
