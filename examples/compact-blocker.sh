#!/bin/bash
# ================================================================
# compact-blocker.sh — Block auto-compaction entirely
# ================================================================
# PURPOSE:
#   Power users who manage context manually (file-backed plans,
#   checkpoint scripts) lose nuanced context when auto-compaction
#   fires. This hook blocks compaction via exit code 2.
#
#   For conditional blocking (e.g., only during plan mode), modify
#   the guard condition below.
#
# TRIGGER: PreCompact
# MATCHER: (none — PreCompact has no matcher)
#
# DECISION: exit 2 = block compaction
#
# See: https://github.com/anthropics/claude-code/issues/6689
# ================================================================

# Unconditional block — compaction never fires
# To make it conditional, add logic here:
#   e.g., [ -f /tmp/allow-compact ] && exit 0
echo '{"decision":"block","reason":"auto-compaction disabled by compact-blocker hook"}' >&2
exit 2
