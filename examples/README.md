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
| Safety Guards | 318 | 132 |
| Auto-Approve | 35 | 18 |
| Quality | 174 | 12 |
| Agent Controls | 15 | 9 |
| Monitoring | 28 | 2 |
| Recovery | 32 | 2 |
| UX | 51 | 13 |
| Other | 2 | 0 |
| (uncategorised) | 259 | 113 |
| **total** | **914** | **301** |

"Can refuse" means the script contains `exit 2`, a permission decision,
`"decision": "block"` or `"deny"` **outside a comment**. The other 613 warn, count or log —
useful, but they cannot stop a tool call, whatever the filename suggests. (Of those 613, 608
have no refusal at all; 5 end with a computed exit code such as `exit "$RC"` and have to be
opened to tell.)

**The word "outside a comment" is doing real work here.** A plain `grep` over the file counts
matches inside comments, and 18 scripts here match only there — including three whose comment
says, in so many words, that they are not blockers:

```
network-guard.sh:5         # This is a warning hook (exit 0), not a blocker (exit 2),
plan-mode-edit-guard.sh:74 # Warning only (exit 0). Change to exit 2 to block.
no-push-without-tests.sh:41 # Warning only. Change exit 0 to exit 2 to enforce.
```

So strip comments before you trust the match. To check the hooks you already rely on:

```bash
for f in "$HOME"/.claude/hooks/*.sh; do
  sed 's/#.*//' "$f" | grep -qE 'exit 2|permissionDecision|"decision": *"block"|"deny"' \
    || echo "WITNESS $f"
done
```

This is still a floor, not a census: at least one script matches only inside a *message string*
(`broad-prefix-session-trap-warner.sh`, whose only exit is `exit 0`), and `sed` cannot tell that
from a real refusal. Adjust the extension too — a hooks directory can hold `.py` and `.js`.

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
