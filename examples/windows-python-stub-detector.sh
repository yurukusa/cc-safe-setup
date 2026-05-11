#!/bin/bash
# windows-python-stub-detector.sh — Detect Microsoft Store python3 stub at session start
#
# Solves: Issue #57946 — On Windows Git Bash, `python3` may resolve to the
#   Microsoft Store stub rather than a real Python interpreter. The stub is
#   on PATH and `which python3` succeeds, but invoking it as a subprocess
#   exits 49 with no stdout and no stderr. Python-based PreToolUse and
#   PostToolUse hooks then exit silently before they can inspect the tool
#   call — the hook configuration is valid, the script file is present,
#   and the agent proceeds as if the hook approved.
#
# How it works: At SessionStart, probes the python3 command (or whatever
#   $CC_PYTHON_CMD points to) with a trivial Python statement. If exit code
#   is 49 (Store redirect) or stderr matches Store-redirect markers, emits a
#   warning via hookSpecificOutput.additionalContext. The model sees the
#   warning and can alert the user.
#
# Why advisory (no exit 2): SessionStart hooks blocking would prevent the
#   user from working at all. The user may have intentional fallback paths.
#   This hook surfaces the problem; the user decides what to do.
#
# TRIGGER: SessionStart
# MATCHER: none required

INPUT=$(cat)

# Allow tests / explicit overrides to point at a different binary
PYTHON_CMD="${CC_PYTHON_CMD:-python3}"

# Probe with a minimal Python statement.
# Real Python: prints "ok", exits 0.
# Microsoft Store stub: exits 49 with no output (sometimes "Microsoft Store"
#   markers in stderr depending on shell wrapper).
PROBE_OUTPUT=$("$PYTHON_CMD" -c 'import sys; sys.stdout.write("ok"); sys.exit(0)' 2>&1)
PROBE_EXIT=$?

# Detection conditions (any one trips the warning):
#   - exit code 49: documented Store-redirect signal in Git Bash subprocess
#   - stderr contains "Microsoft Store" or "install Python"
#   - exit code 127 or "command not found" / "no such file" output: python3 missing
#   - exit code 0 but no "ok" in output (stub may succeed silently in some shells)
TRIGGERED=0
if [ "$PROBE_EXIT" -eq 49 ]; then
    TRIGGERED=1
    REASON="python3 exited 49 (Microsoft Store redirect)"
elif echo "$PROBE_OUTPUT" | grep -qi 'microsoft store\|install python'; then
    TRIGGERED=1
    REASON="python3 stderr matched Store-redirect marker"
elif [ "$PROBE_EXIT" -eq 127 ] || echo "$PROBE_OUTPUT" | grep -qi 'command not found\|no such file'; then
    TRIGGERED=1
    REASON="python3 not found in PATH"
elif [ "$PROBE_EXIT" -eq 0 ] && ! echo "$PROBE_OUTPUT" | grep -q '^ok$'; then
    TRIGGERED=1
    REASON="python3 exited 0 but produced no output (suspected silent stub)"
fi

if [ "$TRIGGERED" -eq 1 ]; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"⚠️ python3 stub detected ($REASON). Any Python-based PreToolUse/PostToolUse hooks will exit 49 silently on this system and be ineffective. The hook configuration looks valid but the hooks never run. Fix: install real Python (winget install Python.Python.3.12, or from python.org) and ensure it precedes the Store stub in PATH, or rewrite hooks in bash. Reference: claude-code#57946."}}
EOF
fi

exit 0
