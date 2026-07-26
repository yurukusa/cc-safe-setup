#!/bin/bash
# ================================================================
# bypass-mode-effective-verifier.sh — Warn when bypass mode is actually in effect
# ================================================================
# PURPOSE:
#   This hook reports at session start via hookSpecificOutput /
#   additionalContext. Without the TRIGGER header below, the
#   installer registered it under the default PreToolUse/Bash,
#   so it fired on every Bash call and never ran at session start.
#
# TRIGGER: SessionStart
# MATCHER: ""
# ================================================================

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

# Signal 4: settings.json. Env vars and hook input miss the case where bypass is
# set as the *saved default* (#65848): accepting the warning prompt silently writes
# `defaultMode: bypassPermissions` and `skipDangerousModePermissionPrompt: true` to
# settings.json permanently, and the upstream prompt never reappears — so the operator
# loses the per-session awareness that they are in dangerous mode at all. Read the
# settings file directly so a silently-persisted default is still surfaced each session.
# CC_BYPASS_VERIFIER_SETTINGS overrides the path (used by tests).
SETTINGS_FILE="${CC_BYPASS_VERIFIER_SETTINGS:-$HOME/.claude/settings.json}"
SKIP_PROMPT_PERSISTED=0
if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_MODE=$(jq -r '.permissions.defaultMode // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [ "$SETTINGS_MODE" = "bypassPermissions" ]; then
        BYPASS_ACTIVE=1
        [ -z "$BYPASS_SIGNAL" ] && BYPASS_SIGNAL="settings.json permissions.defaultMode=bypassPermissions"
    fi
    SKIP_PROMPT=$(jq -r '.skipDangerousModePermissionPrompt // empty' "$SETTINGS_FILE" 2>/dev/null)
    case "$SKIP_PROMPT" in 1|true|TRUE|True|yes|YES) SKIP_PROMPT_PERSISTED=1 ;; esac
fi

# Nothing to warn about if bypass isn't active AND the dangerous-mode prompt
# has not been silently suppressed.
[ "$BYPASS_ACTIVE" = "0" ] && [ "$SKIP_PROMPT_PERSISTED" = "0" ] && exit 0

# The standing note about the silently-persisted dangerous-mode prompt (#65848).
# Accepting the bypass warning writes `skipDangerousModePermissionPrompt: true` to
# settings.json permanently with no disclosure, so Claude Code never re-warns. The
# hook re-surfaces that suppressed awareness each session.
SKIP_NOTE=""
if [ "$SKIP_PROMPT_PERSISTED" = "1" ]; then
    SKIP_NOTE="
- skipDangerousModePermissionPrompt=true is set in settings.json: the upstream dangerous-mode warning is silently suppressed on this machine (#65848). Claude Code will not re-warn you when entering bypass mode. Remove that key to restore the prompt, or keep this hook as the standing warning."
fi

# Build the warning message. Kept compact to minimize cache_creation
# token growth at session start.
if [ "$BYPASS_ACTIVE" = "1" ]; then
    MSG="bypass mode ACTIVE ($BYPASS_SIGNAL). --dangerously-skip-permissions does NOT cover every permission gate. Known exceptions in cc-safe-setup Cluster 6 Axis 7 tracking:

- Edit tool still prompts (#36192)
- Cowork scheduled tasks re-prompt every run (#47180)
- Mobile Remote Control shows prompts (#29214)
- Bypass flag itself broken after v2.1.77 (#36168, regression open)${SKIP_NOTE}

If you depend on bypass for unattended runs (cron, watchdog, automation), test the specific tool surfaces you use BEFORE the run, not during. Tracking meta-issue: #39523 (12+ duplicates over 9 months)."
else
    # Bypass is not currently the active mode, but the dangerous-mode warning has been
    # permanently suppressed — surface that disabled guardrail on its own (#65848).
    MSG="dangerous-mode warning SUPPRESSED.${SKIP_NOTE}"
fi

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
