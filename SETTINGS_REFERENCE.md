# Claude Code settings.json Reference

Everything you can put in `~/.claude/settings.json`, documented from real usage and GitHub Issues.

## File Locations

| File | Scope | Precedence |
|------|-------|------------|
| `~/.claude/settings.json` | All projects (user-level) | Lowest |
| `.claude/settings.json` | Current project | Overrides user |
| `.claude/settings.local.json` | Current project (gitignored) | Highest |

## Permissions

### allow

Commands that auto-execute without prompting.

```json
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "Bash(npm test:*)",
      "Bash(npm run:*)",
      "Read(*)",
      "Edit(*)",
      "Write(*)",
      "Glob(*)",
      "Grep(*)"
    ]
  }
}
```

**Pattern syntax:**
- `Tool(pattern)` — match tool name and argument pattern
- `*` — wildcard (matches anything)
- `:` — separator between command and arguments
- `Bash(git:*)` — any command starting with `git`
- `Bash(git status:*)` — `git status` with any args
- `Bash(*)` — all bash commands (dangerous — use with hooks)

**Known limitations (as of v2.1.81):**
- Compound commands don't match: `Bash(git:*)` won't match `cd /path && git log` ([#30519](https://github.com/anthropics/claude-code/issues/30519), [#16561](https://github.com/anthropics/claude-code/issues/16561))
- "Always Allow" saves exact strings, not patterns ([#6850](https://github.com/anthropics/claude-code/issues/6850))
- User-level settings may not apply at project level ([#5140](https://github.com/anthropics/claude-code/issues/5140))
- **Workaround:** Use `compound-command-approver` hook: `npx cc-safe-setup --install-example compound-command-approver`

### deny

Commands that are always blocked.

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(git push --force:*)",
      "Bash(sudo:*)"
    ]
  }
}
```

**Note:** Deny rules have the same compound-command limitation as allow rules. Hooks are more reliable for blocking.

## Hooks

### Structure

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/my-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### Hook Events

| Event | When | Use Case |
|-------|------|----------|
| `PreToolUse` | Before tool executes | Block/modify commands |
| `PostToolUse` | After tool executes | Validate output, check syntax |
| `Stop` | Session ends | Log data, notify |
| `UserPromptSubmit` | User presses Enter | Validate prompts |
| `Notification` | Claude shows notification | Custom alerts |
| `PreCompact` | Before context compaction | Save state |
| `SessionStart` | Session begins | Initialize |
| `SessionEnd` | Session ends | Cleanup |

### Matcher Values

| Matcher | Matches |
|---------|---------|
| `"Bash"` | Bash tool only |
| `"Edit\|Write"` | Edit or Write tool |
| `"Read"` | Read tool only |
| `""` (empty) | All tools |

### Hook Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Allow (or no opinion) |
| 2 | **Block** — tool call cancelled |
| Other | Error (treated as allow) |

### Hook Input (stdin JSON)

**PreToolUse/PostToolUse:**
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git push origin main"
  }
}
```

**For Edit/Write:**
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.py",
    "old_string": "...",
    "new_string": "..."
  }
}
```

**Stop:**
```json
{
  "stop_reason": "user",
  "hook_event_name": "Stop"
}
```

### Hook Output (stdout JSON)

**Auto-approve:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "auto-approved by hook"
  }
}
```

**Modify input:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": {
      "command": "modified command here"
    }
  }
}
```

## defaultMode

```json
{
  "defaultMode": "default"
}
```

| Mode | Behavior |
|------|----------|
| `"default"` | Prompt for unrecognized commands |
| `"dontAsk"` | Auto-approve everything (hooks still run) |
| `"bypassPermissions"` | Skip everything including hooks (dangerous) |

**Recommendation:** Use `"dontAsk"` + hooks instead of `"bypassPermissions"`.

## Common Configurations

### Minimal Safe Setup

```json
{
  "permissions": {
    "allow": ["Read(*)", "Glob(*)", "Grep(*)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/destructive-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/branch-guard.sh" }
        ]
      }
    ]
  }
}
```

### Autonomous Operation

```json
{
  "defaultMode": "dontAsk",
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)", "Glob(*)", "Grep(*)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/destructive-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/branch-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/secret-guard.sh" },
          { "type": "command", "command": "~/.claude/hooks/compound-command-approver.sh" }
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
    ]
  }
}
```

### Generate This Automatically

```bash
npx cc-safe-setup        # Install hooks
npx cc-safe-setup --audit  # Check your score
npx cc-safe-setup --doctor # Diagnose issues
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Hooks don't fire | Not registered in settings.json | `npx cc-safe-setup` |
| Hooks don't block | Wrong exit code (not 2) | Check `echo $?` after test |
| "jq: command not found" | jq not installed | `brew install jq` / `apt install jq` |
| Hook permission denied | Not executable | `chmod +x ~/.claude/hooks/*.sh` |
| Compound commands prompt | Permission system limitation | Install `compound-command-approver` |
| "Always Allow" doesn't stick | Saves exact string, not pattern | Use hooks instead |

Run `npx cc-safe-setup --doctor` for automated diagnosis.

## Resources

- [Official Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [COOKBOOK.md](https://github.com/yurukusa/claude-code-hooks/blob/main/COOKBOOK.md) — 20 hook recipes
- [Migration Guide](MIGRATION.md) — from permissions to hooks
- [Ecosystem Comparison](https://yurukusa.github.io/cc-safe-setup/ecosystem.html) — all hook projects
- [Token Checkup](https://yurukusa.github.io/cc-safe-setup/token-checkup.html) — free 30-second token diagnostic
- [Token Book](https://zenn.dev/yurukusa/books/token-savings-guide) — cut your token consumption in half (¥2,500, chapter 1 free)
