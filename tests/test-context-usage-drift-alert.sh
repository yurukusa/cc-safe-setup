#!/bin/bash
# Tests for context-usage-drift-alert.sh
#
# 2026-08-09 更新: hookがカウンターを session_id ごとに分けるようになったので、
# テストもその契約を検査する形へ直した。
# 旧テストは "/tmp/cc-context-usage-counter-$(date +%Y%m%d)" というファイル名を
# 直に握っていた。これは実装の詳細で、しかもその名前は「セッション横断で共有される」
# という**壊れていた挙動そのもの**だった(旧hookは $$ を使っていたが $$ は呼び出しごとに
# 変わるため一度も持続せず、常に日付版へ落ちていた)。
# 新しい契約: 同じ session_id の中では 50/100/150 を跨いだ回に鳴り、
#             別の session_id は独立して数える。

HOOK="examples/context-usage-drift-alert.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3', got '$2')"; fi; }

SID="test-drift-$$-$RANDOM"
J="{\"session_id\":\"$SID\",\"tool_name\":\"Bash\"}"
CF="/tmp/cc-context-usage-counter-$SID"
rm -f "$CF"

# Test 1: Calls 1-49 should not warn
for i in $(seq 1 49); do printf '%s' "$J" | bash "$HOOK" 2>/dev/null; done
OUT=$(printf '%s' "$J" | bash "$HOOK" 2>&1)
assert_contains "call 50 should checkpoint" "$OUT" "checkpoint"
assert_contains "should mention /cost" "$OUT" "/cost"

# Test 2: Calls 51-99 should not warn
for i in $(seq 51 99); do printf '%s' "$J" | bash "$HOOK" 2>/dev/null; done
OUT=$(printf '%s' "$J" | bash "$HOOK" 2>&1)
assert_contains "call 100 should warn high" "$OUT" "HIGH CONTEXT"
assert_contains "should mention /compact" "$OUT" "/compact"
assert_contains "should reference issue" "$OUT" "#50204"

# Test 3: Calls 101-149
for i in $(seq 101 149); do printf '%s' "$J" | bash "$HOOK" 2>/dev/null; done
OUT=$(printf '%s' "$J" | bash "$HOOK" 2>&1)
assert_contains "call 150 critical warning" "$OUT" "VERY HIGH"
assert_contains "should mention saving state" "$OUT" "Save"

# Test 4: Normal calls between thresholds should be silent
rm -f "$CF"; echo "10" > "$CF"
OUT=$(printf '%s' "$J" | bash "$HOOK" 2>&1)
assert_not_contains "non-threshold call should be silent" "$OUT" "checkpoint"
assert_not_contains "non-threshold no warning" "$OUT" "HIGH"

# Test 5 (回帰): 別の session_id は独立して数える。
# これが旧実装で壊れていた点=カウンターが全セッションで共有され、
# 150を一度超えるとその日はもう二度と鳴らなかった。
SID2="test-drift2-$$-$RANDOM"
J2="{\"session_id\":\"$SID2\",\"tool_name\":\"Bash\"}"
CF2="/tmp/cc-context-usage-counter-$SID2"
rm -f "$CF2"
echo "200" > "$CF"   # 1本目は閾値を全部跨ぎ終えた状態にする
for i in $(seq 1 49); do printf '%s' "$J2" | bash "$HOOK" 2>/dev/null; done
OUT=$(printf '%s' "$J2" | bash "$HOOK" 2>&1)
assert_contains "別セッションは独立して50で鳴る" "$OUT" "checkpoint"
OUT=$(printf '%s' "$J" | bash "$HOOK" 2>&1)
assert_not_contains "跨ぎ済みのセッションは鳴らない" "$OUT" "checkpoint"

# Test 6 (回帰): 閾値を「跨いだ」判定なので、数が飛んでも取りこぼさない。
# 旧実装は -eq の完全一致だったので、49→51 のように飛ぶと永久に鳴らなかった。
SID3="test-drift3-$$-$RANDOM"
J3="{\"session_id\":\"$SID3\",\"tool_name\":\"Bash\"}"
CF3="/tmp/cc-context-usage-counter-$SID3"
echo "148" > "$CF3"
printf '%s' "$J3" | bash "$HOOK" 2>/dev/null      # 149
OUT=$(printf '%s' "$J3" | bash "$HOOK" 2>&1)      # 150 を跨ぐ
assert_contains "跨ぎ判定で150を捕まえる" "$OUT" "VERY HIGH"

# Test 7: session_id が無くても壊れない(日付単位へ落ちる)
OUT=$(printf '{"tool_name":"Bash"}' | bash "$HOOK" 2>&1; echo "rc=$?")
assert_contains "session_idが無くても正常終了" "$OUT" "rc=0"

# Cleanup
rm -f "$CF" "$CF2" "$CF3"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
