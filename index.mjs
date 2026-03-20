#!/usr/bin/env node

import { readFileSync, writeFileSync, mkdirSync, existsSync, chmodSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { createInterface } from 'readline';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const HOME = homedir();
const HOOKS_DIR = join(HOME, '.claude', 'hooks');
const SETTINGS_PATH = join(HOME, '.claude', 'settings.json');

const c = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m',
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  blue: '\x1b[36m',
};

const SCRIPTS = JSON.parse(readFileSync(join(__dirname, 'scripts.json'), 'utf-8'));

const HOOKS = {
  'destructive-guard': {
    name: 'Destructive Command Blocker',
    why: 'A user lost their entire C:\\Users directory when rm -rf followed NTFS junctions',
    trigger: 'PreToolUse', matcher: 'Bash',
  },
  'branch-guard': {
    name: 'Branch Push Protector',
    why: 'Autonomous Claude Code pushed untested code directly to main at 3am',
    trigger: 'PreToolUse', matcher: 'Bash',
  },
  'syntax-check': {
    name: 'Post-Edit Syntax Validator',
    why: 'A Python syntax error cascaded through 30+ files before anyone noticed',
    trigger: 'PostToolUse', matcher: 'Edit|Write',
  },
  'context-monitor': {
    name: 'Context Window Monitor',
    why: 'Sessions silently lost all state at tool call 150+ with no warning',
    trigger: 'PostToolUse', matcher: '',
  },
  'comment-strip': {
    name: 'Bash Comment Stripper',
    why: 'Comments in bash commands break permission allowlists (18 reactions on GitHub #29582)',
    trigger: 'PreToolUse', matcher: 'Bash',
  },
  'cd-git-allow': {
    name: 'cd+git Auto-Approver',
    why: 'cd+git compounds spam permission prompts for read-only operations (9 reactions on #32985)',
    trigger: 'PreToolUse', matcher: 'Bash',
  },
};

function ask(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => {
    rl.question(question, answer => { rl.close(); resolve(answer.trim()); });
  });
}

const DRY_RUN = process.argv.includes('--dry-run') || process.argv.includes('-n');
const UNINSTALL = process.argv.includes('--uninstall') || process.argv.includes('--remove');

async function uninstall() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --uninstall' + c.reset);
  console.log();

  let removed = 0;
  for (const id of Object.keys(HOOKS)) {
    const hookPath = join(HOOKS_DIR, id + '.sh');
    if (existsSync(hookPath)) {
      const { unlinkSync } = await import('fs');
      unlinkSync(hookPath);
      console.log('  ' + c.red + 'x' + c.reset + ' Removed ' + c.dim + hookPath + c.reset);
      removed++;
    }
  }

  if (existsSync(SETTINGS_PATH)) {
    try {
      const settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      if (settings.hooks) {
        for (const trigger of Object.keys(settings.hooks)) {
          settings.hooks[trigger] = settings.hooks[trigger].filter(e =>
            !e.hooks || !e.hooks.some(h => {
              const cmd = h.command || '';
              return Object.keys(HOOKS).some(id => cmd.includes(id + '.sh'));
            })
          );
          if (settings.hooks[trigger].length === 0) delete settings.hooks[trigger];
        }
        if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
        writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
        console.log('  ' + c.red + 'x' + c.reset + ' Cleaned settings.json');
      }
    } catch(e) {}
  }

  console.log();
  console.log(c.bold + '  Done.' + c.reset + ' ' + removed + ' hooks removed.');
  console.log('  ' + c.dim + 'Restart Claude Code to deactivate.' + c.reset);
  console.log();
}

async function main() {
  if (UNINSTALL) return uninstall();

  console.log();
  console.log(c.bold + '  cc-safe-setup' + c.reset);
  console.log(c.dim + '  Make Claude Code safe for autonomous operation' + c.reset);
  console.log();
  // Check jq dependency
  try {
    const { execSync } = await import('child_process');
    execSync('which jq', { stdio: 'pipe' });
  } catch(e) {
    console.log(c.yellow + '  Warning: jq is not installed. Hooks require jq for JSON parsing.' + c.reset);
    console.log(c.dim + '  Install: brew install jq (macOS) | apt install jq (Linux)' + c.reset);
    console.log();
  }

  console.log(c.dim + '  Prevents real incidents:' + c.reset);
  console.log(c.red + '  x' + c.reset + ' rm -rf deleting entire user directories (NTFS junction traversal)');
  console.log(c.red + '  x' + c.reset + ' Untested code pushed to main at 3am');
  console.log(c.red + '  x' + c.reset + ' Syntax errors cascading through 30+ files');
  console.log(c.red + '  x' + c.reset + ' Sessions losing all context with no warning');
  console.log();

  console.log(c.bold + '  Hooks to install:' + c.reset);
  console.log();
  for (const [id, hook] of Object.entries(HOOKS)) {
    console.log('  ' + c.green + '*' + c.reset + ' ' + c.bold + hook.name + c.reset);
    console.log('    ' + c.dim + hook.why + c.reset);
  }
  console.log();

  if (DRY_RUN) {
    console.log(c.yellow + '  --dry-run: showing what would be installed (no changes made)' + c.reset);
    console.log();
    for (const [id, hook] of Object.entries(HOOKS)) {
      console.log('  ' + c.dim + 'would install: ' + join(HOOKS_DIR, id + '.sh') + c.reset);
    }
    console.log('  ' + c.dim + 'would update: ' + SETTINGS_PATH + c.reset);
    console.log();
    process.exit(0);
  }

  const answer = await ask('  Install all ' + Object.keys(HOOKS).length + ' safety hooks? [Y/n] ');
  if (answer.toLowerCase() === 'n') {
    console.log('\n  ' + c.dim + 'Cancelled.' + c.reset + '\n');
    process.exit(0);
  }

  console.log();
  mkdirSync(HOOKS_DIR, { recursive: true });

  for (const [id, hook] of Object.entries(HOOKS)) {
    const hookPath = join(HOOKS_DIR, id + '.sh');
    writeFileSync(hookPath, SCRIPTS[id]);
    try { chmodSync(hookPath, 0o755); } catch(e) {}
    console.log('  ' + c.green + 'v' + c.reset + ' ' + hook.name + ' -> ' + c.dim + hookPath + c.reset);
  }

  // Update settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch(e) {
      writeFileSync(SETTINGS_PATH + '.bak', readFileSync(SETTINGS_PATH));
    }
  }
  if (!settings.hooks) settings.hooks = {};

  for (const [id, hook] of Object.entries(HOOKS)) {
    const trigger = hook.trigger;
    if (!settings.hooks[trigger]) settings.hooks[trigger] = [];
    const hookPath = join(HOOKS_DIR, id + '.sh');
    const exists = settings.hooks[trigger].some(e =>
      e.hooks && e.hooks.some(h => h.command && h.command.includes(id + '.sh'))
    );
    if (!exists) {
      settings.hooks[trigger].push({
        matcher: hook.matcher,
        hooks: [{ type: 'command', command: hookPath }]
      });
    }
  }

  mkdirSync(dirname(SETTINGS_PATH), { recursive: true });
  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
  console.log('  ' + c.green + 'v' + c.reset + ' settings.json updated -> ' + c.dim + SETTINGS_PATH + c.reset);

  console.log();
  console.log(c.bold + '  Done.' + c.reset + ' ' + Object.keys(HOOKS).length + ' safety hooks installed.');
  console.log('  ' + c.dim + 'Restart Claude Code to activate.' + c.reset);
  console.log('  ' + c.dim + 'Verify:' + c.reset + ' ' + c.blue + 'npx cc-health-check' + c.reset);
  console.log();
  console.log('  ' + c.dim + 'Full kit (11 hooks + templates + tools):' + c.reset);
  console.log('  https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=npm&utm_medium=cli&utm_campaign=safe-setup');
  console.log();
}

main().catch(e => { console.error(e); process.exit(1); });
