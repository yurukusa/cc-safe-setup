#!/usr/bin/env node

import { readFileSync, writeFileSync, mkdirSync, existsSync, chmodSync, copyFileSync } from 'fs';
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
  'secret-guard': {
    name: 'Secret Leak Prevention',
    why: 'git add .env accidentally committed API keys to a public repo',
    trigger: 'PreToolUse', matcher: 'Bash',
  },
  'api-error-alert': {
    name: 'API Error Session Alert',
    why: 'Autonomous sessions silently died from rate limits with no notification',
    trigger: 'Stop', matcher: '',
  },
};

const HELP = process.argv.includes('--help') || process.argv.includes('-h');
const STATUS = process.argv.includes('--status') || process.argv.includes('-s');
const VERIFY = process.argv.includes('--verify') || process.argv.includes('-v');
const EXAMPLES = process.argv.includes('--examples') || process.argv.includes('-e');
const INSTALL_EXAMPLE_IDX = process.argv.findIndex(a => a === '--install-example');
const INSTALL_EXAMPLE = INSTALL_EXAMPLE_IDX !== -1 ? process.argv[INSTALL_EXAMPLE_IDX + 1] : null;

if (HELP) {
  console.log(`
  cc-safe-setup — Make Claude Code safe for autonomous operation

  Usage:
    npx cc-safe-setup              Install 8 safety hooks
    npx cc-safe-setup --status     Check installed hooks
    npx cc-safe-setup --verify     Test each hook with sample inputs
    npx cc-safe-setup --dry-run    Preview without installing
    npx cc-safe-setup --uninstall  Remove all installed hooks
    npx cc-safe-setup --examples   List available example hooks
    npx cc-safe-setup --install-example <name>  Install a specific example hook
    npx cc-safe-setup --help       Show this help

  Hooks installed:
    destructive-guard    Blocks rm -rf, git reset --hard, NFS mount detection
    branch-guard         Blocks pushes to main/master + force-push on all branches
    syntax-check         Validates Python/Shell/JSON/YAML/JS after edits
    context-monitor      Warns when context window is filling up
    comment-strip        Fixes bash comments breaking permissions
    cd-git-allow         Auto-approves read-only cd+git compounds
    secret-guard         Blocks git add .env and credential files
    api-error-alert      Notifies when session stops due to API errors

  More: https://github.com/yurukusa/cc-safe-setup
`);
  process.exit(0);
}

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

function status() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --status' + c.reset);
  console.log();

  let installed = 0;
  let missing = 0;
  for (const [id, hook] of Object.entries(HOOKS)) {
    const hookPath = join(HOOKS_DIR, id + '.sh');
    if (existsSync(hookPath)) {
      console.log('  ' + c.green + '✓' + c.reset + ' ' + hook.name + c.dim + ' → ' + hookPath + c.reset);
      installed++;
    } else {
      console.log('  ' + c.red + '✗' + c.reset + ' ' + hook.name + c.dim + ' (not installed)' + c.reset);
      missing++;
    }
  }

  // Check settings.json
  let settingsOk = false;
  if (existsSync(SETTINGS_PATH)) {
    try {
      const settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      if (settings.hooks) settingsOk = true;
    } catch(e) {}
  }
  console.log();
  console.log('  ' + (settingsOk ? c.green + '✓' : c.red + '✗') + c.reset + ' settings.json ' + (settingsOk ? 'has hooks configured' : 'missing hook configuration'));

  console.log();
  if (missing === 0) {
    console.log(c.bold + '  All ' + installed + ' hooks installed.' + c.reset);
  } else {
    console.log(c.bold + '  ' + installed + '/' + Object.keys(HOOKS).length + ' hooks installed.' + c.reset);
    console.log('  ' + c.dim + 'Run: npx cc-safe-setup' + c.reset);
  }
  console.log();

  // Exit code for CI: 0 = all installed, 1 = missing hooks
  if (missing > 0) process.exit(1);
}

async function verify() {
  const { execSync } = await import('child_process');
  console.log();
  console.log(c.bold + '  cc-safe-setup --verify' + c.reset);
  console.log(c.dim + '  Testing each hook with sample inputs...' + c.reset);
  console.log();

  const tests = [
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"rm -rf /"}}', expect: 2, desc: 'blocks rm -rf /' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"ls -la"}}', expect: 0, desc: 'allows safe commands' },
    { hook: 'branch-guard', input: '{"tool_input":{"command":"git push origin main"}}', expect: 2, desc: 'blocks push to main' },
    { hook: 'branch-guard', input: '{"tool_input":{"command":"git push origin feature"}}', expect: 0, desc: 'allows push to feature' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"git checkout --force main"}}', expect: 2, desc: 'blocks git checkout --force' },
    { hook: 'secret-guard', input: '{"tool_input":{"command":"git add .env"}}', expect: 2, desc: 'blocks git add .env' },
    { hook: 'secret-guard', input: '{"tool_input":{"command":"git add src/app.js"}}', expect: 0, desc: 'allows git add safe files' },
    { hook: 'api-error-alert', input: '{"stop_reason":"user"}', expect: 0, desc: 'ignores normal stops' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"cd /tmp && rm -rf /"}}', expect: 2, desc: 'blocks compound rm -rf' },
    { hook: 'branch-guard', input: '{"tool_input":{"command":"git push --force origin feature"}}', expect: 2, desc: 'blocks force-push' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"git reset --hard HEAD~5"}}', expect: 2, desc: 'blocks git reset --hard' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"sudo rm -rf /var"}}', expect: 2, desc: 'blocks sudo + destructive' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"Remove-Item -Recurse -Force *"}}', expect: 2, desc: 'blocks PowerShell Remove-Item' },
    { hook: 'destructive-guard', input: '{"tool_input":{"command":"Remove-Item ./file.txt"}}', expect: 0, desc: 'allows single file Remove-Item' },
  ];

  let pass = 0, fail = 0;
  for (const t of tests) {
    const hookPath = join(HOOKS_DIR, t.hook + '.sh');
    if (!existsSync(hookPath)) {
      console.log('  ' + c.red + '✗' + c.reset + ' ' + t.hook + ': ' + t.desc + c.dim + ' (not installed)' + c.reset);
      fail++;
      continue;
    }
    try {
      execSync(`echo '${t.input}' | bash "${hookPath}"`, { stdio: 'pipe' });
      if (t.expect === 0) {
        console.log('  ' + c.green + '✓' + c.reset + ' ' + t.hook + ': ' + t.desc);
        pass++;
      } else {
        console.log('  ' + c.red + '✗' + c.reset + ' ' + t.hook + ': ' + t.desc + ' (should have blocked)');
        fail++;
      }
    } catch(e) {
      if (e.status === t.expect) {
        console.log('  ' + c.green + '✓' + c.reset + ' ' + t.hook + ': ' + t.desc);
        pass++;
      } else {
        console.log('  ' + c.red + '✗' + c.reset + ' ' + t.hook + ': ' + t.desc + ' (exit ' + e.status + ', expected ' + t.expect + ')');
        fail++;
      }
    }
  }

  console.log();
  console.log(c.bold + '  ' + pass + '/' + (pass + fail) + ' tests passed.' + c.reset);
  if (fail > 0) {
    console.log('  ' + c.red + fail + ' failures.' + c.reset + ' Run ' + c.blue + 'npx cc-safe-setup' + c.reset + ' to reinstall.');
    process.exit(1);
  }
  console.log();
}

function examples() {
  const examplesDir = join(__dirname, 'examples');
  const EXAMPLE_DESCRIPTIONS = {
    'auto-approve-build.sh': 'Auto-approve npm/yarn/cargo/go build, test, lint commands',
    'auto-approve-docker.sh': 'Auto-approve docker build, compose, ps, logs commands',
    'auto-approve-git-read.sh': 'Auto-approve git status/log/diff even with -C flags',
    'auto-approve-ssh.sh': 'Auto-approve safe SSH commands (uptime, whoami, etc.)',
    'block-database-wipe.sh': 'Block destructive DB commands (migrate:fresh, DROP DATABASE)',
    'edit-guard.sh': 'Block Edit/Write to protected files (.env, credentials)',
    'enforce-tests.sh': 'Warn when source files change without test files',
    'notify-waiting.sh': 'Desktop notification when Claude waits for input',
    'auto-approve-python.sh': 'Auto-approve pytest, mypy, ruff, black, isort commands',
    'auto-snapshot.sh': 'Auto-save file snapshots before edits (rollback protection)',
    'allowlist.sh': 'Block everything not in allowlist (inverse permission model)',
    'protect-dotfiles.sh': 'Block modifications to ~/.bashrc, ~/.aws/, ~/.ssh/',
    'scope-guard.sh': 'Block file operations outside project directory',
    'auto-checkpoint.sh': 'Auto-commit after edits for rollback protection',
  };

  console.log();
  console.log(c.bold + '  cc-safe-setup --examples' + c.reset);
  console.log(c.dim + '  Custom hooks beyond the 8 built-in ones' + c.reset);
  console.log();

  for (const [file, desc] of Object.entries(EXAMPLE_DESCRIPTIONS)) {
    const fullPath = join(examplesDir, file);
    const exists = existsSync(fullPath);
    console.log('  ' + c.green + '*' + c.reset + ' ' + c.bold + file + c.reset);
    console.log('    ' + c.dim + desc + c.reset);
  }

  console.log();
  console.log(c.dim + '  Copy any example to ~/.claude/hooks/ and add to settings.json.' + c.reset);
  console.log(c.dim + '  Source: ' + c.blue + 'https://github.com/yurukusa/cc-safe-setup/tree/main/examples' + c.reset);
  console.log();
}

async function installExample(name) {
  const examplesDir = join(__dirname, 'examples');
  const filename = name.endsWith('.sh') ? name : name + '.sh';
  const srcPath = join(examplesDir, filename);

  if (!existsSync(srcPath)) {
    console.log();
    console.log(c.red + '  Error: example "' + name + '" not found.' + c.reset);
    console.log(c.dim + '  Run --examples to see available hooks.' + c.reset);
    console.log();
    process.exit(1);
  }

  const destPath = join(HOOKS_DIR, filename);
  mkdirSync(HOOKS_DIR, { recursive: true });
  copyFileSync(srcPath, destPath);
  chmodSync(destPath, 0o755);

  // Parse hook header for matcher and trigger
  const content = readFileSync(srcPath, 'utf8');
  let trigger = 'PreToolUse';
  let matcher = 'Bash';

  // Detect trigger from header comments
  if (content.includes('PostToolUse')) trigger = 'PostToolUse';
  if (content.includes('Notification')) trigger = 'Notification';
  if (content.includes('Stop')) trigger = 'Stop';

  // Detect matcher from header
  const matcherMatch = content.match(/"matcher":\s*"([^"]*)"/);
  if (matcherMatch) matcher = matcherMatch[1];

  // Update settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf8'));
  }
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks[trigger]) settings.hooks[trigger] = [];

  const hookEntry = {
    matcher: matcher,
    hooks: [{ type: 'command', command: destPath }],
  };

  // Check if already installed
  const existing = settings.hooks[trigger].find(h =>
    h.hooks && h.hooks.some(hh => hh.command && hh.command.includes(filename))
  );
  if (!existing) {
    settings.hooks[trigger].push(hookEntry);
    writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n');
  }

  console.log();
  console.log(c.green + '  ✓' + c.reset + ' Installed ' + c.bold + filename + c.reset);
  console.log(c.dim + '    → ' + destPath + c.reset);
  console.log(c.dim + '    → settings.json updated (' + trigger + ', matcher: "' + matcher + '")' + c.reset);
  console.log();
}

async function main() {
  if (UNINSTALL) return uninstall();
  if (VERIFY) return verify();
  if (STATUS) return status();
  if (EXAMPLES) return examples();
  if (INSTALL_EXAMPLE) return installExample(INSTALL_EXAMPLE);

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
  console.log(c.red + '  x' + c.reset + ' Force-push rewriting shared branch history');
  console.log(c.red + '  x' + c.reset + ' API keys committed to public repos via git add .');
  console.log(c.red + '  x' + c.reset + ' Syntax errors cascading through 30+ files');
  console.log(c.red + '  x' + c.reset + ' Sessions losing all context with no warning');
  console.log(c.red + '  x' + c.reset + ' git checkout --force discarding uncommitted changes');
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
  console.log('  ' + c.dim + 'Full kit (16 hooks + templates + tools):' + c.reset);
  console.log('  https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=npm&utm_medium=cli&utm_campaign=safe-setup');
  console.log();
}

main().catch(e => { console.error(e); process.exit(1); });
