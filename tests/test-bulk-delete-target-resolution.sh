#!/bin/bash
# bulk-file-delete-guard.sh の両方向の退行検査。
# 直したのは「対象を数えられない時に通していた」分岐。誤爆を増やしていないかを見る。
G="$(cd "$(dirname "$0")/.." && pwd)/examples/bulk-file-delete-guard.sh"
SB="$(mktemp -d)/regprobe"

rm -rf "$SB" 2>/dev/null
mkdir -p "$SB/many" "$SB/few" "$SB/dir with space"
for i in $(seq 1 25); do : > "$SB/many/f$i.txt"; done
for i in 1 2; do : > "$SB/few/f$i.txt"; done
for i in $(seq 1 25); do : > "$SB/dir with space/f$i.txt"; done

pass=0; fail=0
check() { # 期待 コマンド 説明
  local want="$1" C="$2" L="$3"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$C" | jq -Rs .)" \
    | timeout 15 bash "$G" >/dev/null 2>&1
  local rc=$?; local got="通す"; [ $rc -eq 2 ] && got="止める"
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf 'OK   %-6s %s\n' "$got" "$L"
  else fail=$((fail+1)); printf 'NG★  期待=%-6s 実際=%-6s %s\n' "$want" "$got" "$L"; fi
}

echo "=== 止めるべき（25個を消す・書き方を変えただけ） ==="
check 止める "rm -rf $SB/many"                     "素の絶対パス"
check 止める "rm -rf \"$SB/many\""                 "引用符（二重）"
check 止める "rm -rf '$SB/many'"                   "引用符（単一）"
check 止める "rm -rf $SB/many/"                    "末尾スラッシュ"
check 止める "rm -rf $SB/many/*"                   "グロブで中身"
check 止める "rm -rf $SB/ma*"                      "部分グロブ"
check 止める "cd $SB && rm -rf many"               "cd してから相対"
check 止める "cd \"$SB\" && rm -rf many"           "cd の引数も引用符"
check 止める "find $SB/many -delete"               "find -delete"
check 止める "find \"$SB/many\" -type f -exec rm {} +" "find -exec rm（引用符）"
check 止める "rm -rf \"$SB/dir with space\""       "パスに空白（引用符が必須の形）"

echo
echo "=== 通すべき（消す数が少ない・対象が無い・別のコマンド） ==="
check 通す   "rm -rf $SB/few"                      "閾値未満（2個）"
check 通す   "rm -rf \"$SB/few\""                  "閾値未満・引用符"
check 通す   "rm -rf /tmp/does-not-exist-$$"       "存在しないパス（警告のみ）"
check 通す   "rm -f $SB/few/f1.txt"                "-r が無い（対象外）"
check 通す   "ls -la $SB/many"                     "削除ではない"
check 通す   "echo 'rm -rf /' > notes.md"          "文章に書いただけ"
check 通す   "git status"                          "無関係"

echo
echo "合格 $pass / 不合格 $fail"
rm -rf "$SB"
[ $fail -eq 0 ] || exit 1
