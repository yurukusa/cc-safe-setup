# Migrating from Permissions-Only to Hooks

You've been using `permissions.allow` and `permissions.deny` to control Claude Code. It works — until it doesn't. This guide shows how to add hooks for the things permissions can't do.

## Why Migrate?

Permissions are binary: allow or deny. Hooks are programmable: inspect the command, check context, decide dynamically.

| What you want | Permissions | Hooks |
|---|---|---|
| Allow `git status` | `Bash(git status:*)` | Same, or auto-approve hook |
| Block `rm -rf /` but allow `rm -rf node_modules` | Can't — it's all or nothing | `destructive-guard.sh` checks the path |
| Block `git push --force` but allow `git push` | Can't | `branch-guard.sh` checks flags |
| Block `git add .env` but allow `git add src/` | Can't | `secret-guard.sh` checks the target |
| Auto-approve `cd /path && git log` | Can't — compound command | `cd-git-allow.sh` parses both parts |
| Warn when context is running low | Not a permission concept | `context-monitor.sh` tracks usage |

## Step 1: Audit Your Current Setup

```bash
npx cc-safe-setup --audit
```

This scores your current settings (0-100) and shows what's missing.

Or paste your `settings.json` into the [web tool](https://yurukusa.github.io/cc-safe-setup/) — no npm required.

## Step 2: Keep Your Permissions, Add Hooks

**You don't need to remove your existing permissions.** Hooks and permissions work together:

1. Permissions run first (allow/deny the tool call)
2. If allowed, PreToolUse hooks run (can block with exit 2)
3. Tool executes
4. PostToolUse hooks run (can warn about issues)

This means you can keep your working `allow` rules and layer hooks on top for the edge cases.

### Before (permissions only)

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Read(*)",
      "Edit(*)",
      "Write(*)"
    ]
  }
}
```

**Problem:** `Bash(git:*)` allows `git push --force origin main`. No way to block it without also blocking `git push origin feature-branch`.

### After (permissions + hooks)

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Read(*)",
      "Edit(*)",
      "Write(*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/destructive-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/branch-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/secret-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/comment-strip.sh" },
          { "type": "command", "command": "~/.claude/hooks/cd-git-allow.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/syntax-check.sh" }
        ]
      },
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/context-monitor.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/api-error-alert.sh" }
        ]
      }
    ]
  }
}
```

**Result:** `git push origin feature-branch` still works. `git push --force` and `git push origin main` are blocked. `rm -rf node_modules` works. `rm -rf /` is blocked. All without changing your `allow` rules.

## Step 3: Install Everything Automatically

```bash
npx cc-safe-setup
```

This creates the hook scripts and merges the config into your existing settings.json. Your current `permissions` are preserved.

## Step 4: Verify

```bash
npx cc-safe-setup --verify
```

Tests each hook with sample inputs. If something fails:

```bash
npx cc-safe-setup --doctor
```

This checks jq installation, file permissions, shebang lines, and common misconfigurations.

## Common Migration Patterns

### "I use `Bash(*)` to auto-approve everything"

You're trading speed for safety. Keep `Bash(*)` but add hooks to catch the dangerous commands:

```bash
npx cc-safe-setup
```

Now `Bash(*)` auto-approves commands, but hooks still run and block dangerous ones. Best of both worlds.

### "I use `dontAsk` mode"

Same approach. `dontAsk` skips permission prompts but **hooks still fire**. Install hooks and you're protected.

### "I use `bypassPermissions`"

**Warning:** `bypassPermissions` skips **everything** including hooks. Switch to `dontAsk` instead — same UX (no prompts) but hooks still protect you.

### "I have deny rules for specific commands"

Deny rules work but are fragile. `deny: ["Bash(rm -rf:*)"]` doesn't catch `rm -r -f` or `sudo rm -rf`. A hook can use regex to catch all variants.

You can keep your deny rules as a first line of defense and add hooks as a second layer.

## Hook Development Reference

### How hooks receive data

Hooks read JSON from stdin:

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git push origin main"
  }
}
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Allow (or no opinion) |
| 2 | **Block** — command does not execute |
| Other | Error (treated as allow) |

### Returning data

Hooks can modify the input or make permission decisions by writing JSON to stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "auto-approved by hook"
  }
}
```

### Testing a hook manually

```bash
echo '{"tool_input":{"command":"rm -rf /"}}' | bash ~/.claude/hooks/destructive-guard.sh
echo $?  # Should be 2 (blocked)
```

## Monitor Your Hooks

Watch what's being blocked in real time:

```bash
npx cc-safe-setup --watch
```

After a few sessions, generate custom hooks from your block patterns:

```bash
npx cc-safe-setup --learn
```

## Resources

- [Official Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [COOKBOOK.md](https://github.com/yurukusa/claude-code-hooks/blob/main/COOKBOOK.md) — 19 hook recipes
- [cc-safe-setup](https://github.com/yurukusa/cc-safe-setup) — automated setup
- [Web Audit Tool](https://yurukusa.github.io/cc-safe-setup/) — browser-based setup generator
