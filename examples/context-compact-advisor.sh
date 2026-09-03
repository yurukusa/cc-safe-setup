#!/bin/bash
INPUT=$(cat)
__CC_HOOK_INPUT="$INPUT"
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

COUNTER="/tmp/cc-tool-count-$__CC_KEY"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER"
THRESHOLD="${CC_COMPACT_THRESHOLD:-50}"
if [ "$((COUNT % THRESHOLD))" -eq 0 ]; then
    # 記録の場所を推測しない（旧: projects/*/sessions/*/transcript.jsonl は実在せず、
    # glob が空のまま黙って何も助言しなかった）。
    TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -f "$TRANSCRIPT" ] || TRANSCRIPT=$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
    if [ -f "$TRANSCRIPT" ]; then
        SIZE_KB=$(($(wc -c < "$TRANSCRIPT") / 1024))
        if [ "$SIZE_KB" -gt 200 ]; then
            echo "Context ~${SIZE_KB}KB ($COUNT calls). Consider /compact." >&2
        fi
    fi
fi
exit 0
