Updated: 2026-03-26T08:02:27+09:00
main
.claude/session-snapshot.md
cc-safe-setup-export.json
none
18f2b1b checkpoint: auto-save 08:01:15
659a71c checkpoint: auto-save 07:43:19
7b34011 checkpoint: auto-save 07:42:01
187accb feat: PermissionRequest hook support + execution order docs - First PermissionRequest example: allow-git-hooks-dir.sh - TROUBLESHOOTING: PreToolUse vs PermissionRequest execution order - COOKBOOK: Recipe #27 bypass protected directory prompts - 6 new tests (996 total), 331 examples Insight from anthropics/claude-code#37836: PreToolUse runs before built-in protected-dir checks, so permissionDecision allow gets overridden. PermissionRequest runs after, so it works. Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
e05fb2d checkpoint: auto-save 07:26:28
50
---
*Read this file after compaction to restore context.*
