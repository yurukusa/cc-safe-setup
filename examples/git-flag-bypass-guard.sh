#!/bin/bash
# git-flag-bypass-guard.sh — Enforce deny rules for git subcommands regardless of flag placement
#
# Solves: `Bash(git commit *)` deny rules prefix-match the raw command
#   string. `git -C /path commit` or `git --git-dir=.git commit` reads
#   as `git -C` or `git --git-dir=...` to the matcher and the deny never
#   fires.
#
# Related: GitHub #59006, #18613 (canonical), #25270, #52409
#
# How it works: After "git" in the command, walk past option tokens
#   (and their values where applicable) until the first positional
#   token. That token is the effective subcommand. If it matches a
#   configured deny list, block with exit 2.
#
# Configure denied subcommands via CC_GIT_FLAG_DENY (comma-separated).
# Default: "commit". Set to empty string to disable.
#
# Limitations: single-command only. Does not catch `bash -c "..."`,
# `sh -c '...'`, `eval`, or `&&`/`;`-chained forms. Combine with
# deny-bypass-detector.sh and compound-inject-guard.sh for those.
#
# Hooks config:
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Bash",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/git-flag-bypass-guard.sh" }]
#       }]
#     }
#   }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

DENY="${CC_GIT_FLAG_DENY-commit}"
[ -z "$DENY" ] && exit 0

# shellcheck disable=SC2206
read -r -a TOKENS <<< "$CMD"
[ "${#TOKENS[@]}" -eq 0 ] && exit 0

# Find "git" in the token stream, allowing leading env-var assignments
# like `GIT_AUTHOR_NAME=x git commit` and absolute paths like `/usr/bin/git`.
git_idx=-1
for i in "${!TOKENS[@]}"; do
    t="${TOKENS[$i]}"
    case "$t" in
        *=*)
            # env-var assignment (no leading dash), skip and keep looking
            [[ "$t" == -* ]] && break
            continue ;;
        git|*/git)
            git_idx=$i; break ;;
        *)
            break ;;
    esac
done
[ "$git_idx" -lt 0 ] && exit 0

# Walk past option tokens after "git" to find the effective subcommand
i=$((git_idx + 1))
SUBCMD=""
while [ "$i" -lt "${#TOKENS[@]}" ]; do
    t="${TOKENS[$i]}"
    case "$t" in
        -C|--git-dir|--work-tree|-c|--namespace)
            i=$((i + 2)); continue ;;
        -*)
            i=$((i + 1)); continue ;;
        *)
            SUBCMD="$t"; break ;;
    esac
done

[ -z "$SUBCMD" ] && exit 0

IFS=',' read -r -a DENY_LIST <<< "$DENY"
for denied in "${DENY_LIST[@]}"; do
    [ -z "$denied" ] && continue
    if [ "$SUBCMD" = "$denied" ]; then
        echo "BLOCKED: git deny rule for '$denied' (form: $CMD)" >&2
        echo "  Reason: prefix matcher misses 'git $denied' when prefixed with flags like -C, --git-dir, -c, --no-pager." >&2
        echo "  See #18613 for the broader fix." >&2
        exit 2
    fi
done

exit 0
