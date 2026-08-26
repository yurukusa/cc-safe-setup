#!/bin/bash
# subagent-tool-call-limiter.sh — Limit total tool calls per session
#
# Solves: Subagents making unbounded tool calls (#36727).
#         One user reported 234 tool calls in 1.5 hours from a single subagent.
#         Existing rate limiters check frequency, not total count.
#
# How it works: PreToolUse hook (all tools) that increments a counter file.
#   When CC_MAX_TOOL_CALLS (default 200) is reached, blocks further calls.
#
# TRIGGER: PreToolUse
# MATCHER: ""

__CC_HOOK_INPUT=$(cat 2>/dev/null)
# --- セッション識別子でファイルを分ける (2026-08-09 修正) ---
# 旧実装は "$$" を使っていたが、$$ はこのスクリプト自身のPIDで呼び出しごとに変わるため、
# 状態が一度も持続しなかった(実測: 200回呼ぶとファイルが200個でき、中身は全部 1)。
__CC_SID=""
if [ -n "${__CC_HOOK_INPUT:-}" ]; then
  if command -v jq >/dev/null 2>&1; then
    __CC_SID=$(printf '%s' "$__CC_HOOK_INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
  fi
  if [ -z "$__CC_SID" ] && command -v python3 >/dev/null 2>&1; then
    __CC_SID=$(printf '%s' "$__CC_HOOK_INPUT" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("session_id") or d.get("sessionId") or "")
except Exception: print("")' 2>/dev/null)
  fi
fi
if [ -n "$__CC_SID" ]; then
  __CC_KEY=$(printf '%s' "$__CC_SID" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)
else
  __CC_KEY="nosession-$(date +%Y%m%d)"
fi
# --- ここまで ---

set -euo pipefail

MAX_CALLS="${CC_MAX_TOOL_CALLS:-200}"
COUNTER_FILE="/tmp/claude-tool-call-counter-$__CC_KEY"

# 2026-08-09: $PPID を使う旧機構を削除した。
# 旧実装は $PPID(親プロセスのID)をセッションの識別子として使っていた。
# ★訂正: 最初これを「一度も遮断しない」と書いたが、それは計測の誤りだった。
#   親が安定していれば $PPID は持続するので、上限10で15回叩くと11回目から5回遮断する(実測)。
#   「200回で遮断0回」という最初の測定は、こちらが $( ) の中で呼んだせいで
#   呼び出しごとに別のサブシェルが親になっていたためで、仕掛けが作った結果だった。
# 実際に残る欠陥はこちら: $PPID はセッションの識別子ではない。
#   同じ親から複数のセッションが走ると**カウンターが混ざる**。
#   実測: 同じ親から session_id が sX と sY の呼び出しを6回ずつ交互に流すと、
#   カウンターファイルは1個だけで値は12(=6+6)。片方のセッションが上限を使い切ると、
#   もう片方が何もしていなくても遮断される。
# 修正: hookの入力JSONの session_id で分ける。
#
# ★2026-08-27 追記: session_id だけでは、このhookの名前が約束していることができない。
#   PreToolUse の入力を丸ごと落として実測したところ、サブエージェントの呼び出しでも
#   session_id は親と1バイトも違わない(transcript_path も同じ)。増えるのは agent_id と
#   agent_type の2つだけ。つまり session_id を鍵にしたカウンターは、親と全サブエージェントの
#   合算になる。#36727 の「1体のサブエージェントが1.5時間で234回」を止めたくても、
#   合算のカウンターでは「誰が使ったか」が分からず、暴走した子が枠を焼き切ると
#   何もしていない親まで止まる。
#   → セッション全体の上限はそのままに、agent_id ごとの上限を足した。
#     どちらか先に達したほうで止める。合計の上限は変えていないので、緩くはならない。

MAX_SUBAGENT_CALLS="${CC_MAX_SUBAGENT_TOOL_CALLS:-100}"

# agent_id はサブエージェントの呼び出しにだけ入る(実測)。上位エージェントでは空。
__CC_AID=""
if [ -n "${__CC_HOOK_INPUT:-}" ] && command -v jq >/dev/null 2>&1; then
  __CC_AID=$(printf '%s' "$__CC_HOOK_INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
fi
__CC_AKEY=$(printf '%s' "$__CC_AID" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)
AGENT_COUNTER_FILE="/tmp/claude-tool-call-counter-$__CC_KEY-agent-$__CC_AKEY"

read_counter() {
  _v=0
  if [ -f "$1" ]; then
    _v=$(cat "$1" 2>/dev/null || echo 0)
    case "$_v" in ''|*[!0-9]*) _v=0 ;; esac
  fi
  printf '%s' "$_v"
}

COUNT=$(( $(read_counter "$COUNTER_FILE") + 1 ))
AGENT_COUNT=0
[ -n "$__CC_AID" ] && AGENT_COUNT=$(( $(read_counter "$AGENT_COUNTER_FILE") + 1 ))

# ★記録は遮断を決めた後に置く。先に書くと、案内を読んで再試行するたびに
#   カウンターが増えて待ち時間が自分の再試行で延びる(2026-07-28 に別のhookで実害)。
if [ "$COUNT" -gt "$MAX_CALLS" ]; then
  echo "BLOCKED: Tool call limit reached ($COUNT/$MAX_CALLS) for this session." >&2
  echo "This session (parent and all subagents share one session_id) has made" >&2
  echo "$COUNT tool calls (limit: $MAX_CALLS)." >&2
  echo "Consider starting a new session or increasing CC_MAX_TOOL_CALLS." >&2
  exit 2
fi

if [ -n "$__CC_AID" ] && [ "$AGENT_COUNT" -gt "$MAX_SUBAGENT_CALLS" ]; then
  echo "BLOCKED: Subagent tool call limit reached ($AGENT_COUNT/$MAX_SUBAGENT_CALLS)." >&2
  echo "Subagent agent_id=$__CC_AID has made $AGENT_COUNT tool calls on its own." >&2
  echo "The session as a whole is still at $COUNT/$MAX_CALLS, so the parent is not blocked." >&2
  echo "Raise CC_MAX_SUBAGENT_TOOL_CALLS if this subagent legitimately needs more." >&2
  exit 2
fi

echo "$COUNT" > "$COUNTER_FILE"
[ -n "$__CC_AID" ] && echo "$AGENT_COUNT" > "$AGENT_COUNTER_FILE"

# Warn at 80%
WARN_AT=$((MAX_CALLS * 80 / 100))
if [ "$COUNT" -eq "$WARN_AT" ]; then
  echo "WARNING: $COUNT/$MAX_CALLS tool calls used (80%). Consider wrapping up." >&2
fi

AGENT_WARN_AT=$((MAX_SUBAGENT_CALLS * 80 / 100))
if [ -n "$__CC_AID" ] && [ "$AGENT_COUNT" -eq "$AGENT_WARN_AT" ]; then
  echo "WARNING: subagent $__CC_AID is at $AGENT_COUNT/$MAX_SUBAGENT_CALLS of its own budget." >&2
fi

exit 0
