set -u
INPUT=$(cat)
TOKEN_BUDGET="${CC_CLAUDE_MD_TOKEN_BUDGET:-5000}"
CHARS_PER_TOKEN="${CC_CLAUDE_MD_CHARS_PER_TOKEN:-3.5}"
if [ -n "${CC_CLAUDE_MD_FILES:-}" ]; then
    IFS=':' read -ra MD_FILES <<< "$CC_CLAUDE_MD_FILES"
else
    MD_FILES=(
        "$HOME/.claude/CLAUDE.md"
        ".claude/CLAUDE.md"
        "./CLAUDE.md"
    )
fi
FINDINGS=()
TOTAL_TOKENS=0
for file in "${MD_FILES[@]}"; do
    [ -f "$file" ] || continue
    [ -r "$file" ] || continue
    CHARS=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
    [ -z "$CHARS" ] && continue
    [ "$CHARS" -eq 0 ] && continue
    TOKENS=$(awk -v c="$CHARS" -v cpt="$CHARS_PER_TOKEN" 'BEGIN { printf "%d", c / cpt }')
    FINDINGS+=("$file|$CHARS|$TOKENS")
    TOTAL_TOKENS=$((TOTAL_TOKENS + TOKENS))
done
[ ${#FINDINGS[@]} -eq 0 ] && exit 0
[ "$TOTAL_TOKENS" -le "$TOKEN_BUDGET" ] && exit 0
OVERAGE=$((TOTAL_TOKENS - TOKEN_BUDGET))
MSG="DETECTED: CLAUDE.md token budget exceeded.
Total estimated tokens across all CLAUDE.md files: $TOTAL_TOKENS (budget: $TOKEN_BUDGET, overage: $OVERAGE).
Every Claude Code session loads these files at startup. The cost is paid on every tool call in the session.
Per-file breakdown:"
for finding in "${FINDINGS[@]}"; do
    IFS='|' read -r path chars tokens <<< "$finding"
    MSG="$MSG
  - $path: $chars chars, ~$tokens tokens"
done
MSG="$MSG
Suggested actions:
  1. Read https://github.com/anthropics/claude-code/issues/42796 for the community discussion of CLAUDE.md token costs.
  2. Move project-specific instructions to ./.claude/CLAUDE.md and leave global preferences in ~/.claude/CLAUDE.md.
  3. Convert long examples into separate files referenced by URL rather than inlined.
  4. Increase the budget if intentional: set CC_CLAUDE_MD_TOKEN_BUDGET=$TOTAL_TOKENS to silence this warning.
This hook is advisory only. The session continues normally."
jq -n --arg msg "$MSG" '
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $msg
    }
}'
exit 0
