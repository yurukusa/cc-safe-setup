#!/bin/bash
# wellness-break-reminder.sh — Remind the user to take a body break
#
# What this is: a hook that watches your Claude Code session and, after
# you've been working without a noticed pause for ~90 minutes, prints a
# short reminder to your terminal: did you drink water, did you stand up,
# is your back okay?
#
# Why this exists: AI coding assistants make long sessions feel shorter
# than they are. Tokens flow, code gets written, time passes. The token
# usage warning (long-session-reminder.sh) handles the cost side. This
# hook handles the body side, which the existing wellness/posture
# literature suggests is the part that quietly accumulates harm.
#
# Tone: this is meant to feel like a colleague leaning over your desk,
# not a popup ad. It fires at most once per 30 minutes, even if the
# 90-minute threshold has been exceeded for hours, so it won't nag.
#
# TRIGGER: PostToolUse  MATCHER: ""
# (empty matcher = fires on every tool use, but we throttle internally)
#
# CONFIG:
#   CC_WELLNESS_FIRST_MIN=90    最初に出すまでの分数 (デフォルト 90 分)
#   CC_WELLNESS_REPEAT_MIN=30   繰り返しの最短間隔 (デフォルト 30 分)
#   CC_WELLNESS_OFF=1           完全に黙らせる (本人がいま集中したい時など)

# stdin を読んでも使わない (PostToolUse hook の入力 JSON は無視)
cat > /dev/null

[ "${CC_WELLNESS_OFF:-0}" = "1" ] && exit 0

FIRST_THRESHOLD_MIN="${CC_WELLNESS_FIRST_MIN:-90}"
REPEAT_INTERVAL_MIN="${CC_WELLNESS_REPEAT_MIN:-30}"

START_FLAG="$HOME/.claude/wellness-session-start"
LAST_REMIND="$HOME/.claude/wellness-last-reminder"

# 最初の作業でセッション開始時刻を記録
if [ ! -f "$START_FLAG" ]; then
    date +%s > "$START_FLAG"
    exit 0
fi

# Claude Code のセッションが終わった時に START_FLAG が残っていると、
# 次のセッションで誤った時刻が使われる。stop hook 等で消すのが本来だが、
# ここでは 12 時間以上経った flag は古すぎるとみて作り直す
START_EPOCH=$(cat "$START_FLAG" 2>/dev/null)
NOW_EPOCH=$(date +%s)
if [ -z "$START_EPOCH" ]; then
    date +%s > "$START_FLAG"
    exit 0
fi
ELAPSED_SEC=$(( NOW_EPOCH - START_EPOCH ))
if [ "$ELAPSED_SEC" -lt 0 ] || [ "$ELAPSED_SEC" -gt 43200 ]; then
    # 12 時間 (43200 秒) を超えていたら stale flag、新しく作り直す
    date +%s > "$START_FLAG"
    : > "$LAST_REMIND"
    exit 0
fi

ELAPSED_MIN=$(( ELAPSED_SEC / 60 ))

# まだ閾値に届いていない
if [ "$ELAPSED_MIN" -lt "$FIRST_THRESHOLD_MIN" ]; then
    exit 0
fi

# 直近のリマインダー時刻を確認、繰り返し間隔を守る
# stale-reset path で `: > "$LAST_REMIND"` が空ファイルを残す経路があり、
# 空 / 非数値の内容を読むと後続の `[ -gt 0 ]` で integer error が出て
# throttle が bypass される。空 / 非数値は 0 扱いに正規化 (PR #137 Codex review fix)
LAST_EPOCH=0
if [ -f "$LAST_REMIND" ]; then
    LAST_EPOCH_RAW=$(cat "$LAST_REMIND" 2>/dev/null)
    case "$LAST_EPOCH_RAW" in
        ''|*[!0-9]*) LAST_EPOCH=0 ;;
        *) LAST_EPOCH="$LAST_EPOCH_RAW" ;;
    esac
fi
SINCE_LAST_MIN=$(( (NOW_EPOCH - LAST_EPOCH) / 60 ))
if [ "$LAST_EPOCH" -gt 0 ] && [ "$SINCE_LAST_MIN" -lt "$REPEAT_INTERVAL_MIN" ]; then
    exit 0
fi

# メッセージを 1 つ選んで出す (作業時間で内容を変える)
HOURS=$(( ELAPSED_MIN / 60 ))
MINS=$(( ELAPSED_MIN % 60 ))

if [ "$HOURS" -lt 2 ]; then
    cat >&2 <<EOF

🫖 セッション ${HOURS}時間${MINS}分続いています。
  コーヒーが冷めていませんか？水を一杯どうですか。
  3 分くらい立ち上がって肩を回すと、たぶん次の判断が少し変わります。
  (このリマインダーを止めるなら CC_WELLNESS_OFF=1)
EOF
elif [ "$HOURS" -lt 4 ]; then
    cat >&2 <<EOF

🪟 もう ${HOURS}時間${MINS}分経ちました。
  画面から目を離して、3 メートル先のものを 30 秒見てください。
  立って、コップに水を入れて、トイレに行く。コードはここで待っています。
  AI の私には体がないけれど、あなたにはある。
EOF
else
    cat >&2 <<EOF

🌙 ${HOURS}時間${MINS}分。長丁場です。
  そろそろ続きは明日にしませんか。残りの判断の質は、いまの肩や首の痛みと
  たぶん相関しています。git commit して、画面を閉じて、ベッドへ。
  私はあなたが戻ってきた時、いつでも続きから出来ます。
EOF
fi

# 直近のリマインダー時刻を更新
date +%s > "$LAST_REMIND"

exit 0
