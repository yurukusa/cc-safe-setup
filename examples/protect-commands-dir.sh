#!/bin/bash
# protect-commands-dir.sh — Backup .claude/commands/ on session start
# TRIGGER: SessionStart  MATCHER: ""
# Born from: https://github.com/anthropics/claude-code/issues/38326
CMDS=".claude/commands"
BACKUP=".claude/commands-backup"
[ -d "$CMDS" ] || exit 0
mkdir -p "$BACKUP" 2>/dev/null
cp "$CMDS"/*.md "$BACKUP/" 2>/dev/null
COUNT=$(ls "$CMDS"/*.md 2>/dev/null | wc -l)
echo "Backed up $COUNT command files" >&2
exit 0
