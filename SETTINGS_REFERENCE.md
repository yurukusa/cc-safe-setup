# Claude Code settings.json Reference

Everything you can put in `~/.claude/settings.json`, documented from real usage and GitHub Issues.

## File Locations

| File | Scope | Precedence |
|------|-------|------------|
| `~/.claude/settings.json` | All projects (user-level) | Lowest |
| `.claude/settings.json` | Current project | Overrides user |
| `.claude/settings.local.json` | Current project (gitignored) | Highest |

> **Project-scoped files resolve against the launch directory, not the git root — and the two do not behave the same.**
> Launching Claude Code from a subdirectory of a repo (e.g. `packages/api/` in a monorepo) silently drops
> `.claude/settings.json` from the repo root, while `.claude/settings.local.json` from that same root still applies.
> Measured on 2.1.220 (Linux/WSL2) with hooks registered only at the repo root, launching from a nested subdirectory,
> with a root launch as the control on every run:
>
> | At repo root | Launched from subdirectory | Launched from root (control) |
> |---|---|---|
> | `settings.json` only | hook does **not** fire | fires |
> | `settings.local.json` only | hook fires | fires |
> | both present | **only** the `.local` hook fires | both fire |
>
> The direction matters for safety: `settings.local.json` is the personal, gitignored file, so the copy that survives
> is the one only you have, and the copy that disappears is the committed one your whole team relies on. A `PreToolUse`
> guard shipped in `settings.json`, verified from the repo root, can be inert for every developer who runs Claude from
> a package subdirectory — with nothing in the output saying so.
>
> **Until this is fixed upstream** ([#74023](https://github.com/anthropics/claude-code/issues/74023)), launch from the
> repo root so the shared config loads:
>
> ```sh
> # ccroot: launch from the repo root so project config loads
> root="$(git rev-parse --show-toplevel 2>/dev/null)" && cd "$root"; exec claude "$@"
> ```
>
> Copying `settings.json` to `settings.local.json` also makes the hooks fire from a subdirectory, but that file is not
> the one you commit, so it is a diagnostic rather than a team fix: if your hooks start working after that copy, you
> have confirmed you are hitting this bug and not a malformed config.
>
> This installer writes to `$CLAUDE_PROJECT_DIR/.claude/settings.json` when `CLAUDE_PROJECT_DIR` is set, and to
> `~/.claude/settings.json` otherwise. The default (user-level) path is unaffected by this bug; the
> `CLAUDE_PROJECT_DIR` path is affected.

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

There are **31** hook events. This table used to list 8 of them, and described `Stop` as
"Session ends" — which is wrong, and wrong in a direction that costs you: `Stop` fires
**after every turn**, not once at the end. A cleanup or notification hook registered there
runs dozens of times per session.

**A wrong event name is not an error.** Claude Code drops the hook and says
`Unknown hook event "..." was ignored` — but only where you have to go looking for it.
Check yours:

```bash
claude doctor    # any "Unknown hook event" line means that hook never runs
```

The same output prints the authoritative list of valid names, which is where the table below
comes from. Descriptions are quoted from the official hooks reference.

**Session lifecycle**

| Event | When it fires | Use case |
|-------|---------------|----------|
| `SessionStart` | "Claude Code starts a new session or resumes an existing session" | Initialize, restore state |
| `Setup` | Start with `--init-only`, or `--init`/`--maintenance` in `-p` mode | One-time prep in CI |
| `SessionEnd` | "When a session terminates" | Cleanup, final report |

**Prompt and turn**

| Event | When it fires | Use case |
|-------|---------------|----------|
| `UserPromptSubmit` | "When you submit a prompt, before Claude processes it" | Validate or annotate prompts |
| `UserPromptExpansion` | "When a user-typed command expands into a prompt" | Gate your own slash commands |
| `Stop` | **"When Claude finishes responding"** — every turn, not once | Per-turn checks, commitments |
| `StopFailure` | "When the turn ends due to an API error" | Catch `rate_limit`, `billing_error`, `overloaded` |
| `MessageDisplay` | "While assistant message text is displayed" | Redact or annotate on screen only |

**Tools and permissions**

| Event | When it fires | Use case |
|-------|---------------|----------|
| `PreToolUse` | "Before a tool call executes. Can block it" | **Where guards belong.** Fires in every permission mode |
| `PermissionRequest` | "When a tool call needs a permission decision" | Custom approval logic — **does not fire under auto mode or bypassed permissions** |
| `PermissionDenied` | "When a tool call is denied by the auto mode classifier" | Audit what is actually being blocked |
| `PostToolUse` | "After a tool call succeeds" | Validate output, syntax-check writes |
| `PostToolUseFailure` | "After a tool call fails" | Feed the failure reason back to Claude |
| `PostToolBatch` | "After a full batch of parallel tool calls resolves" | Check a whole batch before the next model call |

**Subagents and tasks**

| Event | When it fires | Use case |
|-------|---------------|----------|
| `SubagentStart` | "When a subagent is spawned" | Count and constrain fan-out |
| `SubagentStop` | "When a subagent finishes" | Collect subagent results |
| `TaskCreated` | "When a task is being created via `TaskCreate`" | Enforce task hygiene (exit 2 blocks) |
| `TaskCompleted` | "When a task is being marked as completed" | Require evidence before "done" (exit 2 blocks) |
| `TeammateIdle` | "When an agent team teammate is about to go idle" | Keep a teammate working (exit 2 blocks) |

**Environment and config**

| Event | When it fires | Use case |
|-------|---------------|----------|
| `ConfigChange` | "When a configuration file changes during a session" | **exit 2 blocks the change** (except `policy_settings`) |
| `InstructionsLoaded` | "When a CLAUDE.md or `.claude/rules/*.md` file is loaded into context" | Verify your instructions actually loaded |
| `CwdChanged` | "When the working directory changes, for example when Claude executes a `cd` command" | Reactive environment management (direnv) |
| `DirectoryAdded` | "When a working directory is added mid-session via `/add-dir`" | Audit scope expansion |
| `FileChanged` | "When a watched file changes on disk" | React to edits; `matcher` selects filenames |
| `WorktreeCreate` | "When a worktree is being created" | **Hook returns the path; non-zero aborts creation** |
| `WorktreeRemove` | "When a worktree is being removed" | Salvage work before removal |

**Context and MCP**

| Event | When it fires | Use case |
|-------|---------------|----------|
| `PreCompact` | "Before context compaction" | Save state, or block compaction |
| `PostCompact` | "After context compaction completes" | Re-inject what compaction dropped |
| `Notification` | "When Claude Code sends a notification" | Custom alerts |
| `Elicitation` | "When an MCP server requests user input during a tool call" | Auto-answer or refuse MCP prompts |
| `ElicitationResult` | "After a user responds to an MCP elicitation" | Vet the response before it leaves |

Not every event supports a `matcher`, and the decision control differs per event (some can
block with exit code 2, some ignore the exit code entirely). Check the official reference
before relying on one to *stop* something.

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

## Undocumented settings (verified from the bundled binary)

These `settings.json` keys are not in the official docs but are real and read at runtime. Defaults below were verified by inspecting the bundled `@anthropic-ai/claude-code` binary. Internal short names change between versions — rely on the **key name and default**, not on any internal symbol. Behaviour may change in future releases; re-verify before depending on them.

| Key | Default | What it does | Why you might set it |
|-----|---------|--------------|----------------------|
| `switchModelsOnFlag` | `true` | When a safety classifier flags a message, the session auto-switches to a different (often larger/costlier) model to keep going. `false` makes the session **pause** instead. | Set `false` to keep your model and cost assumptions stable, and to notice flags instead of being silently moved to another model. |
| `skillListingMaxDescChars` | `1536` | Per-skill `description` character cap in the skill listing sent to the model. Longer descriptions are **silently truncated** (from the end). | A skill that "won't auto-trigger" can be a truncated description. Put trigger words first, keep descriptions short, or raise this (costs more per-turn context). |
| `skillListingBudgetFraction` | `0.01` (1%) | Fraction of the context window reserved for the whole skill listing. When the listing exceeds it, descriptions are shortened to fit. | Many skills ⇒ less room per skill ⇒ more truncation. Prune unused skills, or raise this (costs more per-turn context). |

```json
{
  "switchModelsOnFlag": false,
  "skillListingMaxDescChars": 4096,
  "skillListingBudgetFraction": 0.03
}
```

Raising the two skill-listing caps opts you into higher per-turn context cost (the listing is sent every turn). Prefer trimming descriptions and pruning skills first.

## Recently added settings (2.1.220 – 2.1.226)

> **Source: the official changelog, not my own machine.** Every other entry in this file was written
> from usage I ran here. These eleven were introduced in the last seven releases and are listed so the
> file keeps its promise of covering everything you can put in `settings.json`. Descriptions follow the
> changelog wording; I have not reproduced each one locally yet, and I say so rather than implying I have.
>
> Measured 2026-08-11 against Claude Code 2.1.226: all eleven were missing from this file.

| Setting | Since | What the changelog says |
|---|---|---|
| `crossSessionInbound` | 2.1.224 | Cross-session messages sent to a session **running with bypassed permissions are held for your approval**; messages to other sessions auto-deliver. |
| `dialogExpiry` | 2.1.224 | Paired with `crossSessionInbound`; controls how long the held approval dialog stays valid. |
| `network.tlsTerminate` | 2.1.224 | Required for the sandbox credential-masking options below to take effect. |
| `onExtractNoMatch` | 2.1.224 | Sandbox credential masking: what to do when `extract` finds no match in a structured env value. |
| `maskClaims` | 2.1.224 | Sandbox credential masking with `decode: "jwt"` — masks named JWT claims. |
| `awsPairs` | 2.1.224 | Sandbox credential masking for AWS SigV4 re-signing (with `sigv4`). |
| `strictKnownMarketplaces` | 2.1.223 | Managed setting: allow-list for plugin marketplaces. Supports `hostPattern`, `pathPattern`, and owner wildcards (`"owner/*"`). Enforced on install, update, refresh and autoupdate. |
| `blockedMarketplaces` | 2.1.223 | Managed setting: block-list for plugin marketplaces, same matching options. |
| `modelOverrides` | 2.1.223 | Maps model-picker entries to custom provider model IDs (e.g. Bedrock inference profile ARNs). Keys that are not Anthropic model IDs are ignored. |
| `sandbox.filesystem.denyWrite` | 2.1.223 | Sandbox write deny-list. A 2.1.223 fix covers the case where it includes the working directory. |
| `remoteControlAtStartup` | 2.1.224 | Whether Remote Control starts with the session. |

**Why three of these belong in a safety file, not just a completeness list**

- `crossSessionInbound` is a permission gate. If you run with `--dangerously-skip-permissions`, this is the
  one place a message from another session still stops for a human. Leaving it at its default is a decision,
  not an absence of one.
- `strictKnownMarketplaces` / `blockedMarketplaces` are supply-chain controls. They decide which plugin
  sources can install code on your machine, and as of 2.1.223 they are enforced on **autoupdate** too —
  so a source you allowed once keeps its access without a further prompt.
- The sandbox credential-masking options only take effect with `network.tlsTerminate`. A masking rule
  written without it is inert, and nothing in the output says so.

**None of these are covered by the example hooks in this repo yet.** If you rely on the hooks for a
control that one of these settings now provides natively, check both — they are separate layers.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Skill won't auto-trigger | `description` truncated past `skillListingMaxDescChars` (default 1536), or too many skills under the 1% listing budget | Put trigger words first, shorten descriptions, prune unused skills (see Undocumented settings above) |
| Model changed mid-session | `switchModelsOnFlag` is `true` by default; a safety flag auto-switched the model | Set `"switchModelsOnFlag": false` to pause instead |
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
