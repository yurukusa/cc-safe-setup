#!/bin/bash
# measure-literal-match-misfire.sh — 配っているフックのうち、何本が「コマンドの中身」ではなく
# 「コマンド文字列に含まれる語」で判定していて、本文の中の語だけで誤爆するかを実測する。
#
# なぜ必要か（2026-09-16 に自分で踏んだ）:
#   販売文の下書きに "deleted project files with rm -rf" という一文を書いてヒアドキュメントで
#   保存しようとしたら、PreToolUse のフックが exit 2 で止めた。削除は1件もしていない。
#   フックが見ていたのはコマンドの意味ではなく、コマンド文字列そのものだった。
#
# 数え方（先に決める。後から境界を動かさない）:
#   母数 = examples/*.sh のうち (1) tool_input.command を読む かつ (2) exit 2 を含む もの。
#          この2つを満たさないフックは、そもそも Bash のコマンドを見て止める役ではない。
#   危険側 (A) = 本当にその操作をするコマンド。止まるのが正しい。
#   本文側 (B) = 同じ語が「ヒアドキュメントの中身」にあるだけで、その操作はしないコマンド。
#                止まらないのが正しい。
#   無害側 (C) = B とまったく同じ形で、危険な語だけを無害な語に置き換えたもの。
#                ★これが無いと「B が止まった理由」が分からない。許可リスト方式のフックは
#                  先頭の cat が許可されていないだけで止まるので、語とは無関係に B を止める。
#                  C でも止まるなら、それは語の誤爆ではなく「その形を丸ごと止めている」。
#   判定 = A で止まり、B で止まり、C で止まらない → ★語による誤爆（本文の語だけが原因）
#          A で止まり、B で止まらない                → 正しく切り分けている
#          B も C も止まる                           → 語とは無関係にその形を止めている
#          A で止まらない                            → この入力の担当ではない
#
# 安全（フックを本当に実行するので、副作用を隔離する）:
#   - HOME と cwd を使い捨ての一時ディレクトリへ差し替える（フックの書き込み先は $HOME 配下が大半）
#   - cwd は git リポジトリにしない（git を叩くフックが実在のツリーへ触らないように）
#   - 破壊的な操作を自分で実行するフックは、走らせる前に名前で除外する
#     （2026-09-14 に test.sh の中の本物の git stash で作業ツリーを持って行かれた実績がある）
#   - 各フックは timeout で切る
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLES="$REPO/examples"
SANDBOX="$(mktemp -d)"
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; find "$SANDBOX" -mindepth 1 -delete 2>/dev/null; rmdir "$SANDBOX" 2>/dev/null' EXIT

mkdir -p "$SANDBOX/home/.claude" "$SANDBOX/work"

# 撃つ語の組。危険側と本文側で、含まれる語は同一にする（そこが対照の肝）。
DANGER_CMD='rm -rf /tmp/some-scratch-dir'
BODY_CMD="cat > /tmp/note.md <<'EOF'
The guard fires when Claude Code runs rm -rf /tmp/some-scratch-dir by itself.
EOF"
# C＝Bと1語だけ違う。危険な語を無害な語へ置き換えてある（他は同一）
HARMLESS_CMD="cat > /tmp/note.md <<'EOF'
The guard fires when Claude Code runs ls -la /tmp/some-scratch-dir by itself.
EOF"

payload() {  # $1 = コマンド文字列
  jq -cn --arg c "$1" \
    '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}, cwd:"'"$SANDBOX/work"'"}'
}

run_hook() {  # $1 = フックのパス, $2 = 入力のJSON。返すのは終了コード
  printf '%s' "$2" | timeout 5 env HOME="$SANDBOX/home" \
    bash "$1" >/dev/null 2>&1
  echo $?
}

# 破壊的な操作を自分で実行するフックは走らせない（測る価値より事故の危険が大きい）
DESTRUCTIVE_RE='git[[:space:]]+stash[[:space:]]+push|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-|shutdown|reboot|pkill|killall'

total=0; skipped=0; misfire=0; correct=0; notmine=0; shapeblock=0
: > "$SANDBOX/misfire.txt"
: > "$SANDBOX/correct.txt"
: > "$SANDBOX/shape.txt"

A_JSON="$(payload "$DANGER_CMD")"
B_JSON="$(payload "$BODY_CMD")"
C_JSON="$(payload "$HARMLESS_CMD")"

for f in "$EXAMPLES"/*.sh; do
  grep -q 'tool_input\.command' "$f" || continue
  grep -qE '(^|[^0-9])exit[[:space:]]+2' "$f" || continue
  total=$((total+1))
  if grep -qE "$DESTRUCTIVE_RE" "$f"; then
    skipped=$((skipped+1)); continue
  fi
  a=$(run_hook "$f" "$A_JSON")
  b=$(run_hook "$f" "$B_JSON")
  c=$(run_hook "$f" "$C_JSON")
  name="$(basename "$f")"
  if [ "$a" != "2" ]; then
    notmine=$((notmine+1))
  elif [ "$b" != "2" ]; then
    correct=$((correct+1)); echo "$name" >> "$SANDBOX/correct.txt"
  elif [ "$c" = "2" ]; then
    # B も C も止まる＝語ではなく、その形（cat のヒアドキュメント）を丸ごと止めている
    shapeblock=$((shapeblock+1)); echo "$name" >> "$SANDBOX/shape.txt"
  else
    misfire=$((misfire+1)); echo "$name" >> "$SANDBOX/misfire.txt"
  fi
done

echo "母数（コマンドを読み、exit 2 を持つフック）: $total"
echo "  走らせずに外した（破壊的な操作を自分でする）: $skipped"
echo "  この入力の担当ではない（危険側でも止めない）: $notmine"
echo "  ★正しい（危険側で止まり、本文側では止まらない）: $correct"
echo "  ★語による誤爆（本文の語だけが原因。無害側では止まらない）: $misfire"
echo "  その形を丸ごと止めている（語とは無関係。許可リスト方式など）: $shapeblock"
echo
echo "--- 語による誤爆 ---"
cat "$SANDBOX/misfire.txt"
echo
echo "--- 正しく切り分けたフック ---"
cat "$SANDBOX/correct.txt"
echo
echo "--- 形を丸ごと止めているフック（語とは無関係） ---"
cat "$SANDBOX/shape.txt"
