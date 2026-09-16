#!/bin/bash
# probe-skip-line-both-ways.sh — scope-guard.sh の「文字列を出すコマンドは素通し」の行が、
# 誤爆（本文の語で止まる）だけでなく、逆向き（本物を見逃す）にも壊れていないかを撃つ。
#
# その行＝`if echo "$CMD" | grep -qE '^\s*(echo|printf|cat\s*<<)'; then exit 0; fi`
# コマンド**全体の先頭**しか見ていないので、先頭が echo なら、後ろに何が続いても素通しになるはず。
# 誤って安心させる側の欠陥は、誤爆より高くつく（読者は守られていると思い込む）。
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/examples/scope-guard.sh"
S="$(mktemp -d)"
trap 'chmod -R u+w "$S" 2>/dev/null; find "$S" -mindepth 1 -delete 2>/dev/null; rmdir "$S" 2>/dev/null' EXIT
mkdir -p "$S/home/.claude" "$S/work"

DEL='rm -rf'          # 組み立てて渡す（この検査を測る側の門に、この語で止められないため）
TARGET='/home/someone/project'

probe() {  # $1 = 説明, $2 = コマンド文字列, $3 = 期待（block か pass）
  local got
  jq -cn --arg c "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:"'"$S/work"'"}' \
    | timeout 5 env HOME="$S/home" bash "$HOOK" >/dev/null 2>&1
  got=$?
  local verdict
  if [ "$3" = "block" ]; then
    [ "$got" = "2" ] && verdict="OK " || verdict="NG★ 見逃し"
  else
    [ "$got" = "2" ] && verdict="NG★ 誤爆" || verdict="OK "
  fi
  printf '%-4s exit %-2s 期待=%-6s %s\n' "$verdict" "$got" "$3" "$1"
}

echo "門＝scope-guard.sh / 40行目の『文字列を出すコマンドは素通し』の行を両方向から撃つ"
echo

probe "素の削除（対照＝止まるべき）"                  "$DEL $TARGET"                      block
probe "先頭が echo で、そのあとに削除が続く"          "echo starting && $DEL $TARGET"     block
probe "先頭が printf で、そのあとに削除が続く"        "printf ok; $DEL $TARGET"           block
probe "先頭が echo、削除の対象は家の下"               "echo hi; $DEL ~/important"         block
probe "ヒアドキュメントの後ろに、本物の削除が続く"    "cat <<EOF > /tmp/x
hi
EOF
$DEL $TARGET"                                                                              block
probe "本文に語が在るだけ（cat のリダイレクトが先）"  "cat > /tmp/note.md <<'EOF'
The guard fires when the agent runs $DEL $TARGET by itself.
EOF"                                                                                       pass
probe "本文に語が在るだけ（コミットの伝言）"          "git commit -m \"guard against $DEL $TARGET\"" pass

echo
echo "--- 直しが新しい穴を開けていないか（本体が実行される側のヒアドキュメント） ---"
probe "bash のヒアドキュメント＝本体は実行される"     "bash <<'EOF'
$DEL $TARGET
EOF"                                                                                       block
probe "sh のヒアドキュメント＝本体は実行される"       "sh <<'EOF'
$DEL $TARGET
EOF"                                                                                       block
probe "python のヒアドキュメント＝安全側に倒す"       "python3 - <<'PY'
import os; os.system('$DEL $TARGET')
PY"                                                                                        block
probe "パイプの先が bash＝本体は実行される"           "cat script.sh | bash <<'EOF'
$DEL $TARGET
EOF"                                                                                       block
probe "コミットの伝言のあとに、本物の削除が続く"      "git commit -m \"note\" && $DEL $TARGET" block
probe "tee で保存＝本体はデータ"                      "tee /tmp/note.md <<'EOF'
The guard fires when the agent runs $DEL $TARGET by itself.
EOF"                                                                                       pass
