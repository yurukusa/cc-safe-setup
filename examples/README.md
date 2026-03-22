# Example Hooks

Custom hooks beyond the 8 built-in ones. Copy any file to `~/.claude/hooks/` and add to `settings.json`.

| Hook | Purpose | Related Issue |
|------|---------|---------------|
| **allowlist.sh** | Block everything not explicitly approved (inverse model) | [#37471](https://github.com/anthropics/claude-code/issues/37471) |
| **auto-approve-build.sh** | Auto-approve npm/yarn/cargo/go build, test, lint | |
| **auto-approve-docker.sh** | Auto-approve docker build, compose, ps, logs | |
| **auto-approve-git-read.sh** | Auto-approve `git status/log/diff` even with `-C` flags | [#36900](https://github.com/anthropics/claude-code/issues/36900) |
| **auto-approve-python.sh** | Auto-approve pytest, mypy, ruff, black, isort | |
| **auto-approve-ssh.sh** | Auto-approve safe SSH commands (uptime, whoami) | |
| **auto-snapshot.sh** | Save file snapshots before edits (rollback protection) | [#37386](https://github.com/anthropics/claude-code/issues/37386) |
| **block-database-wipe.sh** | Block destructive DB commands (Laravel, Django, Rails) | [#37405](https://github.com/anthropics/claude-code/issues/37405) |
| **edit-guard.sh** | Block Edit/Write to protected files | [#37210](https://github.com/anthropics/claude-code/issues/37210) |
| **enforce-tests.sh** | Warn when source changes without test changes | |
| **notify-waiting.sh** | Desktop notification when Claude waits for input | |
| **protect-dotfiles.sh** | Block modifications to ~/.bashrc, ~/.aws/, ~/.ssh/ | [#37478](https://github.com/anthropics/claude-code/issues/37478) |

## Quick Start

```bash
# 1. Copy example to hooks directory
cp examples/block-database-wipe.sh ~/.claude/hooks/

# 2. Make executable
chmod +x ~/.claude/hooks/block-database-wipe.sh

# 3. Add to settings.json
# See each file's header comment for the JSON configuration
```

## List from CLI

```bash
npx cc-safe-setup --examples
```
