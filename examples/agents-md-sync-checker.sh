set -u
INPUT=$(cat)
DELTA_PCT="${CC_AGENTS_MD_SIZE_DELTA_PCT:-20}"
if [ -n "${CC_AGENTS_MD_FILES:-}" ]; then
    IFS=':' read -ra AGENTS_MD_FILES <<< "$CC_AGENTS_MD_FILES"
else
    AGENTS_MD_FILES=(
        "./AGENTS.md"
        ".agents/AGENTS.md"
    )
fi
if [ -n "${CC_CLAUDE_MD_FILES_FOR_SYNC:-}" ]; then
    IFS=':' read -ra CLAUDE_MD_FILES <<< "$CC_CLAUDE_MD_FILES_FOR_SYNC"
else
    CLAUDE_MD_FILES=(
        "./CLAUDE.md"
        ".claude/CLAUDE.md"
    )
fi
AGENTS_PATH=""
AGENTS_SIZE=0
for path in "${AGENTS_MD_FILES[@]}"; do
    if [ -f "$path" ] && [ -r "$path" ]; then
        AGENTS_PATH="$path"
        AGENTS_SIZE=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
        break
    fi
done
CLAUDE_PATH=""
CLAUDE_SIZE=0
for path in "${CLAUDE_MD_FILES[@]}"; do
    if [ -f "$path" ] && [ -r "$path" ]; then
        CLAUDE_PATH="$path"
        CLAUDE_SIZE=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
        break
    fi
done
[ -z "$AGENTS_PATH" ] && [ -z "$CLAUDE_PATH" ] && exit 0
[ -z "$AGENTS_PATH" ] && exit 0
FINDINGS=()
if [ -z "$CLAUDE_PATH" ]; then
    FINDINGS+=("AGENTS.md present at $AGENTS_PATH ($AGENTS_SIZE bytes) but no CLAUDE.md found. Claude Code does not read AGENTS.md natively. If you want these instructions in this Claude Code session, copy or symlink AGENTS.md to CLAUDE.md.")
else
    if [ "$AGENTS_PATH" -ef "$CLAUDE_PATH" ]; then
        exit 0
    fi
    if cmp -s "$AGENTS_PATH" "$CLAUDE_PATH" 2>/dev/null; then
        FINDINGS+=("AGENTS.md and CLAUDE.md have identical content but are separate files at $AGENTS_PATH and $CLAUDE_PATH. Consider replacing one with a symlink to the other to prevent future drift.")
    else
        if [ "$AGENTS_SIZE" -eq 0 ] || [ "$CLAUDE_SIZE" -eq 0 ]; then
            PCT_DELTA=100
        else
            if [ "$AGENTS_SIZE" -gt "$CLAUDE_SIZE" ]; then
                PCT_DELTA=$(awk -v a="$AGENTS_SIZE" -v c="$CLAUDE_SIZE" 'BEGIN { printf "%d", (a - c) * 100 / a }')
            else
                PCT_DELTA=$(awk -v a="$AGENTS_SIZE" -v c="$CLAUDE_SIZE" 'BEGIN { printf "%d", (c - a) * 100 / c }')
            fi
        fi
        if [ "$PCT_DELTA" -ge "$DELTA_PCT" ]; then
            FINDINGS+=("AGENTS.md ($AGENTS_PATH: $AGENTS_SIZE bytes) and CLAUDE.md ($CLAUDE_PATH: $CLAUDE_SIZE bytes) differ by $PCT_DELTA% in size. Likely drift between the two instruction sources.")
        else
            FINDINGS+=("AGENTS.md and CLAUDE.md present at $AGENTS_PATH ($AGENTS_SIZE bytes) and $CLAUDE_PATH ($CLAUDE_SIZE bytes), close in size ($PCT_DELTA% delta) but content differs. Confirm intentional divergence or sync.")
        fi
    fi
fi
[ ${#FINDINGS[@]} -eq 0 ] && exit 0
MSG="DETECTED: AGENTS.md / CLAUDE.md state requires operator review.
Multiple coding agents (Codex, Amp, Cursor, Aider, others) are converging on AGENTS.md as a shared instruction standard. Claude Code does not read AGENTS.md natively as of this session — the only operator-side mitigation while issue #6235 (5,196 reactions, 13+ months open) is unresolved is to maintain CLAUDE.md alongside.
Findings:"
for finding in "${FINDINGS[@]}"; do
    MSG="$MSG
  - $finding"
done
MSG="$MSG
Mitigation patterns:
  1. Single source of truth: write instructions in CLAUDE.md, symlink AGENTS.md to it (or vice versa). Other agents read AGENTS.md; Claude Code reads CLAUDE.md; one edit updates both.
  2. Git pre-commit hook that fails when AGENTS.md and CLAUDE.md content drifts.
  3. Pick one tool and remove the other file. Multi-agent workflows are not required.
See https://github.com/anthropics/claude-code/issues/6235 for the upstream feature request thread.
This hook is advisory only. The session continues normally."
jq -n --arg msg "$MSG" '
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $msg
    }
}'
exit 0
