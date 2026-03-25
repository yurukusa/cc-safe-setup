# Cookbook — cc-safe-setup Recipes

Real-world recipes for common safety scenarios. Each recipe is a single command.

## Getting Started

| I want to... | Command |
|---|---|
| Install basic safety | `npx cc-safe-setup` |
| Maximum protection | `npx cc-safe-setup --shield` |
| Check my setup | `npx cc-safe-setup --doctor` |
| See my safety score | `npx cc-safe-setup --audit` |

## Blocking Dangerous Commands

### Block rm -rf on home/root
Already included in the default install. To verify:
```bash
npx cc-safe-setup --simulate "rm -rf ~"
# Expected: BLOCKED
```

### Block database wipes
```bash
npx cc-safe-setup --install-example block-database-wipe
```
Blocks: `prisma migrate reset`, `rails db:drop`, `DROP TABLE`, etc.

### Block npm publish accidents
```bash
npx cc-safe-setup --install-example npm-publish-guard
```

## Auto-Approving Safe Commands

### Approve read-only commands (cat, ls, grep)
```bash
npx cc-safe-setup --install-example auto-approve-readonly
```

### Approve test runners
```bash
npx cc-safe-setup --install-example auto-approve-test
```
Covers: `npm test`, `pytest`, `go test`, `cargo test`, `jest`, `vitest`

### Approve git read commands (status, log, diff)
```bash
npx cc-safe-setup --install-example auto-approve-git-read
```

## File Protection

### Protect .env files from edits
```bash
npx cc-safe-setup --protect .env
```

### Protect CLAUDE.md from unauthorized changes
```bash
npx cc-safe-setup --install-example protect-claudemd
```

### Protect dotfiles (~/.bashrc, ~/.aws/)
```bash
npx cc-safe-setup --install-example protect-dotfiles
```

## YAML Rules (No Coding)

Write rules in YAML, compile to hooks:

```yaml
# rules.yaml
- block: "rm -rf on root"
  pattern: "rm\s+-rf\s+(\/$|~)"

- approve: "read-only commands"
  commands: [cat, ls, grep, head, tail]

- protect: ".env"
```

```bash
npx cc-safe-setup --rules rules.yaml
```

## Monitoring & Recovery

### Auto-save checkpoint before compaction
```bash
npx cc-safe-setup --install-example auto-compact-prep
```

### Track context window usage
```bash
npx cc-safe-setup --install-example compact-reminder
```

### Fix hook permissions on Windows/plugins
```bash
npx cc-safe-setup --install-example hook-permission-fixer
```

### Prevent tool call loops
```bash
npx cc-safe-setup --install-example response-budget-guard
```

## Diagnosing Problems

### Why isn't my hook working?
```bash
npx cc-safe-setup --doctor
```
Checks: jq, settings.json, file existence, permissions, shebangs, exit codes.

### Test a specific hook
```bash
npx cc-safe-setup --test-hook destructive-guard
```

### Preview how hooks react to a command
```bash
npx cc-safe-setup --simulate "git push --force origin main"
```

## Web Tools

All browser-based, nothing leaves your machine:

- [Safety Hub](https://yurukusa.github.io/cc-safe-setup/hub.html) — All 23 tools
- [Validator](https://yurukusa.github.io/cc-safe-setup/validator.html) — Paste settings.json, get score
- [Permission Checker](https://yurukusa.github.io/cc-safe-setup/permission-checker.html) — Find broken paths
- [Playground](https://yurukusa.github.io/cc-safe-setup/playground.html) — Write and test hooks
- [Hook Builder](https://yurukusa.github.io/cc-safe-setup/builder.html) — Generate hooks from English

## 27. Bypass Protected Directory Prompts (PermissionRequest)

PreToolUse hooks can't bypass built-in protected-directory checks — they run *before* those checks. Use PermissionRequest instead:

```bash
npx cc-safe-setup --install-example allow-git-hooks-dir
```

Or manually: create a PermissionRequest hook that outputs `permissionDecision: "allow"`. See [Troubleshooting](TROUBLESHOOTING.md#pretooluse-allow-doesnt-bypass-protected-directory-prompts) for details.

## Further Reading

- [Getting Started](https://yurukusa.github.io/cc-safe-setup/getting-started.html)
- [Common Mistakes](https://yurukusa.github.io/cc-safe-setup/common-mistakes.html)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Settings Reference](SETTINGS_REFERENCE.md)
