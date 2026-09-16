#!/bin/bash
# probe-scope-guard-branches.sh — scope-guard.sh が持つ4つの止める分岐すべてを撃って、
# 2026-09-16 の書き直しで退行していないことを確かめる。
#
# probe-skip-line-both-ways.sh は「本文と本物の切り分け」を見る検査で、
# 親ディレクトリへの脱出と、よく知られた利用者ディレクトリの2分岐を撃っていない。
# 片方だけ直した状態を見逃す型（memory: fixed-one-rule-left-the-twin）を避けるために分ける。
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/examples/scope-guard.sh"
S="$(mktemp -d)"
trap 'chmod -R u+w "$S" 2>/dev/null; find "$S" -mindepth 1 -delete 2>/dev/null; rmdir "$S" 2>/dev/null' EXIT
mkdir -p "$S/home/.claude" "$S/work"

DEL='rm -rf'
ng=0
probe() {
    local got
    jq -cn --arg c "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:"'"$S/work"'"}' \
        | timeout 5 env HOME="$S/home" bash "$HOOK" >/dev/null 2>&1
    got=$?
    local verdict
    if [ "$3" = "block" ]; then
        [ "$got" = "2" ] && verdict="OK " || { verdict="NG★"; ng=$((ng+1)); }
    else
        [ "$got" = "2" ] && { verdict="NG★"; ng=$((ng+1)); } || verdict="OK "
    fi
    printf '%-4s exit %-2s 期待=%-6s %s\n' "$verdict" "$got" "$3" "$1"
}

echo "門＝scope-guard.sh / 4つの分岐すべてを撃つ"
echo
probe "分岐1 絶対パス"                       "$DEL /var/tmp/thing"                    block
probe "分岐2 家の下"                         "$DEL ~/Projects/thing"                  block
probe "分岐3 親への脱出"                     "$DEL ../sibling/thing"                  block
probe "分岐4 Desktop"                        "$DEL Desktop/notes"                     block
probe "分岐4 .ssh"                           "$DEL .ssh/known_hosts"                  block
probe "分岐4 大文字小文字ちがい"             "$DEL desktop/notes"                     block
echo
echo "--- 止めてはいけない側（この門の役目は、プロジェクトの外を守ること） ---"
probe "プロジェクトの中の相対パス"           "$DEL ./build"                           pass
probe "本文に分岐4の語が在るだけ"            "cat > /tmp/n.md <<'EOF'
Never let the agent run $DEL Desktop by itself.
EOF"                                                                                  pass
probe "伝言に分岐4の語が在るだけ"            "git commit -m \"guard $DEL .ssh\""       pass
echo
echo "不合格 $ng 件"
exit $([ "$ng" -gt 0 ] && echo 1 || echo 0)
