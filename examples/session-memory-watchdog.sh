MAX_RSS_MB="${CC_MAX_RSS_MB:-4096}"
CHECK_INTERVAL=300
(
    while true; do
        sleep "$CHECK_INTERVAL"
        pgrep -f "claude" | while read pid; do
            RSS_KB=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
            [ -z "$RSS_KB" ] && continue
            RSS_MB=$((RSS_KB / 1024))
            if [ "$RSS_MB" -gt "$MAX_RSS_MB" ]; then
                echo "[$(date -Iseconds)] PID $pid: ${RSS_MB}MB > ${MAX_RSS_MB}MB limit" >> ~/.claude/memory-watchdog.log
                kill -15 "$pid" 2>/dev/null
            fi
        done
    done
) &
exit 0
