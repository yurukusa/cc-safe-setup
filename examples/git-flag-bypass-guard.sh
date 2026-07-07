#!/bin/bash
# git-flag-bypass-guard.sh
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# WHY: A `deny` rule like `Bash(git commit *)` matches on the command
# string starting with `git commit`. Inserting a flag between `git` and
# the subcommand -- `git -C <path> commit`, `git --no-pager commit`,
# `git -c user.name=foo commit` -- shifts the prefix so the matcher
# misses it and the denied subcommand runs silently. See upstream
# issue #18613 (open at time of writing).
#
# This hook tokenizes the command, skips git's own flags (both the
# value-taking ones like -C/--git-dir and the =-joined / valueless ones),
# resolves the *effective* subcommand, and compares it against a deny
# list. It matches on the subcommand, not on a string prefix, so the
# flag-insertion bypass no longer works.
#
# CONFIG: CC_GIT_FLAG_DENY (comma-separated subcommands, default "commit").
#         Set empty to disable. e.g. CC_GIT_FLAG_DENY="commit,reset,push"
#
# LIMITS: sees a single command line only. Wrapping (bash -c/eval) and
# chaining (&&/;/||) are covered by deny-bypass-detector.sh and
# compound-inject-guard.sh respectively.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# 禁止の一覧は環境変数で指定 (既定値はcommit、空で無効化)
DENY="${CC_GIT_FLAG_DENY-commit}"
[ -z "$DENY" ] && exit 0

# shellcheck disable=SC2206
read -r -a TOKENS <<< "$CMD"
[ "${#TOKENS[@]}" -eq 0 ] && exit 0

# gitの本体を探す (環境変数の前置きや絶対パスにも対応)
git_idx=-1
for i in "${!TOKENS[@]}"; do
    t="${TOKENS[$i]}"
    case "$t" in
        *=*)
            [[ "$t" == -* ]] && break
            continue ;;
        git|*/git)
            git_idx=$i; break ;;
        *)
            break ;;
    esac
done
[ "$git_idx" -lt 0 ] && exit 0

# gitの後ろのフラグを読み飛ばし、実際に効くサブコマンドを取り出す
i=$((git_idx + 1))
SUBCMD=""
while [ "$i" -lt "${#TOKENS[@]}" ]; do
    t="${TOKENS[$i]}"
    case "$t" in
        # 次の単語を値として取るフラグ
        -C|--git-dir|--work-tree|-c|--namespace)
            i=$((i + 2)); continue ;;
        # =つきのフラグ、または値を取らないフラグ
        -*)
            i=$((i + 1)); continue ;;
        *)
            SUBCMD="$t"; break ;;
    esac
done

[ -z "$SUBCMD" ] && exit 0

# 禁止リストと突き合わせる
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
