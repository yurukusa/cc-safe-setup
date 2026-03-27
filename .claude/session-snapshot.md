# Session Snapshot (auto-generated)
Updated: 2026-03-27T20:17:39+09:00

## Git
- Branch: `main`
- Uncommitted changes: 1 file(s)
```
 M .claude/session-snapshot.md
```
- Last commit: 9431dc7 feat: add banned-command-guard hook (solves #36413) Blocks sed -i, awk -i inplace, perl -pi — commands that edit files in-place via shell when the Edit tool should be used instead. Configurable via CC_BANNED_COMMANDS env var. Inspired by #36413 where sed from wrong CWD emptied a file. 350 hooks, 4,516 tests. 8 new tests. Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>

## Recent Files
```
./.claude/session-snapshot.md
./.claude/pre-compact-checkpoint.md
./test.sh
./examples/banned-command-guard.sh
./examples/uncommitted-discard-guard.sh
./README.md
./examples/credential-exfil-guard.sh
./examples/npm-publish-guard.sh
./examples/env-source-guard.sh
./examples/kubernetes-guard.sh
```

