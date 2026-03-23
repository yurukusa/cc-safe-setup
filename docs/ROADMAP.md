# cc-safe-setup Roadmap

## Current: v3.8.1

- 8 built-in hooks + 38 examples
- 21 CLI commands
- 5 web tools (audit, cheatsheet, ecosystem, cookbook, hook builder)
- 173 tests, CI green
- 2,500+ daily npm downloads

## Next Major: v4.0 (planned)

### --dashboard: Real-Time Terminal Dashboard

A single screen showing everything about your Claude Code safety:

```
┌─ cc-safe-setup dashboard ─────────────────────────┐
│                                                     │
│  Hooks: 26 active (8 built-in + 18 examples)       │
│  Score: 85/100 (Grade A)                            │
│  Context: ~60% remaining                            │
│  Cost: ~$1.47 (142 tool calls, Opus)                │
│                                                     │
│  ── Recent Blocks ──────────────────────────────── │
│  14:23  rm -rf ~/projects (destructive-guard)       │
│  14:21  git push --force (branch-guard)             │
│  14:18  git add .env (secret-guard)                 │
│                                                     │
│  ── Hook Performance ───────────────────────────── │
│  destructive-guard  15ms ████████                   │
│  branch-guard        7ms ████                       │
│  secret-guard        5ms ███                        │
│                                                     │
│  ── Today ──────────────────────────────────────── │
│  Blocks: 12 | Warns: 5 | Approves: 34              │
│  Top reason: rm on sensitive path (5)               │
└─────────────────────────────────────────────────────┘
```

**Implementation notes:**
- ANSI escape codes only (no blessed/ink dependencies)
- Reads blocked-commands.log + context-monitor state + cost-tracker state
- Refreshes every 2 seconds
- Ctrl+C to exit
- Works in any terminal (iTerm, VS Code, Windows Terminal, WSL)

### Hook Marketplace (concept)

Community-contributed hooks discoverable from CLI:

```bash
npx cc-safe-setup --search "database"
npx cc-safe-setup --install-remote user/hook-name
```

Would require a registry (GitHub-based, no server). Defer to v5.0.

### Hook Composition

Chain hooks with conditions:

```json
{
  "hooks": [{
    "if": "branch === 'main'",
    "then": "block-all-writes.sh",
    "else": "allow-all.sh"
  }]
}
```

Requires Claude Code API changes. Not feasible with current hook system.

## Done (Session 39)

- --create, --lint, --diff, --share, --benchmark, --doctor, --watch, --stats
- --export/--import, --audit --json
- 38 examples including cost-tracker, loop-detector, session-handoff
- Hook Builder web tool
- Interactive COOKBOOK
- 6 documentation files + Japanese README
- CONTRIBUTING.md for external contributors
