# Example Hooks

658 installable hooks. Each solves a real problem from GitHub Issues or autonomous operation. 14,096 tests.

```bash
npx cc-safe-setup --install-example <name>   # install one
npx cc-safe-setup --examples                  # list all
npx cc-safe-setup --examples safety           # filter by category
npx cc-safe-setup --shield                    # install recommended set
```

## Categories

| Category | Count | Examples |
|----------|-------|---------|
| Destructive Command Prevention | 14 | `destructive-guard`, `branch-guard`, `no-sudo-guard`, `symlink-guard`, `shell-wrapper-guard`, `compound-inject-guard` |
| Data Protection | 5 | `block-database-wipe`, `secret-guard`, `hardcoded-secret-detector` |
| Git Safety | 11 | `git-config-guard`, `no-verify-blocker`, `push-requires-test-pass` |
| Auto-Approve (PreToolUse) | 11 | `auto-approve-readonly`, `auto-approve-build`, `auto-approve-docker` |
| Auto-Approve (PermissionRequest) | 7 | `allow-git-hooks-dir`, `allow-protected-dirs`, `edit-always-allow` |
| Code Quality | 10 | `syntax-check`, `diff-size-guard`, `test-deletion-guard` |
| Security | 10 | `credential-file-cat-guard`, `credential-exfil-guard`, `prompt-injection-guard` |
| Deploy | 4 | `deploy-guard`, `no-deploy-friday`, `work-hours-guard` |
| Monitoring & Cost | 14 | `context-monitor`, `cost-tracker`, `loop-detector`, `edit-error-counter`, `dotenv-watch` |
| Utility | 20 | `comment-strip`, `session-handoff`, `auto-checkpoint`, `edit-retry-loop-guard`, `direnv-auto-reload`, `pre-compact-checkpoint` |

## Popular Hooks

- **`auto-approve-readonly`** — Skip prompts for `cat`, `ls`, `grep`, `git status`
- **`destructive-guard`** — Block `rm -rf`, `git reset --hard`
- **`credential-file-cat-guard`** — Block reading `.netrc`, `.npmrc`, `.cargo/credentials`
- **`push-requires-test-pass`** — Block `git push main` without passing tests
- **`context-monitor`** — Warn at 40/25/20/15% context remaining

## Guides

- [Auto-Approve Guide](https://yurukusa.github.io/cc-safe-setup/auto-approve-guide.html)
- [Credential Protection](https://yurukusa.github.io/cc-safe-setup/prevent-credential-leak.html)
- [OWASP MCP Top 10 Defense](https://yurukusa.github.io/cc-safe-setup/owasp-mcp-hooks.html)
- [COOKBOOK](../COOKBOOK.md)

## Write Your Own

See [CONTRIBUTING.md](../CONTRIBUTING.md).
