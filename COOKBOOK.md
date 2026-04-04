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

## Credential Protection

Block credential hunting commands (env scanning, file searches for tokens):

```bash
npx cc-safe-setup --install-example credential-exfil-guard
```

Blocks: `env | grep -i token`, `find / -name *.pem`, `cat ~/.ssh/id_rsa`, `cat ~/.aws/credentials`.

## Extra rm Protection

Add a second layer of rm protection beyond destructive-guard:

```bash
npx cc-safe-setup --install-example rm-safety-net
```

Blocks rm -rf on any non-safe path (only allows node_modules, dist, build, /tmp, __pycache__).

## Auto Mode False Positive Fix

Stop the safety classifier from blocking read-only commands:

```bash
npx cc-safe-setup --install-example auto-mode-safe-commands
```

Auto-approves: cat, grep, git status, ls, find, jq, curl GET, echo.

## Compound Command Auto-Approve

Stop permission prompts for `cd /path && git log`:

```bash
npx cc-safe-setup --install-example compound-command-allow
```

Splits compound commands and checks each component. Approves when all are safe.

## Secret Leak Prevention (Write/Edit)

Block secrets from being written into source files:

```bash
npx cc-safe-setup --install-example write-secret-guard
```

Detects AWS, GitHub, OpenAI, Anthropic, Slack, Stripe, Google keys + PEM + database URLs. Allows .env.example and test files.

## Permission Audit Log

Log every tool call for debugging permission rules:

```bash
npx cc-safe-setup --install-example permission-audit-log
```

Writes JSONL to `~/.claude/tool-usage.jsonl`. Analyze with `cat ~/.claude/tool-usage.jsonl | jq -s 'group_by(.tool) | map({tool: .[0].tool, count: length})'`.

## Classifier Fallback

Auto-approve read-only commands when Auto Mode's classifier is unavailable:

```bash
npx cc-safe-setup --install-example classifier-fallback-allow
```

PermissionRequest hook that approves cat, ls, grep, git read-only when the classifier can't respond.

## Block Reading Credential Files

Prevent the agent from displaying tokens in conversations by reading package manager credential files:

```bash
npx cc-safe-setup --install-example credential-file-cat-guard
```

Blocks `cat`, `head`, `tail`, `grep` on `~/.netrc`, `~/.npmrc`, `~/.cargo/credentials`, `~/.docker/config.json`, `~/.kube/config`, and more. Complements `credential-exfil-guard` which blocks hunting patterns. See [#34819](https://github.com/anthropics/claude-code/issues/34819).

## Require Tests Before Push

Block `git push` to protected branches unless tests have passed in the current session:

```bash
npx cc-safe-setup --install-example push-requires-test-pass
npx cc-safe-setup --install-example push-requires-test-pass-record
```

Two-hook system: the PostToolUse `record` hook detects successful test runs (`npm test`, `pytest`, `cargo test`, etc.) and saves a timestamp. The PreToolUse hook blocks push to main/master/production if no recent test pass exists (30-minute window). See [#36673](https://github.com/anthropics/claude-code/issues/36673).

## Recipe: Protect CI/CD Pipelines

```bash
npx cc-safe-setup --install-example github-actions-secret-guard
npx cc-safe-setup --install-example ci-workflow-guard
npx cc-safe-setup --install-example gitops-drift-guard
```

Three-hook system: `github-actions-secret-guard` (PostToolUse) detects hardcoded secrets in workflow files. `ci-workflow-guard` (PostToolUse) flags `--no-verify`, remote script execution, and broad write permissions. `gitops-drift-guard` (PreToolUse) warns when editing infrastructure files on protected branches.

## Recipe: Kubernetes Production Safety

```bash
npx cc-safe-setup --install-example k8s-production-guard
# Set production contexts/namespaces:
export CC_K8S_PROD_CONTEXTS="prod:production"
export CC_K8S_PROD_NAMESPACES="production:prod"
```

Blocks `kubectl delete`, `scale --replicas=0`, `drain`, and `helm uninstall` on production namespaces/contexts. Safe operations (get, logs, describe) are always allowed.

## Recipe: MCP Server Allowlist

```bash
npx cc-safe-setup --install-example mcp-server-allowlist
npx cc-safe-setup --install-example mcp-tool-audit-log
export CC_MCP_ALLOWED="github:filesystem:memory"
```

Only allows MCP tool calls from whitelisted servers. Blocks calls from unknown/synced servers that may cause OOM crashes ([#20412](https://github.com/anthropics/claude-code/issues/20412)). The audit log records all MCP tool calls for security review (OWASP MCP09 compliance).

## Recipe: Role-Based Agent Teams

```bash
npx cc-safe-setup --install-example role-tool-guard
echo "pm" > .claude/current-role.txt
```

Restricts tools based on agent role. PM can only read and delegate (no Edit/Write/Bash). Architect can design but not execute. Reviewer is read-only. Developer has full access. Switch roles: `echo "developer" > .claude/current-role.txt`. See [#40425](https://github.com/anthropics/claude-code/issues/40425).

## Recipe: Fix git show --no-stat Bug

Claude Code frequently runs `git show <ref> --no-stat`, which fails because `--no-stat` is not a valid git-show flag. This wastes context on error output. The hook silently rewrites the command.

```bash
npx cc-safe-setup --install-example git-show-flag-sanitizer
```

Install in `.claude/settings.json` as a PreToolUse hook with matcher `Bash`. The hook detects `git show` + `--no-stat`, strips the invalid flag, and returns the corrected command via `updatedInput`. See [#13071](https://github.com/anthropics/claude-code/issues/13071).

## Recipe: Diagnose Token Consumption

If your Max Plan 5-hour limit is exhausting too fast, install these two hooks to track what's consuming tokens:

```bash
# Log every prompt with timestamps
npx cc-safe-setup --install-example prompt-usage-logger

# Alert when auto-compaction fires
npx cc-safe-setup --install-example compact-alert-notification
```

After a session, check `/tmp/claude-usage-log.txt` for prompt frequency and `/tmp/claude-compact-log.txt` for compaction count. If you see 3+ compactions per session, the compact-rebuild cycle is a major token sink — use manual `/compact` before the threshold.

Quick wins: reduce MCP servers (`claude mcp list`), use `offset`/`limit` on large file reads, trim CLAUDE.md to essentials. If on v2.1.89+, set `"ENABLE_TOOL_SEARCH": "false"` in settings.json `env` to prevent Deferred Tool Loading from breaking the cache prefix ([#41617](https://github.com/anthropics/claude-code/issues/41617)). See also [#41249](https://github.com/anthropics/claude-code/issues/41249), [#41788](https://github.com/anthropics/claude-code/issues/41788), [#40524](https://github.com/anthropics/claude-code/issues/40524).

## Recipe: Protect Session Data

Back up session JSONL files on every start (protects against silent deletion):

```bash
npx cc-safe-setup --install-example session-backup-on-start
```

Keeps last 5 timestamped backups in `~/.claude/session-backups/`. Restore with `cp`. See [#41874](https://github.com/anthropics/claude-code/issues/41874).

Back up the full transcript before compaction (protects against rate-limit data loss):

```bash
npx cc-safe-setup --install-example pre-compact-transcript-backup
```

Keeps last 3 backups in `~/.claude/compact-backups/`. If compaction fails and your transcript is corrupted, restore from the backup. See [#40352](https://github.com/anthropics/claude-code/issues/40352).

## Recipe: Disable Auto-Compaction

Power users who manage context manually can block auto-compaction entirely:

```bash
npx cc-safe-setup --install-example compact-blocker
```

Install as a PreCompact hook (no matcher needed). Exit code 2 blocks compaction. For conditional control, add a guard: `[ -f /tmp/allow-compact ] && exit 0`. See [#6689](https://github.com/anthropics/claude-code/issues/6689).

## Recipe: WebFetch Domain Allowlist

`WebFetch(domain:*)` in settings.json fails in sandbox mode. This hook auto-approves WebFetch requests by domain:

```bash
npx cc-safe-setup --install-example webfetch-domain-allow
```

Install as a PreToolUse hook with matcher `WebFetch`. By default allows all domains. Set `CC_WEBFETCH_ALLOW_DOMAINS=github.com,docs.anthropic.com` for specific domains. See [#9329](https://github.com/anthropics/claude-code/issues/9329).

## Further Reading

- [Getting Started](https://yurukusa.github.io/cc-safe-setup/getting-started.html)
- [Common Mistakes](https://yurukusa.github.io/cc-safe-setup/common-mistakes.html)
- [Auto-Approve Guide](https://yurukusa.github.io/cc-safe-setup/auto-approve-guide.html)
- [Credential Protection](https://yurukusa.github.io/cc-safe-setup/prevent-credential-leak.html)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Settings Reference](SETTINGS_REFERENCE.md)
- **[Hook Design Guide (Zenn Book)](https://zenn.dev/yurukusa/books/6076c23b1cb18b)** — 14 chapters on hook design patterns, testing, and real incident postmortems. Chapter 3 free.
