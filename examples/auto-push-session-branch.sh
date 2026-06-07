set -uo pipefail
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
[ -z "$branch" ] && exit 0          # detached HEAD: do nothing
case "$branch" in
  main|master|develop|release) exit 0 ;;
esac
push() { if "$@"; then return 0; else
  echo "[auto-push] '$branch' not pushed (no remote / auth / rejected). Push manually." >&2
  exit 0; fi; }
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  [ "$ahead" -eq 0 ] && exit 0      # nothing unpushed
  push git push --quiet
  echo "[auto-push] pushed $ahead commit(s) on '$branch'." >&2
else
  git rev-parse --verify --quiet HEAD >/dev/null 2>&1 || exit 0
  push git push --quiet -u origin "$branch"
  echo "[auto-push] set upstream and pushed '$branch' to origin." >&2
fi
exit 0
