#!/bin/bash
# temp-file-cleanup-stop.sh — Clean up tmpclaude-* files on session end
#
# Solves: Claude Code creates tmpclaude-{hash}-cwd temporary
#         files in the working directory but doesn't clean them
#         up after the session ends (#17720). These accumulate
#         over time and clutter the project.
#
# How it works: On Stop event, finds and removes all
#   tmpclaude-*-cwd files in the current directory and /tmp.
#   Only removes files matching the exact pattern to avoid
#   deleting user files.
#
# TRIGGER: Stop
# MATCHER: ""

set -euo pipefail

# Clean up tmpclaude-* files in current directory
find . -maxdepth 1 -name "tmpclaude-*-cwd" -type f -delete 2>/dev/null || true

# Also clean up in /tmp
find /tmp -maxdepth 1 -name "tmpclaude-*" -type f -mmin +60 -delete 2>/dev/null || true

# Clean up any .claude-tmp-* files too
find . -maxdepth 1 -name ".claude-tmp-*" -type f -delete 2>/dev/null || true

exit 0
