#!/bin/bash
# measure-heredoc-shapes.sh — 「本文の中に危険な語を書くだけ」の同じ意図を、何通りの綴りで書けるか。
# そのうち何通りが門に止められるかを実測する。
#
# 見つかっていること（2026-09-16）:
#   scope-guard.sh は本文を素通しする行を持っている（40行目 `^\s*(echo|printf|cat\s*<<)`）。
#   つまり作者は本文の除外を意図していた。だが `cat > file <<'EOF'` の形は
#   `cat` の直後が `>` なので `cat\s*<<` に当たらず、素通しの対象から外れる。
#   ★同じことをする綴りが何通りあって、どれが当たり どれが外れるかを表にする。
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; find "$SANDBOX" -mindepth 1 -delete 2>/dev/null; rmdir "$SANDBOX" 2>/dev/null' EXIT
mkdir -p "$SANDBOX/home/.claude" "$SANDBOX/work"

HOOK="${1:-$REPO/examples/scope-guard.sh}"
BODY='The guard fires when Claude Code runs rm -rf /home/someone/project by itself.'
SAFE='The guard fires when Claude Code runs ls -la /home/someone/project by itself.'

shapes() {  # $1 = 本文
  local b="$1"
  printf '%s\n' \
    "cat > /tmp/note.md <<'EOF'|$b|EOF" \
    "cat <<'EOF' > /tmp/note.md|$b|EOF" \
    "cat <<'EOF'|$b|EOF" \
    "tee /tmp/note.md <<'EOF'|$b|EOF" \
    "python3 - <<'PY'|print(\"$b\")|PY" \
    "echo \"$b\" > /tmp/note.md||" \
    "printf '%s' \"$b\" > /tmp/note.md||" \
    "git commit -m \"$b\"||"
}

run() {  # $1 = コマンド文字列
  jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:"'"$SANDBOX/work"'"}' \
    | timeout 5 env HOME="$SANDBOX/home" bash "$HOOK" >/dev/null 2>&1
  echo $?
}

echo "門＝$(basename "$HOOK")"
echo
printf '%-42s %-10s %-10s %s\n' "綴り（本文に語を書くだけ・削除はしない）" "危険な語" "無害な語" "判定"
printf '%s\n' "--------------------------------------------------------------------------------"
mis=0; ok=0; shape=0
while IFS= read -r line; do
  IFS='|' read -r head body tail <<< "$line"
  cmd="$head"
  [ -n "$body" ] && cmd="$cmd
$body"
  [ -n "$tail" ] && cmd="$cmd
$tail"
  b=$(run "$cmd")
  # 同じ綴りで、語だけ無害に差し替えたもの
  safe_cmd="${cmd//rm -rf/ls -la}"
  c=$(run "$safe_cmd")
  if [ "$b" = "2" ] && [ "$c" != "2" ]; then verdict="★語で誤爆"; mis=$((mis+1))
  elif [ "$b" = "2" ] && [ "$c" = "2" ]; then verdict="形ごと停止"; shape=$((shape+1))
  else verdict="素通し"; ok=$((ok+1)); fi
  printf '%-42s %-10s %-10s %s\n' "$(printf '%s' "$head" | cut -c1-40)" "exit $b" "exit $c" "$verdict"
done < <(shapes "$BODY")
echo
echo "★語で誤爆 $mis 通り / 形ごと停止 $shape 通り / 素通し $ok 通り（全 8 通り）"
echo
echo "★この表の「誤爆」は機械の判定で、設計の意図とは別物。"
echo "  2026-09-16 の直しのあとに1通りだけ残る python3 - <<'PY' は、意図して止めている:"
echo "  ヒアドキュメントの本体が実行される受け手（bash/sh と、shell を呼びうるインタプリタ）は"
echo "  本文として落とさない。誤って安心させる側の誤りのほうが高くつくため、安全側へ倒してある。"
echo "  直す前は 4通りが誤爆だった（cat のリダイレクトが先／tee／python／コミットの伝言）。"
