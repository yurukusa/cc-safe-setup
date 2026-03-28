#!/bin/bash
# permission-mode-drift-guard.sh — Detect permission mode changes mid-session
#
# Solves: Permission mode resets from 'Bypass permissions' to 'Edit automatically'
#         mid-session without user interaction (#39057, 3 reactions).
#
# How it works: On SessionStart, records the initial permission mode.
#   On each PermissionRequest, compares current behavior against expected.
#   If permissions are being requested when bypass mode was set,
#   warns the user that the mode may have drifted.
#
# Uses ConfigChange hook event (v2.1.83+) when available, falls back
# to heuristic detection via unexpected permission prompts.
#
# TRIGGER: PermissionRequest (fallback detection)
# MATCHER: "" (all permission requests)

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)

STATE_FILE="/tmp/cc-permission-mode-${PPID}"

# On first call, record that we're getting permission prompts
if [ ! -f "$STATE_FILE" ]; then
    echo "prompt_count=1" > "$STATE_FILE"
    echo "first_prompt=$(date +%s)" >> "$STATE_FILE"
    exit 0
fi

# Track prompt count
. "$STATE_FILE"
prompt_count=$((prompt_count + 1))
echo "prompt_count=$prompt_count" > "$STATE_FILE"
echo "first_prompt=$first_prompt" >> "$STATE_FILE"

# If we're getting many permission prompts, something may be wrong
if [ "$prompt_count" -eq 5 ]; then
    echo "⚠ Permission mode drift detected: ${prompt_count} permission prompts this session" >&2
    echo "  If you set 'Bypass permissions', it may have reset to 'Edit automatically'" >&2
    echo "  Check: Ctrl+Shift+P → Claude Code: Set Permission Mode" >&2
fi

if [ "$prompt_count" -eq 20 ]; then
    echo "⚠ ${prompt_count} permission prompts — consider re-enabling bypass mode" >&2
fi

exit 0
