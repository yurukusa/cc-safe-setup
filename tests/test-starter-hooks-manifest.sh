#!/bin/bash
# test-starter-hooks-manifest.sh — hooks/hooks.json の同梱フックを両方向で検証する
#
# なぜ要るか: hooks/hooks.json は README から参照されていないが、リポジトリを
# 見に来た人が実際に開いてコピーしていく面（2026-08-18 に traffic API で実測＝
# 14日で6閲覧・2人）。そこに入っている素通りは、そのまま利用者の環境へ複製される。
#
# 2026-08-18 に実測で見つかった4件の素通り／誤爆を、二度と入れないための回帰試験。
#   1. 免除の語がコマンド全体に部分一致し、"./buildout" や末尾に足した "/tmp" で無効化された
#   2. --force-with-lease（案内文自身が勧める安全側）を止めていた
#   3. .env.local / .env.production / 拡張子の無い credentials が素通りした
#   4. api.key の "." が任意の1文字に当たり apiXkey で誤爆した
#
# 対照を必ず置く（止める側と通す側の両方を数える）。片方だけだと、
# 何も止めないフックでも、何でも止めるフックでも「合格」になる。

set -u
cd "$(dirname "$0")/.." || exit 1
# 対照を取れるようにする＝旧版を指して走らせると落ちることを確かめられる
MANIFEST="${MANIFEST:-hooks/hooks.json}"
PASS=0
FAIL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq が無いのでこの試験は成立しない"; exit 0; }

# 目録から、スクリプトを指していない素のフックの本体を取り出す
extract() {
  python3 -c "
import json,sys
d=json.load(open('$MANIFEST'))
out=[h['command'] for e in d['hooks']['PreToolUse'] for h in e['hooks']]
out=[c for c in out if not c.strip().startswith('~')]
print(out[int(sys.argv[1])])
" "$1"
}

payload_cmd() {
  python3 -c "import json,sys;print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" "$1"
}
payload_file() {
  python3 -c "import json,sys;print(json.dumps({'tool_input':{'file_path':sys.argv[1]}}))" "$1"
}

# $1=フックの番号 $2=payload $3=期待の終了コード $4=説明
check() {
  local body rc
  body=$(extract "$1")
  rc=$(printf '%s' "$2" | bash -c "$body
exit 0" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "$3" ]; then
    PASS=$((PASS + 1)); echo "  PASS: $4"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $4 (終了コード $rc・期待 $3)"
  fi
}

DEL="rm"

echo "== 再帰削除の番人 =="
check 0 "$(payload_cmd "$DEL -rf ./buildout")"                2 "免除の語の部分一致で素通りしない (buildout)"
check 0 "$(payload_cmd "$DEL -rf ./distribution")"            2 "免除の語の部分一致で素通りしない (distribution)"
check 0 "$(payload_cmd "$DEL -rf ./data && ls /tmp")"         2 "後ろに足した語では免除されない"
check 0 "$(payload_cmd "$DEL -rf ./data # cleanup of build")" 2 "コメントの語では免除されない"
check 0 "$(payload_cmd "sudo $DEL -rf ./stage")"              2 "sudo つきも止める"
check 0 "$(payload_cmd "$DEL --recursive ./data")"            2 "長い書き方の再帰も止める"
check 0 "$(payload_cmd "$DEL -rf node_modules")"              0 "対照: 本当に安全な対象は通す"
check 0 "$(payload_cmd "$DEL -rf /tmp/x")"                    0 "対照: /tmp は通す"
check 0 "$(payload_cmd "$DEL -f one.txt")"                    0 "対照: 再帰でなければ通す"

echo "== git の番人 =="
check 1 "$(payload_cmd 'git push --force origin main')" 2 "強制の push を止める"
check 1 "$(payload_cmd 'git reset --hard HEAD~1')"      2 "hard reset を止める"
check 1 "$(payload_cmd 'git clean -fd')"                2 "追跡外の掃除を止める"
check 1 "$(payload_cmd 'git push --force-with-lease origin a; git push --force origin b')" 2 "安全側を混ぜても危険側は止める"
check 1 "$(payload_cmd 'git push --force-with-lease origin main')" 0 "対照: 案内文が勧める安全側は通す"
check 1 "$(payload_cmd 'git push origin main')"                    0 "対照: 素の push は通す"

echo "== 資格情報の番人 =="
check 2 "$(payload_cmd 'export API_KEY=abcdefghij0123456789')" 2 "環境変数への直書きを止める"
check 2 "$(payload_cmd 'export apiXkey=abcdefghij0123456789')" 0 "対照: 任意の1文字には当たらない"
check 2 "$(payload_cmd 'echo hello')"                          0 "対照: 無関係な命令は通す"

echo "== 機微ファイルの番人 =="
check 3 "$(payload_file '.env')"             2 ".env を止める"
check 3 "$(payload_file '.env.local')"       2 ".env.local を止める"
check 3 "$(payload_file '.env.production')"  2 ".env.production を止める"
check 3 "$(payload_file '.aws/credentials')" 2 "拡張子の無い credentials を止める"
check 3 "$(payload_file 'config/secret')"    2 "拡張子の無い secret を止める"
check 3 "$(payload_file 'cert.pem')"         2 ".pem を止める"
check 3 "$(payload_file '.env.example')"     0 "対照: 見本の .env は通す"
check 3 "$(payload_file 'src/main.py')"      0 "対照: 普通のソースは通す"
check 3 "$(payload_file 'README.md')"        0 "対照: 普通の文書は通す"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
