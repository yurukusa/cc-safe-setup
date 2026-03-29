#!/bin/bash
# notify-waiting.sh — Desktop notification when Claude needs input
#
# Solves: Multiple sessions running, don't know which one is blocked
#
# GitHub Issue: #36885
#
# Usage: Add to settings.json as a Notification hook
#
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/notify-waiting.sh" }]
#     }]
#   }
# }

# Linux (notify-send) — skip on WSL2 where D-Bus may not be running
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
if command -v notify-send &>/dev/null && [ -z "$WSL_DISTRO_NAME" ]; then
    notify-send "Claude Code" "Waiting for your input" --urgency=normal 2>/dev/null && exit 0
fi

# macOS (osascript)
if command -v osascript &>/dev/null; then
    osascript -e 'display notification "Waiting for your input" with title "Claude Code"'
    exit 0
fi

# Windows/WSL (PowerShell toast)
if command -v powershell.exe &>/dev/null; then
    powershell.exe -Command "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null; \$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02); \$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('Claude Code')) | Out-Null; \$xml.GetElementsByTagName('text')[1].AppendChild(\$xml.CreateTextNode('Waiting for your input')) | Out-Null; [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show([Windows.UI.Notifications.ToastNotification]::new(\$xml))" 2>/dev/null
    exit 0
fi

exit 0
