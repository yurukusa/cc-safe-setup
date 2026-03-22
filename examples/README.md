# Example Hooks

19 hooks beyond the 8 built-in ones, organized by category.

## Quick Start

```bash
# One command — copies hook, updates settings.json, makes executable
npx cc-safe-setup --install-example block-database-wipe

# Browse all examples with categories
npx cc-safe-setup --examples
```

## Safety Guards

| Hook | Purpose | Issue |
|------|---------|-------|
| **allowlist.sh** | Block everything not explicitly approved | [#37471](https://github.com/anthropics/claude-code/issues/37471) |
| **block-database-wipe.sh** | Block migrate:fresh, DROP DATABASE, Prisma reset | [#37405](https://github.com/anthropics/claude-code/issues/37405) |
| **deploy-guard.sh** | Block deploy with uncommitted changes | [#37314](https://github.com/anthropics/claude-code/issues/37314) |
| **env-var-check.sh** | Block hardcoded API keys in export commands | |
| **git-config-guard.sh** | Block git config --global | [#37201](https://github.com/anthropics/claude-code/issues/37201) |
| **network-guard.sh** | Warn on suspicious network commands | [#37420](https://github.com/anthropics/claude-code/issues/37420) |
| **protect-dotfiles.sh** | Block changes to ~/.bashrc, ~/.aws/, ~/.ssh/ | [#37478](https://github.com/anthropics/claude-code/issues/37478) |
| **scope-guard.sh** | Block operations outside project directory | [#36233](https://github.com/anthropics/claude-code/issues/36233) |
| **test-before-push.sh** | Block git push without tests | [#36970](https://github.com/anthropics/claude-code/issues/36970) |

## Auto-Approve

| Hook | Purpose | Issue |
|------|---------|-------|
| **auto-approve-build.sh** | npm/yarn/cargo/go build, test, lint | |
| **auto-approve-docker.sh** | docker build, compose, ps, logs | |
| **auto-approve-git-read.sh** | git status/log/diff with -C flags | [#36900](https://github.com/anthropics/claude-code/issues/36900) |
| **auto-approve-python.sh** | pytest, mypy, ruff, black, isort | |
| **auto-approve-ssh.sh** | Safe SSH commands (uptime, whoami) | |

## Quality

| Hook | Purpose | Issue |
|------|---------|-------|
| **commit-message-check.sh** | Warn on non-conventional commit messages | |
| **edit-guard.sh** | Block Edit/Write to protected files | [#37210](https://github.com/anthropics/claude-code/issues/37210) |
| **enforce-tests.sh** | Warn when source changes without tests | |
| **large-file-guard.sh** | Warn when Write creates files >500KB | |

## Recovery

| Hook | Purpose | Issue |
|------|---------|-------|
| **auto-checkpoint.sh** | Auto-commit after edits (compaction protection) | [#34674](https://github.com/anthropics/claude-code/issues/34674) |
| **auto-snapshot.sh** | Save file copies before edits | [#37386](https://github.com/anthropics/claude-code/issues/37386) |

## UX

| Hook | Purpose | Issue |
|------|---------|-------|
| **notify-waiting.sh** | Desktop notification when Claude waits | |
