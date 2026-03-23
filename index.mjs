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
const AUDIT = process.argv.includes('--audit');
const LEARN = process.argv.includes('--learn');
const SCAN = process.argv.includes('--scan');
const FULL = process.argv.includes('--full');

if (HELP) {
  console.log(`
  cc-safe-setup — Make Claude Code safe for autonomous operation

  Usage:
    npx cc-safe-setup              Install 8 safety hooks
    npx cc-safe-setup --status     Check installed hooks
    npx cc-safe-setup --verify     Test each hook with sample inputs
    npx cc-safe-setup --dry-run    Preview without installing
    npx cc-safe-setup --uninstall  Remove all installed hooks
    npx cc-safe-setup --examples   List 25 example hooks (5 categories)
    npx cc-safe-setup --install-example <name>  Install a specific example
    npx cc-safe-setup --audit      Analyze your setup and recommend missing protections
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

  // Check installed examples
  const exampleFiles = [
    'allowlist.sh', 'auto-approve-build.sh', 'auto-approve-docker.sh',
    'auto-approve-git-read.sh', 'auto-approve-python.sh', 'auto-approve-ssh.sh',
    'auto-checkpoint.sh', 'auto-snapshot.sh', 'block-database-wipe.sh', 'branch-name-check.sh', 'commit-message-check.sh', 'env-var-check.sh',
    'deploy-guard.sh', 'edit-guard.sh', 'enforce-tests.sh', 'git-config-guard.sh',
    'large-file-guard.sh', 'network-guard.sh', 'notify-waiting.sh', 'path-traversal-guard.sh',
    'protect-dotfiles.sh', 'scope-guard.sh', 'test-before-push.sh', 'timeout-guard.sh', 'todo-check.sh',
  ];
  const installedExamples = exampleFiles.filter(f => existsSync(join(HOOKS_DIR, f)));
  if (installedExamples.length > 0) {
    console.log();
    console.log('  ' + c.bold + 'Example hooks installed:' + c.reset);
    for (const f of installedExamples) {
      console.log('  ' + c.green + '✓' + c.reset + ' ' + f);
    }
  }

  console.log();
  if (missing === 0) {
    console.log(c.bold + '  All ' + installed + ' hooks installed.' + c.reset);
  } else {
    console.log(c.bold + '  ' + installed + '/' + Object.keys(HOOKS).length + ' hooks installed.' + c.reset);
    console.log('  ' + c.dim + 'Run: npx cc-safe-setup' + c.reset);
  }
  if (installedExamples.length > 0) {
    console.log('  ' + c.dim + '+ ' + installedExamples.length + ' example hooks' + c.reset);
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
  const CATEGORIES = {
    'Safety Guards': {
      'allowlist.sh': 'Block everything not in allowlist (inverse permission model)',
      'block-database-wipe.sh': 'Block destructive DB commands (migrate:fresh, DROP DATABASE, Prisma)',
      'deploy-guard.sh': 'Block deploy when uncommitted changes exist',
      'env-var-check.sh': 'Block hardcoded API keys in export commands',
      'network-guard.sh': 'Warn on suspicious network commands (data exfiltration)',
      'path-traversal-guard.sh': 'Block Edit/Write with path traversal (../../)',
      'protect-dotfiles.sh': 'Block modifications to ~/.bashrc, ~/.aws/, ~/.ssh/',
      'scope-guard.sh': 'Block file operations outside project directory',
      'test-before-push.sh': 'Block git push when tests have not passed',
      'timeout-guard.sh': 'Warn before long-running commands (servers, watchers)',
      'git-config-guard.sh': 'Block git config --global modifications',
    },
    'Auto-Approve': {
      'auto-approve-build.sh': 'Auto-approve npm/yarn/cargo/go build, test, lint',
      'auto-approve-docker.sh': 'Auto-approve docker build, compose, ps, logs',
      'auto-approve-git-read.sh': 'Auto-approve git status/log/diff even with -C flags',
      'auto-approve-python.sh': 'Auto-approve pytest, mypy, ruff, black, isort',
      'auto-approve-ssh.sh': 'Auto-approve safe SSH commands (uptime, whoami)',
    },
    'Quality': {
      'branch-name-check.sh': 'Warn on non-conventional branch names',
      'commit-message-check.sh': 'Warn on non-conventional commit messages',
      'edit-guard.sh': 'Block Edit/Write to protected files (.env, credentials)',
      'enforce-tests.sh': 'Warn when source files change without test files',
      'large-file-guard.sh': 'Warn when Write creates files over 500KB',
      'todo-check.sh': 'Warn when committing files with TODO/FIXME markers',
      'verify-before-commit.sh': 'Block commit unless tests passed recently',
    },
    'Recovery': {
      'auto-checkpoint.sh': 'Auto-commit after edits for rollback protection',
      'auto-snapshot.sh': 'Auto-save file snapshots before edits (rollback protection)',
    },
    'UX': {
      'notify-waiting.sh': 'Desktop notification when Claude waits for input',
    },
  };

  console.log();
  console.log(c.bold + '  cc-safe-setup --examples' + c.reset);
  console.log(c.dim + '  25 hooks beyond the 8 built-in ones' + c.reset);
  console.log();

  for (const [cat, hooks] of Object.entries(CATEGORIES)) {
    console.log('  ' + c.bold + c.blue + cat + c.reset);
    for (const [file, desc] of Object.entries(hooks)) {
      console.log('  ' + c.green + '*' + c.reset + ' ' + c.bold + file + c.reset);
      console.log('    ' + c.dim + desc + c.reset);
    }
    console.log();
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

async function audit() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --audit' + c.reset);
  console.log(c.dim + '  Analyzing your Claude Code safety setup...' + c.reset);
  console.log();

  const risks = [];
  const good = [];

  // 1. Check if any PreToolUse hooks exist
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch(e) {}
  }
  const preHooks = (settings.hooks?.PreToolUse || []);
  const postHooks = (settings.hooks?.PostToolUse || []);
  const stopHooks = (settings.hooks?.Stop || []);

  if (preHooks.length === 0) {
    risks.push({
      severity: 'CRITICAL',
      issue: 'No PreToolUse hooks — destructive commands (rm -rf, git reset --hard) can run unchecked',
      fix: 'npx cc-safe-setup'
    });
  } else {
    good.push('PreToolUse hooks installed (' + preHooks.length + ')');
  }

  // 2. Check for destructive command protection
  const allHookCommands = preHooks.map(h => h.hooks?.map(hh => hh.command || '').join(' ') || '').join(' ');
  if (!allHookCommands.match(/destructive|guard|block|rm|reset/i)) {
    risks.push({
      severity: 'HIGH',
      issue: 'No destructive command blocker detected — rm -rf /, git reset --hard could execute',
      fix: 'npx cc-safe-setup (installs destructive-guard)'
    });
  } else {
    good.push('Destructive command protection detected');
  }

  // 3. Check for branch protection
  if (!allHookCommands.match(/branch|push|main|master/i)) {
    risks.push({
      severity: 'HIGH',
      issue: 'No branch push protection — code could be pushed directly to main/master',
      fix: 'npx cc-safe-setup (installs branch-guard)'
    });
  } else {
    good.push('Branch push protection detected');
  }

  // 4. Check for secret leak protection
  if (!allHookCommands.match(/secret|env|credential/i)) {
    risks.push({
      severity: 'HIGH',
      issue: 'No secret leak protection — .env files could be committed via git add .',
      fix: 'npx cc-safe-setup (installs secret-guard)'
    });
  } else {
    good.push('Secret leak protection detected');
  }

  // 5. Check for database wipe protection
  if (!allHookCommands.match(/database|wipe|migrate|prisma/i)) {
    risks.push({
      severity: 'MEDIUM',
      issue: 'No database wipe protection — migrate:fresh, prisma migrate reset could wipe data',
      fix: 'npx cc-safe-setup --install-example block-database-wipe'
    });
  } else {
    good.push('Database wipe protection detected');
  }

  // 6. Check for syntax checking
  if (postHooks.length === 0) {
    risks.push({
      severity: 'MEDIUM',
      issue: 'No PostToolUse hooks — no automatic syntax checking after edits',
      fix: 'npx cc-safe-setup (installs syntax-check)'
    });
  } else {
    good.push('PostToolUse hooks installed (' + postHooks.length + ')');
  }

  // 7. Check for CLAUDE.md
  const CC_DIR = join(HOME, '.claude');
  const claudeMdPaths = ['CLAUDE.md', '.claude/CLAUDE.md', join(CC_DIR, 'CLAUDE.md')];
  const hasClaudeMd = claudeMdPaths.some(p => existsSync(p));
  if (!hasClaudeMd) {
    risks.push({
      severity: 'MEDIUM',
      issue: 'No CLAUDE.md found — Claude has no project-specific instructions',
      fix: 'Create CLAUDE.md with project rules and conventions'
    });
  } else {
    good.push('CLAUDE.md found');
  }

  // 8. Check for dotfile protection
  if (!allHookCommands.match(/dotfile|bashrc|protect/i)) {
    risks.push({
      severity: 'LOW',
      issue: 'No dotfile protection — ~/.bashrc, ~/.aws/ could be modified',
      fix: 'npx cc-safe-setup --install-example protect-dotfiles'
    });
  }

  // 9. Check for scope guard
  if (!allHookCommands.match(/scope|traversal|outside/i)) {
    risks.push({
      severity: 'LOW',
      issue: 'No scope guard — files outside project directory could be modified',
      fix: 'npx cc-safe-setup --install-example scope-guard'
    });
  }

  // Display results
  if (good.length > 0) {
    console.log(c.bold + '  ✓ What\'s working:' + c.reset);
    for (const g of good) {
      console.log('  ' + c.green + '✓' + c.reset + ' ' + g);
    }
    console.log();
  }

  if (risks.length === 0) {
    console.log(c.green + c.bold + '  No risks detected. Your setup looks solid.' + c.reset);
  } else {
    console.log(c.bold + '  ⚠ Risks found (' + risks.length + '):' + c.reset);
    console.log();
    for (const r of risks) {
      const severityColor = r.severity === 'CRITICAL' ? c.red : r.severity === 'HIGH' ? c.red : c.yellow;
      console.log('  ' + severityColor + '[' + r.severity + ']' + c.reset + ' ' + r.issue);
      console.log('  ' + c.dim + '  Fix: ' + r.fix + c.reset);
    }
  }

  console.log();
  const score = Math.max(0, 100 - risks.reduce((sum, r) => {
    if (r.severity === 'CRITICAL') return sum + 30;
    if (r.severity === 'HIGH') return sum + 20;
    if (r.severity === 'MEDIUM') return sum + 10;
    return sum + 5;
  }, 0));
  console.log(c.bold + '  Safety Score: ' + (score >= 80 ? c.green : score >= 50 ? c.yellow : c.red) + score + '/100' + c.reset);

  // --audit --fix: auto-fix what we can
  if (process.argv.includes('--fix') && risks.length > 0) {
    console.log();
    console.log(c.bold + '  Applying fixes...' + c.reset);
    const { execSync } = await import('child_process');
    for (const r of risks) {
      if (r.fix.startsWith('npx cc-safe-setup')) {
        try {
          const cmd = r.fix.replace('npx cc-safe-setup', 'node ' + process.argv[1]);
          console.log('  ' + c.dim + '→ ' + r.fix + c.reset);
          execSync(cmd, { stdio: 'inherit' });
        } catch(e) {
          console.log('  ' + c.red + '  Failed: ' + e.message + c.reset);
        }
      }
    }
    console.log();
    console.log(c.green + '  Re-run --audit to verify fixes.' + c.reset);
  } else if (risks.length > 0) {
    console.log();
    console.log(c.dim + '  Run with --fix to auto-apply: npx cc-safe-setup --audit --fix' + c.reset);
  }

  // Badge output
  if (process.argv.includes('--badge')) {
    const color = score >= 80 ? 'brightgreen' : score >= 50 ? 'yellow' : 'red';
    const badge = `![Claude Code Safety](https://img.shields.io/badge/Claude_Code_Safety-${score}%2F100-${color})`;
    console.log();
    console.log(c.bold + '  README Badge:' + c.reset);
    console.log('  ' + badge);
    console.log();
    console.log(c.dim + '  Paste this into your README.md' + c.reset);
  }

  console.log();
}

function learn() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --learn' + c.reset);
  console.log(c.dim + '  Analyzing your blocked command history to generate custom protections...' + c.reset);
  console.log();

  const logPath = join(HOME, '.claude', 'blocked-commands.log');
  if (!existsSync(logPath)) {
    console.log(c.yellow + '  No blocked-commands.log found.' + c.reset);
    console.log(c.dim + '  Install cc-safe-setup first, then use Claude Code normally.' + c.reset);
    console.log(c.dim + '  Blocked commands are logged automatically. Re-run --learn after a few sessions.' + c.reset);
    console.log();
    return;
  }

  const log = readFileSync(logPath, 'utf-8');
  const lines = log.split('\n').filter(l => l.trim());

  if (lines.length === 0) {
    console.log(c.green + '  No blocked commands in history. Your setup is catching nothing (or everything is safe).' + c.reset);
    console.log();
    return;
  }

  // Extract command patterns from blocked log
  const patterns = {};
  for (const line of lines) {
    // Extract the command from log lines like "[2026-03-23 12:00:00] BLOCKED: rm -rf / (destructive-guard)"
    const cmdMatch = line.match(/BLOCKED:\s*(.+?)(?:\s*\(|$)/);
    if (cmdMatch) {
      const cmd = cmdMatch[1].trim();
      // Extract the base command (first word)
      const base = cmd.split(/\s+/)[0];
      if (!patterns[base]) patterns[base] = [];
      patterns[base].push(cmd);
    }
  }

  const uniqueBases = Object.keys(patterns);
  if (uniqueBases.length === 0) {
    console.log(c.dim + '  Could not parse patterns from log. Format may differ.' + c.reset);
    console.log();
    return;
  }

  console.log(c.bold + '  Patterns found (' + lines.length + ' blocked commands):' + c.reset);
  console.log();

  const recommendations = [];

  for (const [base, cmds] of Object.entries(patterns)) {
    const count = cmds.length;
    const unique = [...new Set(cmds)];

    if (count >= 3) {
      console.log('  ' + c.red + '⚠' + c.reset + ' ' + c.bold + base + c.reset + ' blocked ' + count + ' times');
      for (const u of unique.slice(0, 3)) {
        console.log('    ' + c.dim + u + c.reset);
      }
      if (unique.length > 3) console.log('    ' + c.dim + '... and ' + (unique.length - 3) + ' more' + c.reset);

      recommendations.push({
        command: base,
        count,
        examples: unique.slice(0, 5),
      });
    } else {
      console.log('  ' + c.yellow + '·' + c.reset + ' ' + base + ' (' + count + 'x)');
    }
  }

  if (recommendations.length > 0) {
    console.log();
    console.log(c.bold + '  Recommendations:' + c.reset);
    console.log();
    for (const r of recommendations) {
      console.log('  ' + c.green + '→' + c.reset + ' ' + r.command + ' is frequently blocked (' + r.count + 'x).');
      console.log('    Consider adding a specific hook or adjusting your allow rules.');

      // Generate a custom hook suggestion
      const hookCode = `#!/bin/bash
# Auto-generated: block ${r.command} patterns (seen ${r.count} times)
CMD=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0
if echo "$CMD" | grep -qE '^\\s*${r.command}\\b'; then
    echo "BLOCKED: ${r.command} requires manual approval" >&2
    exit 2
fi
exit 0`;

      const hookPath = join(HOOKS_DIR, 'learned-block-' + r.command + '.sh');
      console.log('    ' + c.dim + 'Suggested hook: ' + hookPath + c.reset);

      if (process.argv.includes('--apply')) {
        mkdirSync(HOOKS_DIR, { recursive: true });
        writeFileSync(hookPath, hookCode);
        chmodSync(hookPath, 0o755);
        console.log('    ' + c.green + '✓ Hook created' + c.reset);
      }
    }

    if (!process.argv.includes('--apply')) {
      console.log();
      console.log(c.dim + '  Run with --apply to auto-create hooks: npx cc-safe-setup --learn --apply' + c.reset);
    }
  }

  console.log();
  console.log(c.bold + '  Summary: ' + lines.length + ' blocked commands, ' + uniqueBases.length + ' unique patterns, ' + recommendations.length + ' recommendations.' + c.reset);
  console.log();
}

async function fullSetup() {
  console.log();
  console.log(c.bold + c.green + '  cc-safe-setup --full' + c.reset);
  console.log(c.dim + '  Complete safety setup in one command' + c.reset);
  console.log();

  const { execSync } = await import('child_process');
  const self = process.argv[1];

  // Step 1: Install 8 built-in hooks
  console.log(c.bold + '  Step 1: Installing 8 built-in safety hooks...' + c.reset);
  try {
    execSync('node ' + self + ' --yes', { stdio: 'inherit' });
  } catch(e) {
    // --yes doesn't exist, run normal install
    execSync('node ' + self, { stdio: 'inherit', input: 'y\n' });
  }

  // Step 2: Scan project and create CLAUDE.md
  console.log();
  console.log(c.bold + '  Step 2: Scanning project and creating CLAUDE.md...' + c.reset);
  scan();

  // Step 3: Audit and show results
  console.log();
  console.log(c.bold + '  Step 3: Running safety audit...' + c.reset);
  // Inject --badge into argv temporarily
  process.argv.push('--badge');
  await audit();

  console.log(c.bold + c.green + '  ✓ Full setup complete!' + c.reset);
  console.log(c.dim + '  Your project now has:' + c.reset);
  console.log(c.dim + '  • 8 built-in safety hooks' + c.reset);
  console.log(c.dim + '  • Project-specific hook recommendations' + c.reset);
  console.log(c.dim + '  • Safety score and README badge' + c.reset);
  console.log();
}

function scan() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --scan' + c.reset);
  console.log(c.dim + '  Scanning project to generate safety config...' + c.reset);
  console.log();

  const cwd = process.cwd();
  const detected = { languages: [], frameworks: [], hasDb: false, hasDocker: false, isMonorepo: false };
  const hooks = ['destructive-guard', 'branch-guard', 'secret-guard', 'syntax-check'];
  const claudeMdRules = ['# Project Safety Rules\n', '## Generated by cc-safe-setup --scan\n'];

  // Detect languages & frameworks
  if (existsSync(join(cwd, 'package.json'))) {
    detected.languages.push('JavaScript/TypeScript');
    try {
      const pkg = JSON.parse(readFileSync(join(cwd, 'package.json'), 'utf-8'));
      const allDeps = { ...pkg.dependencies, ...pkg.devDependencies };
      if (allDeps.next) detected.frameworks.push('Next.js');
      if (allDeps.react) detected.frameworks.push('React');
      if (allDeps.express) detected.frameworks.push('Express');
      if (allDeps.prisma || allDeps['@prisma/client']) { detected.frameworks.push('Prisma'); detected.hasDb = true; }
      if (allDeps.sequelize) { detected.frameworks.push('Sequelize'); detected.hasDb = true; }
      if (allDeps.typeorm) { detected.frameworks.push('TypeORM'); detected.hasDb = true; }
    } catch(e) {}
  }
  if (existsSync(join(cwd, 'requirements.txt')) || existsSync(join(cwd, 'pyproject.toml'))) {
    detected.languages.push('Python');
    if (existsSync(join(cwd, 'manage.py'))) { detected.frameworks.push('Django'); detected.hasDb = true; }
    if (existsSync(join(cwd, 'app.py')) || existsSync(join(cwd, 'wsgi.py'))) detected.frameworks.push('Flask');
  }
  if (existsSync(join(cwd, 'Gemfile'))) {
    detected.languages.push('Ruby');
    detected.frameworks.push('Rails');
    detected.hasDb = true;
  }
  if (existsSync(join(cwd, 'composer.json'))) {
    detected.languages.push('PHP');
    try {
      const composer = JSON.parse(readFileSync(join(cwd, 'composer.json'), 'utf-8'));
      if (composer.require?.['laravel/framework']) { detected.frameworks.push('Laravel'); detected.hasDb = true; }
      if (composer.require?.['symfony/framework-bundle']) { detected.frameworks.push('Symfony'); detected.hasDb = true; }
    } catch(e) {}
  }
  if (existsSync(join(cwd, 'go.mod'))) detected.languages.push('Go');
  if (existsSync(join(cwd, 'Cargo.toml'))) detected.languages.push('Rust');

  // Docker
  if (existsSync(join(cwd, 'Dockerfile')) || existsSync(join(cwd, 'docker-compose.yml')) || existsSync(join(cwd, 'compose.yaml'))) {
    detected.hasDocker = true;
  }

  // Monorepo
  if (existsSync(join(cwd, 'pnpm-workspace.yaml')) || existsSync(join(cwd, 'lerna.json')) || existsSync(join(cwd, 'nx.json'))) {
    detected.isMonorepo = true;
  }

  // .env files
  const hasEnv = existsSync(join(cwd, '.env')) || existsSync(join(cwd, '.env.local'));

  // Display detection results
  console.log(c.bold + '  Detected:' + c.reset);
  if (detected.languages.length) console.log('  ' + c.green + '✓' + c.reset + ' Languages: ' + detected.languages.join(', '));
  if (detected.frameworks.length) console.log('  ' + c.green + '✓' + c.reset + ' Frameworks: ' + detected.frameworks.join(', '));
  if (detected.hasDb) console.log('  ' + c.green + '✓' + c.reset + ' Database detected');
  if (detected.hasDocker) console.log('  ' + c.green + '✓' + c.reset + ' Docker detected');
  if (detected.isMonorepo) console.log('  ' + c.green + '✓' + c.reset + ' Monorepo detected');
  if (hasEnv) console.log('  ' + c.yellow + '⚠' + c.reset + ' .env file found (secret leak risk)');
  console.log();

  // Generate recommendations
  const examples = [];

  if (detected.hasDb) {
    examples.push('block-database-wipe');
    claudeMdRules.push('- Never run destructive database commands (migrate:fresh, DROP DATABASE, prisma migrate reset)');
    claudeMdRules.push('- Always backup database before schema changes');
  }

  if (detected.hasDocker) {
    examples.push('auto-approve-docker');
    claudeMdRules.push('- Docker commands are auto-approved for build/compose/ps/logs');
  }

  if (hasEnv) {
    claudeMdRules.push('- Never commit .env files. Use .env.example for templates');
    claudeMdRules.push('- Never hardcode API keys or secrets in source files');
  }

  if (detected.languages.includes('Python')) {
    examples.push('auto-approve-python');
    claudeMdRules.push('- Run pytest after every code change');
  }

  if (detected.languages.includes('JavaScript/TypeScript')) {
    examples.push('auto-approve-build');
    claudeMdRules.push('- Run npm test after every code change');
  }

  // Always recommend
  examples.push('scope-guard');
  examples.push('protect-dotfiles');
  claudeMdRules.push('- Always run tests before committing');
  claudeMdRules.push('- Never force-push to main/master');
  claudeMdRules.push('- Create a backup branch before large refactors');

  // Display recommendations
  console.log(c.bold + '  Recommended hooks:' + c.reset);
  console.log('  ' + c.dim + 'npx cc-safe-setup' + c.reset + ' (8 built-in hooks)');
  for (const ex of examples) {
    console.log('  ' + c.dim + 'npx cc-safe-setup --install-example ' + ex + c.reset);
  }

  // Generate CLAUDE.md
  console.log();
  const claudeMdPath = join(cwd, 'CLAUDE.md');
  if (existsSync(claudeMdPath)) {
    console.log(c.yellow + '  CLAUDE.md already exists. Suggested rules to add:' + c.reset);
    console.log();
    for (const rule of claudeMdRules.slice(2)) {
      console.log('  ' + c.dim + rule + c.reset);
    }
  } else {
    const content = claudeMdRules.join('\n') + '\n';
    if (process.argv.includes('--apply')) {
      writeFileSync(claudeMdPath, content);
      console.log(c.green + '  ✓ CLAUDE.md created with ' + (claudeMdRules.length - 2) + ' project-specific rules.' + c.reset);
    } else {
      console.log(c.bold + '  Suggested CLAUDE.md:' + c.reset);
      console.log();
      for (const rule of claudeMdRules) {
        console.log('  ' + c.dim + rule + c.reset);
      }
      console.log();
      console.log(c.dim + '  Run with --apply to create: npx cc-safe-setup --scan --apply' + c.reset);
    }
  }

  console.log();
}

async function main() {
  if (UNINSTALL) return uninstall();
  if (VERIFY) return verify();
  if (STATUS) return status();
  if (EXAMPLES) return examples();
  if (INSTALL_EXAMPLE) return installExample(INSTALL_EXAMPLE);
  if (AUDIT) return audit();
  if (LEARN) return learn();
  if (SCAN) return scan();
  if (FULL) return fullSetup();

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
  console.log(c.red + '  x' + c.reset + ' Remove-Item -Recurse -Force destroying unpushed source code');
  console.log(c.red + '  x' + c.reset + ' prisma migrate reset / migrate:fresh wiping databases');
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
