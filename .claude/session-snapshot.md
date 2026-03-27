# Session Snapshot (auto-generated)
Updated: 2026-03-28T02:18:00+09:00

## Git
- Branch: `main`
- Uncommitted changes: 1 file(s)
```
 M .claude/session-snapshot.md
```
- Last commit: 854a404 feat: add session-start-safety-check — warn about uncommitted changes (#34327) New hook #361: SessionStart hook that checks for: - Uncommitted changes (suggests git stash) - Unpushed commits (suggests git push) - Existing stashes (informational) Prevents data loss from destructive git commands on session startup. 3 new tests. 4,775→4,780. Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>

## Recent Files
```
./.claude/session-snapshot.md
./.claude/pre-compact-checkpoint.md
./test.sh
./examples/session-start-safety-check.sh
./examples/multiline-command-approver.sh
./examples/hook-tamper-guard.sh
./README.md
./examples/dependency-install-guard.sh
./examples/temp-file-cleanup.sh
./examples/test-exit-code-verify.sh
```

