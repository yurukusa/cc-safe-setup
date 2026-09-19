#!/bin/bash
# find-unfirable-rules.sh — list guard rules whose pattern cannot match anything.
#
# Why this exists: find-dead-hooks.sh covers the case where the script is not
# there. This covers the case where the script is there, is registered, runs on
# every call, and its rule still cannot return true. The operator-visible
# symptom is identical to a guard that has simply never seen a dangerous
# command: an `exit 2` rule, an `exit 0` outcome, and no diagnostic anywhere.
#
# Two mechanisms, both measured on shipped guards of mine:
#
#   1. The pattern is eaten as options. grep reads an argument that starts with
#      a dash as flags, so
#          grep -qE '--no-verify|SKIP_CI'
#      dies with "unrecognized option" and matches nothing, for every input,
#      forever. Two of my own guards carried this from 2026-03-29 to
#      2026-09-20 with their tests passing the whole time. Fix: `--` before the
#      pattern, or `-e`.
#
#   2. Lookaround in an engine that has none. ERE has no (?! (?= (?<, so
#          grep -qE '(?!origin\b)'
#      is either a warning and exit 1 (GNU grep) or a syntax error and exit 2
#      (ugrep) — and both look the same to the `if` around it. Fix: grep -P
#      where it is available, or restructure the rule.
#
# It looks at the scripts your settings actually register, and at inline
# command strings, because a rule written directly into settings.json has the
# same failure and no file to inspect.
#
# Usage:  ./find-unfirable-rules.sh          # run from your project directory
#
# Output: one block per suspect rule. No output is good.
#
# What it does NOT tell you: whether a rule that CAN match ever DOES. A pattern
# can be well-formed and still name the wrong thing. Use fire.sh and
# boundary.sh for that. This only rules out the rules that could never have
# worked.
set -u

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
  echo "find-unfirable-rules: needs jq, python3 or node to read settings.json" >&2
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

# A quoted grep pattern whose first character is a dash. The quote may be
# backslash-escaped, because the same commands appear inline inside JSON.
EATEN='grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*\\?['"'"'"]-'
# ... unless -- or -e comes first, which is the correct spelling.
SPELLED_OK='grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(--|-e)[[:space:]]'
# Lookaround, only a problem when the engine is ERE or BRE (no -P).
LOOKAROUND='grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*\\?['"'"'"][^'"'"'"]*\(\?[!=<]'

report() {  # report <where> <line-no-or-dash> <text> <why> <fix>
  echo "UNFIRABLE  $1${2:+:$2}"
  echo "           $3"
  echo "           why: $4"
  echo "           fix: $5"
  echo
}

scan_text() {  # scan_text <where> <text-on-stdin>
  local where="$1" n=0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in \#*) continue ;; esac
    if printf '%s' "$line" | grep -qE -- "$EATEN" \
       && ! printf '%s' "$line" | grep -qE -- "$SPELLED_OK"; then
      report "$where" "$n" "$(printf '%s' "$line" | cut -c1-140)" \
        "the pattern starts with a dash, so grep reads it as options and matches nothing" \
        "put -- before the pattern, or use -e"
    fi
    if printf '%s' "$line" | grep -qE -- "$LOOKAROUND" \
       && ! printf '%s' "$line" | grep -qE -- 'grep[[:space:]]+(-[A-Za-z]*P[A-Za-z]*[[:space:]])'; then
      report "$where" "$n" "$(printf '%s' "$line" | cut -c1-140)" \
        "lookaround ((?! (?= (?<) does not exist in ERE/BRE; this pattern can never match" \
        "use grep -P if available, or restructure the rule"
    fi
  done
}

# 1) the scripts the settings register
for f in "${files[@]}"; do
  extract "$f" | grep -oE '(~|/|\$\{?[A-Za-z_]+\}?/)[^ ";|&)]*\.sh' | sort -u |
  while read -r script; do
    p="${script/#\~/$HOME}"
    p="${p//\$\{CLAUDE_PROJECT_DIR\}/${CLAUDE_PROJECT_DIR:-$PWD}}"
    p="${p//\$CLAUDE_PROJECT_DIR/${CLAUDE_PROJECT_DIR:-$PWD}}"
    p="${p//\$\{HOME\}/$HOME}"
    [ -f "$p" ] || continue
    scan_text "$p" < "$p"
  done
done

# 2) inline command strings, which have no file to open
for f in "${files[@]}"; do
  extract "$f" | while IFS= read -r cmd; do
    case "$cmd" in *grep*) ;; *) continue ;; esac
    printf '%s\n' "$cmd" | scan_text "$f (inline)"
  done
done

echo "---"
echo "Nothing listed above means no rule was found that is structurally unable"
echo "to match. It does NOT mean any rule fires on the thing you care about."
echo "Use fire.sh for that, and boundary.sh for the neighbours it misses."
