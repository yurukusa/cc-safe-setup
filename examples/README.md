# Example Hooks

914 installable hooks. Each solves a real problem from GitHub Issues or autonomous
operation. Covered by the 278 test files in [`tests/`](../tests) — 277 shell, one Python.
(Counted 2026-08-31.)

```bash
npx github:yurukusa/cc-safe-setup --install-example <name>   # install one
npx github:yurukusa/cc-safe-setup --examples                  # list all
npx github:yurukusa/cc-safe-setup --examples safety           # filter by category
npx github:yurukusa/cc-safe-setup --shield                    # install recommended set
```

## Categories

| Category | Hooks | Of which can refuse a call |
|----------|------:|---------------------------:|
| Safety Guards | 318 | 140 |
| Auto-Approve | 35 | 18 |
| Quality | 174 | 13 |
| Agent Controls | 15 | 9 |
| Monitoring | 28 | 3 |
| Recovery | 32 | 2 |
| UX | 51 | 16 |
| Other | 2 | 0 |
| (uncategorised) | 259 | 118 |
| **total** | **914** | **319** |

"Can refuse" means the script contains `exit 2`, a permission decision,
`"decision": "block"` or `"deny"` on some path. The other 595 warn, count or log — useful,
but they cannot stop a tool call, whatever the filename suggests. (Of those 595, 591 have
no refusal at all; 4 end with a computed exit code such as `exit "$RC"` and have to be
opened to tell.) To check the hooks you already rely on, list the ones with no literal
refusal in them:

```bash
grep -L -E 'exit 2|permissionDecision|"decision": *"block"|"deny"' "$HOME"/.claude/hooks/*.sh
```

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

## Token Optimization

Using too many tokens? These hooks help monitor and reduce consumption:

- **`token-budget-guard`** — Alert when session exceeds token budget
- **`large-read-guard`** — Block reading files over 1000 lines
- **`context-monitor`** — Track context window usage

For a complete guide: [Token Book](https://zenn.dev/yurukusa/books/token-savings-guide) — cut token consumption in half with templates and measured data (¥2,500, chapter 1 free). Or try the [free diagnostic](https://yurukusa.github.io/cc-safe-setup/token-checkup.html).

## Write Your Own

See [CONTRIBUTING.md](../CONTRIBUTING.md).
