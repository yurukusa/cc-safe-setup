#!/bin/bash
# terminal-state-restore — restore terminal to clean state on session exit
# Fixes: bracketed paste mode, application cursor keys, cursor visibility,
#        line wrapping, Kitty keyboard protocol left enabled after exit.
# Event: Notification (matcher: "stop")
# Related: https://github.com/anthropics/claude-code/issues/39272

# Reset bracketed paste mode
printf '\e[?2004l'
# Reset application cursor keys to normal mode
printf '\e[?1l'
# Ensure cursor is visible
printf '\e[?25h'
# Re-enable line wrapping
printf '\e[?7h'
# Disable Kitty keyboard protocol (if enabled)
printf '\e[>0u' 2>/dev/null
# Reset character set to default
printf '\e(B'
# Restore default SGR (color/style reset)
printf '\e[0m'

exit 0
