#!/bin/bash
# ================================================================
# bypass-mode-effective-verifier.sh — Warn about partial bypass-mode
# coverage when --dangerously-skip-permissions is active
# ================================================================
# PURPOSE:
#   Cluster 6 Axis 7. The --dangerously-skip-permissions flag
#   (a.k.a. "bypass mode") does NOT bypass every permission gate
#   the way operators expect. Documented exceptions and known bugs:
#     - Edit tool prompts still fire (#36192)
#     - Cowork scheduled tasks ignore "Always allow" rules and
#       re-prompt every run (#47180)
#     - Mobile Remote Control shows permission prompts despite the
#       flag being set (#29214, 71 reactions)
#     - The flag itself stopped working entirely after v2.1.77
#       (#36168, 63 reactions, regression open as of v2.1.150)
#   Meta-issue #39523 tracks the regression with 12+ duplicates
#   over 9 months.
#
#   Operators run with --dangerously-skip-permissions expecting
#   "no prompts at all" and only discover the partial coverage
#   when something they assumed was bypassed surfaces a prompt
#   anyway, mid-task. The hook makes the partial coverage legible
#   at session start so the operator can plan accordingly.
#
# DETECTION:
#   At SessionStart, detect bypass mode via three signals:
#     1. env var CLAUDE_PERMISSION_MODE = "bypassPermissions"
#     2. env var CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS = "1"/"true"
#     3. permission_mode field in the hook input JSON
#   If any signal indicates bypass mode is active, emit the warning.
#
# OUTPUT:
#   hookSpecificOutput.additionalContext naming the four known
#   tool surfaces that the bypass does NOT cover, with issue links
#   so the operator can verify the current upstream state. Kept
#   short to minimize cache_creation tokens at session start
#   (Cluster 4 — Pro Max quota anomaly — interaction).
#
# CONFIGURATION:
#   CC_BYPASS_VERIFIER_DISABLE  — set to 1 to suppress the warning
#                                 entirely (operator already aware).
#   CC_BYPASS_VERIFIER_SILENT   — set to 1 to skip JSON output but
#                                 still emit stderr advisory.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/29214
#   https://github.com/anthropics/claude-code/issues/36168
#   https://github.com/anthropics/claude-code/issues/36192
#   https://github.com/anthropics/claude-code/issues/39523
#   https://github.com/anthropics/claude-code/issues/47180
# ================================================================

set -u

INPUT=$(cat 2>/dev/null || echo "{}")

# Allow operator to disable without removing the hook.
[ "${CC_BYPASS_VERIFIER_DISABLE:-0}" = "1" ] && exit 0

# Detect bypass mode via three independent signals.
BYPASS_ACTIVE=0
BYPASS_SIGNAL=""

# Signal 1: env var CLAUDE_PERMISSION_MODE
if [ "${CLAUDE_PERMISSION_MODE:-}" = "bypassPermissions" ]; then
    BYPASS_ACTIVE=1
    BYPASS_SIGNAL="CLAUDE_PERMISSION_MODE=bypassPermissions"
fi

# Signal 2: env var CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS
case "${CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS:-}" in
    1|true|TRUE|True|yes|YES)
        BYPASS_ACTIVE=1
        BYPASS_SIGNAL="CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=${CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS}"
        ;;
esac

# Signal 3: permission_mode field in the hook input JSON
INPUT_MODE=$(printf '%s' "$INPUT" | jq -r '.permission_mode // .permissionMode // empty' 2>/dev/null)
if [ "$INPUT_MODE" = "bypassPermissions" ]; then
    BYPASS_ACTIVE=1
    BYPASS_SIGNAL="hook input permission_mode=bypassPermissions"
fi

# Nothing to warn about if bypass isn't active.
[ "$BYPASS_ACTIVE" = "0" ] && exit 0

# Build the warning message. Kept compact to minimize cache_creation
# token growth at session start.
MSG="bypass mode ACTIVE ($BYPASS_SIGNAL). --dangerously-skip-permissions does NOT cover every permission gate. Known exceptions in cc-safe-setup Cluster 6 Axis 7 tracking:

- Edit tool still prompts (#36192)
- Cowork scheduled tasks re-prompt every run (#47180)
- Mobile Remote Control shows prompts (#29214)
- Bypass flag itself broken after v2.1.77 (#36168, regression open)

If you depend on bypass for unattended runs (cron, watchdog, automation), test the specific tool surfaces you use BEFORE the run, not during. Tracking meta-issue: #39523 (12+ duplicates over 9 months)."

# Always echo to stderr for operator visibility.
echo "[bypass-mode-effective-verifier] $MSG" >&2

# Emit JSON additionalContext unless silent mode is requested.
if [ "${CC_BYPASS_VERIFIER_SILENT:-0}" != "1" ]; then
    jq -n --arg msg "$MSG" '
    {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": $msg
        }
    }' 2>/dev/null || true
fi

exit 0
