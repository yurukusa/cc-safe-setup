#!/bin/bash
# Tests for subagent-tool-call-limiter.sh
#
# 2026-08-09 新規。このhookには**テストが1本も無かった**。
#
# 旧実装は $PPID(親プロセスのID)をセッションの識別子として使っていた。
# 遮断そのものは動く(親が安定していれば $PPID は持続する)。
# 残る欠陥は「$PPID はセッションの識別子ではない」こと:
#   同じ親から複数のセッションが走るとカウンターが混ざる。
#   実測(修正前) = 同じ親から session_id が sX と sY の呼び出しを6回ずつ交互に流すと、
#   カウンターファイルは1個だけで値は12(=6+6)。片方が上限を使い切ると、
#   もう片方は何もしていなくても遮断される。
# 修正後は session_id ごとに分ける。
#
# ★このテストを書く過程で自分の測定を1つ取り下げた。最初「200回叩いて遮断0回=
#   この制限は一度も働いていない」と測ったが、それはこちらが $( ) の中で hook を
#   呼んだせいで呼び出しごとに別のサブシェルが親になっていたためで、
#   仕掛けが作った結果だった。親を固定して測り直すと5回ちゃんと遮断する。
#   だからこのテストは「遮断が動くこと」と「セッションが独立すること」の両方を見る。

HOOK="examples/subagent-tool-call-limiter.sh"
PASS=0 FAIL=0
ok() { PASS=$((PASS+1)); }
ng() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
assert_eq() { if [ "$2" = "$3" ]; then ok; else ng "$1 (expected '$3', got '$2')"; fi; }

SID="test-limiter-$$-$RANDOM"
J="{\"session_id\":\"$SID\",\"tool_name\":\"Task\",\"tool_input\":{}}"
CF="/tmp/claude-tool-call-counter-$SID"
rm -f "$CF"

# 上限を10にして15回叩く
blocked=0
for i in $(seq 1 15); do
  printf '%s' "$J" | CC_MAX_TOOL_CALLS=10 bash "$HOOK" >/dev/null 2>&1
  [ $? -eq 2 ] && blocked=$((blocked+1))
done

# 回帰1: 上限を超えたら遮断する(修正前は0回だった)
assert_eq "上限10で15回叩くと11..15回目の5回が遮断される" "$blocked" "5"

# 回帰2: カウンターが呼び出しをまたいで貯まる(修正前は毎回1にリセットされていた)
assert_eq "カウンターが15まで進む" "$(cat "$CF" 2>/dev/null)" "15"

# 回帰3: カウンターのファイルはセッションにつき1個(修正前は呼び出しごとに1個increaseしていた)
assert_eq "ファイルはセッションにつき1個" "$(ls /tmp/claude-tool-call-counter-$SID 2>/dev/null | wc -l)" "1"

# 回帰4: 別セッションは独立して数える
SID2="test-limiter2-$$-$RANDOM"
J2="{\"session_id\":\"$SID2\",\"tool_name\":\"Task\",\"tool_input\":{}}"
CF2="/tmp/claude-tool-call-counter-$SID2"
rm -f "$CF2"
printf '%s' "$J2" | CC_MAX_TOOL_CALLS=10 bash "$HOOK" >/dev/null 2>&1
rc2=$?
assert_eq "別セッションの1回目は遮断されない" "$rc2" "0"
assert_eq "別セッションのカウンターは1" "$(cat "$CF2" 2>/dev/null)" "1"

# 上限内は素通しする
SID3="test-limiter3-$$-$RANDOM"
J3="{\"session_id\":\"$SID3\",\"tool_name\":\"Task\",\"tool_input\":{}}"
CF3="/tmp/claude-tool-call-counter-$SID3"
rm -f "$CF3"
printf '%s' "$J3" | CC_MAX_TOOL_CALLS=100 bash "$HOOK" >/dev/null 2>&1
assert_eq "上限内は exit 0" "$?" "0"

# 遮断のメッセージが理由を述べる
echo "10" > "$CF3"
MSG=$(printf '%s' "$J3" | CC_MAX_TOOL_CALLS=10 bash "$HOOK" 2>&1 >/dev/null)
if echo "$MSG" | grep -q "limit"; then ok; else ng "遮断のメッセージが上限に触れる"; fi

# 回帰5 (本命): 同じ親プロセスから2つのセッションを交互に流してもカウンターが混ざらない。
# これが旧実装($PPID をセッション識別子にしていた)で壊れていた点。
# 修正前の実測 = ファイル1個・値12(=6+6)。片方が上限を使い切るともう片方も遮断された。
SX="test-mix-x-$$-$RANDOM"; SY="test-mix-y-$$-$RANDOM"
JX="{\"session_id\":\"$SX\",\"tool_name\":\"Task\",\"tool_input\":{}}"
JY="{\"session_id\":\"$SY\",\"tool_name\":\"Task\",\"tool_input\":{}}"
rm -f "/tmp/claude-tool-call-counter-$SX" "/tmp/claude-tool-call-counter-$SY"
for i in $(seq 1 6); do
  printf '%s' "$JX" | CC_MAX_TOOL_CALLS=10 bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$JY" | CC_MAX_TOOL_CALLS=10 bash "$HOOK" >/dev/null 2>&1
done
assert_eq "同じ親でもセッションXは6" "$(cat "/tmp/claude-tool-call-counter-$SX" 2>/dev/null)" "6"
assert_eq "同じ親でもセッションYは6" "$(cat "/tmp/claude-tool-call-counter-$SY" 2>/dev/null)" "6"
rm -f "/tmp/claude-tool-call-counter-$SX" "/tmp/claude-tool-call-counter-$SY"

rm -f "$CF" "$CF2" "$CF3"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
