# Troubleshooting Claude Code Hooks

Your hook isn't working. Here's how to fix it, starting with the most common causes.

## Quick Diagnosis

```bash
npx cc-safe-setup --doctor
```

This checks jq, settings.json, file permissions, shebangs, and common misconfigurations. If it says "All checks passed" but hooks still don't fire, read on.

## "Hook doesn't block anything"

### 1. Did you restart Claude Code?

Hooks are loaded on startup. After installing or modifying hooks, close Claude Code completely and reopen it.

### 2. Is the hook registered in settings.json?

```bash
cat ~/.claude/settings.json | jq '.hooks'
```

You should see your hook's path under the correct trigger. If not:

```bash
npx cc-safe-setup  # Re-registers all hooks
```

### 3. Is the hook file executable?

```bash
ls -la ~/.claude/hooks/your-hook.sh
# Should show -rwxr-xr-x
```

Fix: `chmod +x ~/.claude/hooks/your-hook.sh`

### 4. Is jq installed?

Most hooks use jq to parse JSON input.

```bash
jq --version
# Should print: jq-1.x
```

Install: `brew install jq` (macOS) / `apt install jq` (Linux/WSL)

### 5. Does the hook work manually?

Test it outside Claude Code:

```bash
echo '{"tool_input":{"command":"rm -rf /"}}' | bash ~/.claude/hooks/destructive-guard.sh
echo $?
# Should print: 2 (blocked)
```

If exit code is 0, the hook isn't matching the pattern.

### 6. Wrong exit code

| Exit Code | Meaning |
|-----------|---------|
| **0** | Allow (or no opinion) |
| **2** | Block — the only code that stops execution |
| **1** | Error (treated as allow, not block!) |

Common mistake: using `exit 1` instead of `exit 2` to block. Only exit 2 blocks.

## "Hook blocks everything"

### 1. Overly broad grep pattern

```bash
# BAD: matches ANY command containing "rm"
grep -q 'rm'

# GOOD: matches only rm with -rf flags
grep -qE 'rm\s+(-[rf]+\s+)*/'
```

### 2. Missing empty-input guard

Every hook should handle empty input:

```bash
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0  # ← This line is critical
```

Without this, the hook may exit 2 on tools that don't have `.tool_input.command` (like Read or Glob).

### 3. Wrong matcher

If your hook is for Bash commands but the matcher is empty, it runs on every tool call:

```json
{"matcher": "Bash"}      ← Correct: only Bash commands
{"matcher": ""}           ← Runs on EVERY tool (Read, Edit, Glob, etc.)
```

## "Hook fires but doesn't auto-approve"

### 1. JSON output format is wrong

Auto-approve requires exact JSON structure:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "your reason"
  }
}
```

Missing any field = permission system ignores it.

### 2. jq output is going to stderr

```bash
# BAD: output goes to stderr
jq -n '...' >&2

# GOOD: output goes to stdout
jq -n '...'
```

Auto-approve JSON must go to stdout.

## "PreToolUse allow doesn't bypass protected directory prompts"

This is expected behavior, not a bug.

**Execution order:**
1. PreToolUse hooks run
2. Built-in protected-directory checks run (`.claude/`, `.git/`, etc.)
3. PermissionRequest hooks run

PreToolUse's `permissionDecision: "allow"` gets overridden by the built-in checks in step 2. To bypass protected directory prompts, use **PermissionRequest** hooks instead:

```bash
#!/bin/bash
# Save as: ~/.claude/hooks/allow-protected-dir.sh
# Trigger: PermissionRequest (not PreToolUse)
INPUT=$(cat)
PATH_TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // empty')

# Allow writes to a specific protected directory
if echo "$PATH_TARGET" | grep -q '/my-project/.git/hooks'; then
  jq -n '{hookSpecificOutput: {hookEventName: "PermissionRequest", permissionDecision: "allow", permissionDecisionReason: "Allowed: git hooks directory"}}'
  exit 0
fi
exit 0
```

**Rule of thumb:** PreToolUse = block dangerous actions. PermissionRequest = allow trusted actions that trigger built-in prompts.

## "PermissionRequest hooks don't fire in `-p` mode"

**Known limitation** ([#35646](https://github.com/anthropics/claude-code/issues/35646)): In headless/pipe mode (`claude -p`), the protected-directory check short-circuits *before* PermissionRequest hooks fire. This means:

| Mode | PermissionRequest fires? | Hook workaround works? |
|------|-------------------------|----------------------|
| Interactive (`claude`) | ✅ Yes | ✅ Yes |
| Interactive + bypassPermissions | ✅ Yes | ✅ Yes |
| Pipe mode (`claude -p`) | ❌ No | ❌ No |
| Pipe + `--dangerously-skip-permissions` | ❌ No | ❌ No |

**Workaround:** Currently none for `-p` mode. If your automation needs to write to `.claude/`, use interactive mode with hooks instead. This is a Claude Code core issue — the fix requires the harness to route protected-dir checks through PermissionRequest in all modes.

## "Permission prompts still appear for compound commands"

This is a known Claude Code limitation, not a hook issue. `Bash(git:*)` doesn't match `cd /path && git log`.

Fix:

```bash
npx cc-safe-setup --install-example compound-command-approver
```

## "Hooks slow down Claude Code"

### 1. Check execution time

```bash
npx cc-safe-setup --install-example hook-debug-wrapper
# Then wrap your slow hook to see timing
```

Hooks should complete in <50ms. If a hook takes >200ms, it's noticeable.

### 2. Too many hooks on empty matcher

Hooks with `"matcher": ""` run on every single tool call. Move heavy checks to specific matchers:

```json
{"matcher": "Bash"}        ← Only when Bash runs
{"matcher": "Edit|Write"}  ← Only when files are edited
```

### 3. Use --lint to find issues

```bash
npx cc-safe-setup --lint
```

Reports performance warnings and configuration issues.

## "Hooks work locally but not for teammates"

### 1. Compare settings

```bash
npx cc-safe-setup --diff teammate-settings.json
```

Shows exactly what's different between your setups.

### 2. Export and share

```bash
npx cc-safe-setup --export   # Creates cc-safe-setup-export.json
# Send to teammate
npx cc-safe-setup --import cc-safe-setup-export.json
```

### 3. Different jq versions

Some hooks use jq features not available in older versions. Check: `jq --version`

## "Hooks run but don't log"

Hooks write to stderr for user-visible messages. For persistent logging:

```bash
# Add to your hook
LOG="$HOME/.claude/blocked-commands.log"
echo "[$(date -Iseconds)] BLOCKED: reason | cmd: $COMMAND" >> "$LOG"
```

Then view with: `npx cc-safe-setup --watch` or `npx cc-safe-setup --stats`

## "claude -p returns empty output when Stop hook is configured"

This is a known Claude Code v2.1.83 bug ([#38651](https://github.com/anthropics/claude-code/issues/38651)), not a cc-safe-setup issue. Any Stop hook — even `true` — causes `-p` (print mode) to return empty stdout.

**Workaround:** Temporarily remove Stop hooks when using `-p` mode:

```bash
# Quick toggle: comment out Stop hooks before -p commands
npx cc-safe-setup --status  # See which hooks are active
# Manually comment out Stop hooks in ~/.claude/settings.json
# Run your -p command
# Uncomment Stop hooks after
```

This should be fixed in a future Claude Code release.

## "write-secret-guard blocks normal code"

The write-secret-guard hook may false-positive on strings that look like API keys (20+ alphanumeric characters after specific prefixes). Fix:

1. If the blocked file is a test file, rename it to include `test` in the path
2. If it's a `.env.example`, the hook should already allow it — check the filename pattern
3. For specific false positives, add an allowlist pattern to the hook

## "credential-exfil-guard blocks my grep"

The hook blocks `grep` commands that search for secret-related keywords. If you need to search for `token` or `key` in code:

```bash
# This is blocked:
env | grep -i token

# This is allowed (searching code, not environment):
grep "token" src/auth.js
```

The hook only blocks `env/printenv/set` piped to grep with secret keywords, not general file searches.

## "compound-command-allow doesn't approve my command"

The hook has a strict whitelist. If a command isn't on the list, it passes through to the normal permission system. Common misses:

- `docker` commands (not whitelisted — install `auto-approve-docker` instead)
- `pip install` (not whitelisted — install `pip-venv-guard` instead)
- Custom scripts (unknown to the whitelist)

## Token Consumption Too Fast

**Symptom**: Max Plan 5-hour limit exhausted in 1-2 hours. Same usage pattern as before.

**Diagnosis**:

```bash
# Install token tracking hooks
npx cc-safe-setup --install-example prompt-usage-logger
npx cc-safe-setup --install-example compact-alert-notification
```

After a session, check:
- `/tmp/claude-usage-log.txt` — how many prompts, how frequently
- `/tmp/claude-compact-log.txt` — how many auto-compactions fired

**Common causes**:

| Cause | Check | Fix |
|-------|-------|-----|
| Too many MCP servers | `claude mcp list` | Remove unused servers |
| Large CLAUDE.md/MEMORY.md | `wc -c CLAUDE.md` | Move reference content to separate files |
| Auto-compact cycles | compact-alert count > 3 | Use manual `/compact` before threshold |
| Large file reads | prompt-usage-log timestamps | Use `offset`/`limit` parameters |

**Related issues**: [#41249](https://github.com/anthropics/claude-code/issues/41249), [#41788](https://github.com/anthropics/claude-code/issues/41788), [#38335](https://github.com/anthropics/claude-code/issues/38335)

## Still Stuck?

1. Wrap the hook with debug wrapper: `npx cc-safe-setup --install-example hook-debug-wrapper`
2. Check `~/.claude/hook-debug.log` for detailed I/O traces
3. Run `npx cc-safe-setup --doctor` for automated checks
4. Open an issue: [cc-safe-setup issues](https://github.com/yurukusa/cc-safe-setup/issues)
