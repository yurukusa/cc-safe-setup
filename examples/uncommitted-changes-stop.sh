INPUT=$(cat)
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    exit 0
fi
MODIFIED=$(git diff --name-only 2>/dev/null | wc -l)
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
TOTAL=$((MODIFIED + STAGED + UNTRACKED))
if [ "$TOTAL" -gt 0 ]; then
    echo "⚠ WARNING: $TOTAL uncommitted changes:" >&2
    [ "$MODIFIED" -gt 0 ] && echo "  Modified: $MODIFIED files" >&2
    [ "$STAGED" -gt 0 ] && echo "  Staged: $STAGED files" >&2
    [ "$UNTRACKED" -gt 0 ] && echo "  Untracked: $UNTRACKED files" >&2
    echo "  Consider: git add -A && git commit -m 'session checkpoint'" >&2
fi
exit 0
