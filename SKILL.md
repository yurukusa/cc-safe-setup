---
name: cc-safe-setup
description: Safety hooks for Claude Code — 667 pre-built hooks that prevent file deletion, credential leaks, git disasters, and token waste during autonomous AI coding sessions. 9,200+ tests. Install with npx cc-safe-setup.
---

# cc-safe-setup

Safety-first configuration for Claude Code. Prevents the accidents that happen when AI writes code autonomously.

## What it does

Installs pre-built safety hooks into your Claude Code environment. These hooks run automatically before/after tool calls to block dangerous operations.

**Categories:**
- **File protection**: Block `rm -rf`, prevent overwriting files outside project
- **Git safety**: Prevent force-push to main, block `reset --hard`
- **Credential guards**: Stop `.env` files from being committed or read by AI
- **Token optimization**: Warn on large file reads, limit subagent spawning
- **Quality gates**: Detect lazy rewrites, verify claims before committing

## Quick start

```bash
npx cc-safe-setup
```

This runs an interactive wizard that configures hooks based on your risk profile.

## Install individual hooks

```bash
npx cc-safe-setup --install-example large-read-guard
npx cc-safe-setup --install-example prevent-rm-rf
npx cc-safe-setup --install-example git-force-push-block
```

## Why hooks instead of CLAUDE.md rules

Rules in CLAUDE.md are suggestions — Claude can forget them. Hooks are enforced at the system level. A hook that blocks `rm -rf` cannot be overridden by the AI.

From 800+ hours of autonomous operation: the hooks that matter most are the ones you don't notice until something goes wrong.

## Resources

- Repository: https://github.com/yurukusa/cc-safe-setup
- Hook Selector (find hooks for your setup): https://yurukusa.github.io/cc-safe-setup/hook-selector.html
- Token Checkup (diagnose waste): https://yurukusa.github.io/cc-safe-setup/token-checkup.html
