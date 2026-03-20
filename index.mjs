#!/usr/bin/env node

import { readFileSync, writeFileSync, mkdirSync, existsSync, chmodSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { createInterface } from 'readline';

const HOME = homedir();
const HOOKS_DIR = join(HOME, '.claude', 'hooks');
const SETTINGS_PATH = join(HOME, '.claude', 'settings.json');

const c = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m',
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  blue: '\x1b[36m', magenta: '\x1b[35m',
};

// ═══════════════════════════════════════════════════
// Hook definitions — each one prevents a real incident
// ═══════════════════════════════════════════════════

const HOOKS = {
  'destructive-guard': {
    name: 'Destructive Command Blocker',
    why: 'A user lost their entire C:\\Users directory when rm -rf followed NTFS junctions (GitHub #36339)',
    trigger: 'PreToolUse',
    matcher: 'Bash',
    script: `#!/bin/bash
# destructive-guard.sh — Blocks rm -rf, git reset --hard, git clean
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# rm on sensitive paths
if echo "$COMMAND" | grep -qE 'rm\\s+(-[rf]+\\s+)*(\\/$|\\/\\s|\\/[^a-z]|\\/home|\\/etc|\\/usr|~\\/|~\\s*$|\\.\\.\\/|\\.\\.\\s*$)'; then
  SAFE=0
  for dir in node_modules dist build .cache __pycache__ coverage; do
    echo "$COMMAND" | grep -qE "rm\\s+.*${dir}" && SAFE=1 && break
  done
  if (( SAFE == 0 )); then
    echo "BLOCKED: rm on sensitive path. On WSL2, rm -rf follows NTFS junctions." >&2
    exit 2
  fi
fi

# git reset --hard
echo "$COMMAND" | grep -qE 'git\\s+reset\\s+--hard' && echo "BLOCKED: git reset --hard discards uncommitted changes." >&2 && exit 2

# git clean -fd
echo "$COMMAND" | grep -qE 'git\\s+clean\\s+-[a-z]*[fd]' && echo "BLOCKED: git clean removes untracked files permanently. Use -n first." >&2 && exit 2

exit 0`,
  },

  'branch-guard': {
    name: 'Branch Push Protector',
    why: 'Autonomous Claude Code pushed untested code directly to main at 3am',
    trigger: 'PreToolUse',
    matcher: 'Bash',
    script: `#!/bin/bash
# branch-guard.sh — Blocks pushes to main/master
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0
echo "$COMMAND" | grep -qE '^\\s*git\\s+push' || exit 0

PROTECTED="\${CC_PROTECT_BRANCHES:-main:master}"
IFS=':' read -ra BRANCHES <<< "$PROTECTED"
for branch in "\${BRANCHES[@]}"; do
  if echo "$COMMAND" | grep -qwE "origin\\s+\${branch}|\${branch}\\s|\${branch}$"; then
    echo "BLOCKED: Push to protected branch '\${branch}'. Use a feature branch + PR instead." >&2
    exit 2
  fi
done
exit 0`,
  },

  'syntax-check': {
    name: 'Post-Edit Syntax Validator',
    why: 'A Python syntax error cascaded through 30+ files before anyone noticed',
    trigger: 'PostToolUse',
    matcher: 'Edit|Write',
    script: `#!/bin/bash
# syntax-check.sh — Validates syntax after file edits
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0

case "$FILE" in
  *.py)  python3 -m py_compile "$FILE" 2>/dev/null || { echo "SYNTAX ERROR in $FILE" >&2; exit 1; } ;;
  *.sh)  bash -n "$FILE" 2>/dev/null || { echo "SYNTAX ERROR in $FILE" >&2; exit 1; } ;;
  *.json) python3 -c "import json; json.load(open('$FILE'))" 2>/dev/null || { echo "INVALID JSON: $FILE" >&2; exit 1; } ;;
  *.yaml|*.yml) python3 -c "import yaml; yaml.safe_load(open('$FILE'))" 2>/dev/null || { echo "INVALID YAML: $FILE" >&2; exit 1; } ;;
  *.js|*.mjs) node --check "$FILE" 2>/dev/null || { echo "SYNTAX ERROR in $FILE" >&2; exit 1; } ;;
esac
exit 0`,
  },

  'context-monitor': {
    name: 'Context Window Monitor',
    why: 'Sessions silently lost all state at tool call 150+ with no warning',
    trigger: 'PostToolUse',
    matcher: '',
    script: `#!/bin/bash
# context-monitor.sh — Warns when context window is filling up
INPUT=$(cat)
PERCENT=$(echo "$INPUT" | jq -r '.session.context_window.percent_used // empty' 2>/dev/null)
[[ -z "$PERCENT" ]] && exit 0

if (( $(echo "$PERCENT > 80" | bc -l 2>/dev/null || echo 0) )); then
  echo "⚠️ Context window at \${PERCENT}%. Consider compacting or starting a new session." >&2
fi
exit 0`,
  },
};

// ═══════════════════════════════════════════════════
// Installation logic
// ═══════════════════════════════════════════════════

function ask(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => {
    rl.question(question, answer => { rl.close(); resolve(answer.trim()); });
  });
}

function printHeader() {
  console.log();
  console.log(`${c.bold}  cc-safe-setup${c.reset}`);
  console.log(`${c.dim}  Make Claude Code safe for autonomous operation${c.reset}`);
  console.log();
  console.log(`${c.dim}  This installs safety hooks that prevent real incidents:${c.reset}`);
  console.log(`${c.red}  ✗${c.reset} rm -rf deleting entire user directories (NTFS junction traversal)`);
  console.log(`${c.red}  ✗${c.reset} Untested code pushed to main at 3am`);
  console.log(`${c.red}  ✗${c.reset} Syntax errors cascading through 30+ files`);
  console.log(`${c.red}  ✗${c.reset} Sessions losing all context with no warning`);
  console.log();
}

function installHook(id, hook) {
  const hookPath = join(HOOKS_DIR, `${id}.sh`);
  mkdirSync(HOOKS_DIR, { recursive: true });
  writeFileSync(hookPath, hook.script);
  try { chmodSync(hookPath, 0o755); } catch(e) {}
  return hookPath;
}

function updateSettings(installedHooks) {
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try {
      settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
    } catch(e) {
      console.log(`${c.yellow}  Warning: Could not parse existing settings.json. Creating backup.${c.reset}`);
      writeFileSync(SETTINGS_PATH + '.bak', readFileSync(SETTINGS_PATH));
      settings = {};
    }
  }

  if (!settings.hooks) settings.hooks = {};

  for (const [id, hook] of Object.entries(installedHooks)) {
    const trigger = hook.trigger;
    if (!settings.hooks[trigger]) settings.hooks[trigger] = [];

    const hookPath = join(HOOKS_DIR, `${id}.sh`);
    const entry = {
      matcher: hook.matcher,
      hooks: [{ type: 'command', command: hookPath }]
    };

    // Check if already exists
    const exists = settings.hooks[trigger].some(e =>
      e.hooks && e.hooks.some(h => h.command && h.command.includes(`${id}.sh`))
    );

    if (!exists) {
      settings.hooks[trigger].push(entry);
    }
  }

  mkdirSync(dirname(SETTINGS_PATH), { recursive: true });
  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
}

async function main() {
  printHeader();

  // Show what will be installed
  console.log(`${c.bold}  Hooks to install:${c.reset}`);
  console.log();
  for (const [id, hook] of Object.entries(HOOKS)) {
    console.log(`  ${c.green}●${c.reset} ${c.bold}${hook.name}${c.reset}`);
    console.log(`    ${c.dim}${hook.why}${c.reset}`);
  }
  console.log();

  const answer = await ask(`  Install all ${Object.keys(HOOKS).length} safety hooks? [Y/n] `);
  if (answer.toLowerCase() === 'n') {
    console.log(`\n  ${c.dim}Cancelled. No changes made.${c.reset}\n`);
    process.exit(0);
  }

  console.log();

  // Install hooks
  const installed = {};
  for (const [id, hook] of Object.entries(HOOKS)) {
    const path = installHook(id, hook);
    installed[id] = hook;
    console.log(`  ${c.green}✓${c.reset} ${hook.name} → ${c.dim}${path}${c.reset}`);
  }

  // Update settings.json
  updateSettings(installed);
  console.log(`  ${c.green}✓${c.reset} settings.json updated → ${c.dim}${SETTINGS_PATH}${c.reset}`);

  console.log();
  console.log(`${c.bold}  Done.${c.reset} ${Object.keys(HOOKS).length} safety hooks installed.`);
  console.log();
  console.log(`  ${c.dim}Restart Claude Code to activate the hooks.${c.reset}`);
  console.log();
  console.log(`  ${c.dim}Verify your setup:${c.reset} ${c.blue}npx cc-health-check${c.reset}`);
  console.log();
  console.log(`  ${c.dim}Want more hooks + templates + tools?${c.reset}`);
  console.log(`  ${c.bold}https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=npm&utm_medium=cli&utm_campaign=safe-setup${c.reset}`);
  console.log();
}

main().catch(e => { console.error(e); process.exit(1); });
