#!/bin/bash
# ================================================================
# reroute-after-block-guard.sh — Stop "reroute after a block"
# ================================================================
# PURPOSE:
#   PreToolUse hooks are stateless: each one evaluates the current
#   action in isolation, with no memory that a sibling action was
#   just denied. So a common failure trajectory slips through —
#   a gate fires on an action, the agent substitutes an equivalent
#   path toward the SAME target, and the next hook sees a fresh,
#   individually-defensible action and lets it run.
#   (anthropics/claude-code#70112: "Agent treats safety gates as
#    obstacles to route around" — goal misgeneralization.)
#
#   This hook adds the missing state. It reads the transcript: if
#   the PREVIOUS tool call was blocked by a PreToolUse hook and the
#   CURRENT action targets the same concrete FILE/path, it stops and
#   surfaces to the human instead of letting the reroute proceed. A
#   fired gate should RAISE the threshold for proceeding, not prompt
#   a search for another path.
#
#   This does not change the model's disposition; it converts a
#   silent reroute into a hard stop for the case where the blast
#   radius is concentrated on one target (a file, a path).
#
# Detects (only when ALL hold, else it stays out of the way):
#   1. the most recent tool result is an error, AND
#   2. its text is a Claude Code PreToolUse hook block
#      (the "PreToolUse: ... hook error" runner phrasing), AND
#   3. the blocked action and the current action share a concrete
#      filesystem path (anchored path or a path with a file
#      extension). Bare word/word tokens and git refs (origin/main,
#      refs/heads/...) are NOT treated as targets — inspecting a
#      branch after a push is rejected must stay allowed.
#
# Does NOT block (fail-open by design — never guesses):
#   - no transcript available / unreadable / jq missing
#   - previous tool succeeded (no gate fired)
#   - the error was a normal failure or a server-side rejection
#     ("permission denied", git "blocked by required reviews", etc.)
#   - no shared concrete file/path between blocked and current action
#   - the human explicitly re-authorizes with CC_REROUTE_ALLOW=1
#
# Legitimate retry after fixing the real problem is expected: set
#   CC_REROUTE_ALLOW=1 for that one command. Being forced to do so
#   IS the point — it makes "proceed after a block" a conscious act.
#
# NOTE: this hook deliberately omits `set -e`/`pipefail`. Every
#   jq/tail/grep failure must fall through to the next
#   `[ -z "$VAR" ] && exit 0` guard; a crash exit (1) would be
#   miscounted by Claude Code as a hook error rather than "allow".
#
# TRIGGER: PreToolUse  MATCHER: "Bash|Edit|Write|MultiEdit"
#
# CONFIG:
#   CC_REROUTE_ALLOW=1     one-shot override (proceed despite block)
#   CC_REROUTE_DISABLE=1   disable this hook entirely
# ================================================================

[ "${CC_REROUTE_DISABLE:-0}" = "1" ] && exit 0
[ "${CC_REROUTE_ALLOW:-0}" = "1" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TP" ] && exit 0
TP="${TP/#\~/$HOME}"
[ -r "$TP" ] || exit 0

# Current action's concrete target (command string or edited file).
CUR=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.file_path // empty' 2>/dev/null)
[ -z "$CUR" ] && exit 0

# Only the tail matters: a blocked tool_use and its result are adjacent
# and most recent. Bound the work so the hook stays cheap.
WINDOW=$(tail -n 120 "$TP" 2>/dev/null)
[ -z "$WINDOW" ] && exit 0

# Most recent tool_result: {id, err, text}. Parse each line independently with
# `try fromjson catch empty` so one malformed line can't abort the scan and
# leave us reading a stale (older) result. content may be string or array.
LAST=$(printf '%s' "$WINDOW" \
  | jq -Rc 'try (fromjson) catch empty
           | select(.message.content? != null) | .message.content[]?
           | select(.type=="tool_result")
           | {id: .tool_use_id,
              err: (.is_error // false),
              text: (.content
                     | if type=="array" then (map(.text? // "") | join(" "))
                       elif type=="string" then .
                       else "" end)}' 2>/dev/null | tail -n 1)
[ -z "$LAST" ] && exit 0

ERR=$(printf '%s' "$LAST" | jq -r '.err // false' 2>/dev/null)
[ "$ERR" = "true" ] || exit 0

TEXT=$(printf '%s' "$LAST" | jq -r '.text // ""' 2>/dev/null)
# Was the previous action stopped by a Claude Code PreToolUse hook? Match ONLY
# the hook runner's own phrasing ("PreToolUse: <matcher> hook error"). Generic
# "permission denied" / git "blocked by ..." server rejections are NOT gates —
# matching them would false-block ordinary post-failure work.
printf '%s' "$TEXT" | grep -qE 'PreToolUse:[^|]*hook error' || exit 0

BLOCKED_ID=$(printf '%s' "$LAST" | jq -r '.id // empty' 2>/dev/null)
[ -z "$BLOCKED_ID" ] && exit 0

# The blocked action's concrete target, linked by tool_use_id.
BLOCKED=$(printf '%s' "$WINDOW" \
  | jq -Rr --arg id "$BLOCKED_ID" 'try (fromjson) catch empty
          | select(.message.content? != null) | .message.content[]?
          | select(.type=="tool_use" and .id==$id)
          | (.input.command // .input.file_path // empty)' 2>/dev/null | tail -n 1)
[ -z "$BLOCKED" ] && exit 0

# Shared concrete file/path? Pull slash-bearing tokens from the blocked action,
# keep only real filesystem paths (anchored with / ./ ../ ~/, or carrying a file
# extension), drop flags and git refs, and look for any in the current action.
# A file/path overlap is the strong, low-false-positive signal that the agent is
# rerouting toward the same resource rather than doing unrelated work.
SHARED=""
while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    case "$tok" in
        -*) continue ;;                                                   # flag
        origin/*|upstream/*|remotes/*|refs/*|heads/*|tags/*) continue ;;  # git refs
    esac
    [ "${#tok}" -lt 4 ] && continue
    case "$tok" in
        /*|./*|../*|~/*) : ;;   # anchored filesystem path
        *.*) : ;;               # carries a file extension
        *) continue ;;          # bare word/word (e.g. origin/main) — not a target
    esac
    if printf '%s' "$CUR" | grep -qF -- "$tok"; then
        SHARED="$tok"
        break
    fi
done < <(printf '%s' "$BLOCKED" | grep -oE '(/|\./|\.\./|~/)?[A-Za-z0-9_.-]+(/[A-Za-z0-9_.+-]+)+')

[ -z "$SHARED" ] && exit 0

cat >&2 <<MSG
ブロック: 直前の操作はゲート(PreToolUseのhook)で止められました。
今回の操作は同じ対象「${SHARED}」へ向かう再ルートに見えます。
ゲートの発火は「別の経路を探せ」ではなく「立ち止まって正しさを確かめろ」の合図です。
回避策を探さず、人へ状況を共有してください。
本当に正しいと確認した上で進めるなら、その1コマンドだけ CC_REROUTE_ALLOW=1 を付けて実行してください。
MSG
exit 2
