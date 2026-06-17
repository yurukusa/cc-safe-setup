INPUT=$(cat)
TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[[ -z "$TARGET" ]] && exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[[ -z "$CWD" ]] && CWD="$PWD"
case "$CWD" in
    *"/.claude/worktrees/"*) ;;
    *) exit 0 ;;
esac
PARENT="${CWD%%/.claude/worktrees/*}"
REST="${CWD#*/.claude/worktrees/}"          # <name>/maybe/more
WTNAME="${REST%%/*}"                          # <name>
WT="$PARENT/.claude/worktrees/$WTNAME"
case "$TARGET" in
    /*) ABS="$TARGET" ;;
    *)  ABS="$CWD/$TARGET" ;;
esac
case "$ABS" in
    "$WT"/*|"$WT")
        exit 0 ;;                              # correctly inside the worktree — OK
    "$PARENT"/*|"$PARENT")
        echo "BLOCKED: write target is in the PARENT repo, not the active worktree." >&2
        echo "  cwd (worktree): $CWD" >&2
        echo "  target:         $ABS" >&2
        echo "  Expected under: $WT/" >&2
        echo "  This is the silent nested-worktree parent-write (#62547/#60679/#69026)." >&2
        echo "  Fix: write under the worktree path, or create worktrees OUTSIDE the repo." >&2
        exit 2 ;;
esac
exit 0
