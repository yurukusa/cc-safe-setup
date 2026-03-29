MAIN_TREE=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/worktree //')
[ -z "$MAIN_TREE" ] && exit 0
CUR_DIR=$(pwd)
[ "$CUR_DIR" = "$MAIN_TREE" ] && exit 0
to_project_dir() {
    echo "$HOME/.claude/projects/$(echo "$1" | sed 's|/|-|g; s|^-||')"
}
MAIN_PROJECT=$(to_project_dir "$MAIN_TREE")
CUR_PROJECT=$(to_project_dir "$CUR_DIR")
if [ -d "$MAIN_PROJECT" ] && [ ! -L "$CUR_PROJECT" ]; then
    if [ -d "$CUR_PROJECT" ] && [ -z "$(ls -A "$CUR_PROJECT" 2>/dev/null)" ]; then
        rmdir "$CUR_PROJECT"
    fi
    if [ ! -e "$CUR_PROJECT" ]; then
        ln -s "$MAIN_PROJECT" "$CUR_PROJECT"
        echo "Linked worktree project dir → main repo" >&2
    fi
fi
exit 0
