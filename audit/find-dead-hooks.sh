#!/bin/bash
# find-dead-hooks.sh — list hook registrations whose script is not on disk.
#
# Why this exists: Claude Code treats a hook that fails to launch as a
# non-blocking error and lets the tool call proceed. A registration pointing at
# a path that does not exist therefore produces no symptom at all — the guard
# is simply absent, and everything looks normal.
#
# It reads all three settings files, because a registration can rot in any of
# them and each is merged into the others.
#
# Usage:  ./find-dead-hooks.sh            # run from your project directory
#
# Output: one line per registration whose script is missing. No output is good.
set -u

# The same file can appear twice — when HOME is the project directory, or when
# one path is a symlink to the other. Reporting a registration twice makes it
# look like two separate problems, so collapse the list by resolved path first.
raw=(
  "$HOME/.claude/settings.json"
  "$PWD/.claude/settings.json"
  "$PWD/.claude/settings.local.json"
)
files=()
seen=""
for f in "${raw[@]}"; do
  [ -f "$f" ] || continue
  real=$(readlink -f "$f" 2>/dev/null || printf '%s' "$f")
  case ":$seen:" in *":$real:"*) continue ;; esac
  seen="$seen:$real"
  files+=("$f")
done

reader=""
for r in jq python3 python node; do command -v "$r" >/dev/null 2>&1 && { reader="$r"; break; }; done
if [ -z "$reader" ]; then
  echo "find-dead-hooks: needs jq, python3 or node to read settings.json" >&2
  exit 70
fi

extract() {   # print every command string registered under any hook event
  case "$reader" in
    jq) jq -r '.hooks // {} | .[]?[]?.hooks[]?.command // empty' "$1" 2>/dev/null ;;
    *)  "$reader" - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
for groups in (data.get("hooks") or {}).values():
    for group in groups or []:
        for hook in (group or {}).get("hooks") or []:
            cmd = hook.get("command")
            if cmd:
                print(cmd)
PY
    ;;
  esac
}

found=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  extract "$f" | grep -oE '(~|/|\$\{?[A-Za-z_]+\}?/)[^ ";|&)]*\.(sh|py|js|mjs)' | sort -u |
  while read -r script; do
    p="${script/#\~/$HOME}"
    p="${p//\$\{CLAUDE_PROJECT_DIR\}/${CLAUDE_PROJECT_DIR:-$PWD}}"
    p="${p//\$CLAUDE_PROJECT_DIR/${CLAUDE_PROJECT_DIR:-$PWD}}"
    p="${p//\$\{HOME\}/$HOME}"
    if [ ! -e "$p" ]; then
      echo "MISSING  $p"
      echo "         registered in $f"
      found=1
    fi
  done
done

# The subshell above cannot set `found` in the parent, so report on emptiness instead.
echo "---"
echo "Nothing listed above means every registered hook script exists."
echo "It does NOT mean any of them fires. Use fire.sh for that."
