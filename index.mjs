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
const DOCTOR = process.argv.includes('--doctor');
const WATCH = process.argv.includes('--watch');
const EXPORT = process.argv.includes('--export');
const IMPORT_IDX = process.argv.findIndex(a => a === '--import');
const IMPORT_FILE = IMPORT_IDX !== -1 ? process.argv[IMPORT_IDX + 1] : null;
const STATS = process.argv.includes('--stats');
const JSON_OUTPUT = process.argv.includes('--json');
const LINT = process.argv.includes('--lint');
const DIFF_IDX = process.argv.findIndex(a => a === '--diff');
const DIFF_FILE = DIFF_IDX !== -1 ? process.argv[DIFF_IDX + 1] : null;
const SHARE = process.argv.includes('--share');
const BENCHMARK = process.argv.includes('--benchmark');
const DASHBOARD = process.argv.includes('--dashboard');
const ISSUES = process.argv.includes('--issues');
const MIGRATE = process.argv.includes('--migrate');
const GENERATE_CI = process.argv.includes('--generate-ci');
const COMPARE_IDX = process.argv.findIndex(a => a === '--compare');
const COMPARE = COMPARE_IDX !== -1 ? { a: process.argv[COMPARE_IDX + 1], b: process.argv[COMPARE_IDX + 2] } : null;
const CREATE_IDX = process.argv.findIndex(a => a === '--create');
const CREATE_DESC = CREATE_IDX !== -1 ? process.argv.slice(CREATE_IDX + 1).join(' ') : null;

if (HELP) {
  console.log(`
  cc-safe-setup — Make Claude Code safe for autonomous operation

  Usage:
    npx cc-safe-setup              Install 8 safety hooks
    npx cc-safe-setup --status     Check installed hooks
    npx cc-safe-setup --verify     Test each hook with sample inputs
    npx cc-safe-setup --dry-run    Preview without installing
    npx cc-safe-setup --uninstall  Remove all installed hooks
    npx cc-safe-setup --examples   List 30 example hooks (5 categories)
    npx cc-safe-setup --install-example <name>  Install a specific example
    npx cc-safe-setup --full       Complete setup: hooks + scan + audit + badge
    npx cc-safe-setup --audit      Safety score (0-100) with fixes
    npx cc-safe-setup --audit --fix  Auto-fix missing protections
    npx cc-safe-setup --audit --json  Machine-readable output for CI/CD
    npx cc-safe-setup --scan       Detect tech stack, recommend hooks
    npx cc-safe-setup --learn      Learn from your block history
    npx cc-safe-setup --generate-ci   Generate GitHub Actions workflow for safety checks
    npx cc-safe-setup --migrate       Detect hooks from other projects, suggest replacements
    npx cc-safe-setup --compare <a> <b>  Compare two hooks side-by-side
    npx cc-safe-setup --issues        Show GitHub Issues each hook addresses
    npx cc-safe-setup --dashboard     Real-time status dashboard
    npx cc-safe-setup --benchmark     Measure hook execution time
    npx cc-safe-setup --share         Generate shareable URL for your setup
    npx cc-safe-setup --diff <file>   Compare your settings with another file
    npx cc-safe-setup --lint       Static analysis of hook configuration
    npx cc-safe-setup --doctor     Diagnose why hooks aren't working
    npx cc-safe-setup --watch      Live dashboard of blocked commands
    npx cc-safe-setup --create "<desc>"  Generate a custom hook from description
    npx cc-safe-setup --stats      Block statistics and patterns report
    npx cc-safe-setup --export     Export hooks config for team sharing
    npx cc-safe-setup --import <file>  Import hooks from exported config
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
  Find hooks: npx cc-hook-registry search <keyword>
  Test hooks: npx cc-hook-test <hook.sh>
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
      'case-sensitive-guard.sh': 'Detect case-insensitive FS collisions (exFAT/NTFS/HFS+)',
      'compound-command-approver.sh': 'Auto-approve safe compound commands (cd && git log)',
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
      'session-checkpoint.sh': 'Save session state before context compaction',
    },
    'UX': {
      'notify-waiting.sh': 'Desktop notification when Claude waits for input',
      'tmp-cleanup.sh': 'Clean up /tmp/claude-*-cwd files on session end',
      'hook-debug-wrapper.sh': 'Wrap any hook to log input/output/exit/timing',
      'loop-detector.sh': 'Detect and break command repetition loops',
      'session-handoff.sh': 'Auto-save session state for next session resume',
      'commit-quality-gate.sh': 'Warn on vague or too-long commit messages',
      'diff-size-guard.sh': 'Warn/block on large diffs (10+ files warn, 50+ block)',
      'dependency-audit.sh': 'Warn on new package installs not in manifest',
      'binary-file-guard.sh': 'Warn when Write targets binary file types',
      'stale-branch-guard.sh': 'Warn when branch is far behind default',
      'symlink-guard.sh': 'Detect symlink/junction traversal in rm targets',
      'cost-tracker.sh': 'Estimate session token cost ($1 warn, $5 alert)',
      'read-before-edit.sh': 'Warn when editing files not recently read',
      'no-sudo-guard.sh': 'Block all sudo commands',
      'no-install-global.sh': 'Block npm -g and system-wide pip',
      'no-curl-upload.sh': 'Warn on curl POST/upload',
      'no-port-bind.sh': 'Warn on network port binding',
      'git-tag-guard.sh': 'Block pushing all tags at once',
      'npm-publish-guard.sh': 'Version check before npm publish',
      'max-file-count-guard.sh': 'Warn when 20+ files created per session',
      'protect-claudemd.sh': 'Block edits to CLAUDE.md and settings files',
      'reinject-claudemd.sh': 'Re-inject CLAUDE.md rules after compaction',
    },
  };

  // Optional category filter: --examples safety, --examples ux, etc.
  const filterArg = process.argv[process.argv.indexOf('--examples') + 1] || process.argv[process.argv.indexOf('-e') + 1] || '';
  const filter = filterArg.toLowerCase();

  console.log();
  console.log(c.bold + '  cc-safe-setup --examples' + c.reset + (filter ? ' ' + filter : ''));
  console.log(c.dim + '  38 hooks beyond the 8 built-in ones' + c.reset);
  if (filter) console.log(c.dim + '  Filter: ' + filter + c.reset);
  console.log();

  for (const [cat, hooks] of Object.entries(CATEGORIES)) {
    // Filter by category name OR hook name/description
    const filteredHooks = filter
      ? Object.entries(hooks).filter(([file, desc]) =>
          cat.toLowerCase().includes(filter) ||
          file.toLowerCase().includes(filter) ||
          desc.toLowerCase().includes(filter))
      : Object.entries(hooks);

    if (filteredHooks.length === 0) continue;

    console.log('  ' + c.bold + c.blue + cat + c.reset);
    for (const [file, desc] of filteredHooks) {
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

  // JSON output (for CI/CD integration)
  if (JSON_OUTPUT) {
    const output = {
      score,
      grade: score >= 80 ? 'A' : score >= 60 ? 'B' : score >= 40 ? 'C' : 'F',
      risks: risks.map(r => ({ severity: r.severity, issue: r.issue, fix: r.fix })),
      passing: good,
      timestamp: new Date().toISOString(),
    };
    console.log(JSON.stringify(output, null, 2));
  }

  console.log();
  process.exit(score < (parseInt(process.env.CC_AUDIT_THRESHOLD) || 0) ? 1 : 0);
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

function generateCI() {
  const workflowDir = join(process.cwd(), '.github', 'workflows');
  const workflowPath = join(workflowDir, 'claude-code-safety.yml');

  const workflow = `# Claude Code Safety Audit
# Generated by: npx cc-safe-setup --generate-ci
# Checks safety score on every PR and fails if below threshold

name: Claude Code Safety
on:
  pull_request:
  push:
    branches: [main, master]

jobs:
  safety-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run safety audit
        uses: yurukusa/cc-safe-setup@main
        with:
          threshold: 70

      - name: Comment PR with score
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const score = '\${{ steps.audit.outputs.score }}' || '?';
            const grade = '\${{ steps.audit.outputs.grade }}' || '?';
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: \`## Claude Code Safety: \${score}/100 (Grade \${grade})\\n\\nRun \\\`npx cc-safe-setup --audit\\\` locally for details.\`
            });
`;

  console.log();
  console.log(c.bold + '  cc-safe-setup --generate-ci' + c.reset);
  console.log();

  if (existsSync(workflowPath)) {
    console.log(c.yellow + '  Workflow already exists: ' + workflowPath + c.reset);
    console.log(c.dim + '  Delete it first if you want to regenerate.' + c.reset);
    process.exit(0);
  }

  mkdirSync(workflowDir, { recursive: true });
  writeFileSync(workflowPath, workflow);

  console.log(c.green + '  ✓ Created: ' + workflowPath + c.reset);
  console.log();
  console.log(c.dim + '  This workflow will:' + c.reset);
  console.log(c.dim + '  1. Run safety audit on every PR and push to main' + c.reset);
  console.log(c.dim + '  2. Fail CI if safety score < 70' + c.reset);
  console.log(c.dim + '  3. Comment PR with safety score' + c.reset);
  console.log();
  console.log(c.dim + '  Commit and push to activate:' + c.reset);
  console.log(c.bold + '  git add .github/workflows/claude-code-safety.yml && git commit -m "ci: add safety audit" && git push' + c.reset);
  console.log();
}

async function migrate() {
  const { readdirSync } = await import('fs');

  console.log();
  console.log(c.bold + '  cc-safe-setup --migrate' + c.reset);
  console.log(c.dim + '  Detecting hooks from other projects...' + c.reset);
  console.log();

  if (!existsSync(HOOKS_DIR)) {
    console.log(c.dim + '  No hooks installed.' + c.reset);
    process.exit(0);
  }

  const files = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh') || f.endsWith('.js') || f.endsWith('.py'));

  // Detection patterns for other projects
  const detections = [
    { pattern: /safety-net|cc-safety-net|SAFETY_LEVEL/i, project: 'claude-code-safety-net', replacement: 'npx cc-safe-setup (destructive-guard, branch-guard)' },
    { pattern: /karanb192|block-dangerous-commands\.js/i, project: 'karanb192/claude-code-hooks', replacement: 'npx cc-safe-setup (destructive-guard)' },
    { pattern: /hooks-mastery|disler|pre_tool_use\.py/i, project: 'disler/claude-code-hooks-mastery', replacement: 'npx cc-safe-setup (multiple hooks)' },
    { pattern: /cchooks|from cchooks/i, project: 'GowayLee/cchooks', replacement: 'npx cc-safe-setup (bash equivalents)' },
    { pattern: /lasso.*security|prompt.*injection.*pattern/i, project: 'lasso-security/claude-hooks', replacement: 'No direct equivalent (unique functionality)' },
  ];

  let found = 0;
  const suggestions = [];

  for (const file of files) {
    const content = readFileSync(join(HOOKS_DIR, file), 'utf-8');

    for (const det of detections) {
      if (det.pattern.test(content) || det.pattern.test(file)) {
        console.log('  ' + c.yellow + '!' + c.reset + ' ' + file + c.dim + ' ← from ' + det.project + c.reset);
        console.log('    ' + c.dim + 'Replacement: ' + det.replacement + c.reset);
        found++;
        break;
      }
    }

    // Detect hand-written hooks that duplicate built-in functionality
    if (content.includes('rm -rf') && !file.includes('destructive-guard')) {
      suggestions.push({ file, suggest: 'destructive-guard', reason: 'rm -rf detection already built-in' });
    }
    if (content.includes('git push') && content.includes('main') && !file.includes('branch-guard')) {
      suggestions.push({ file, suggest: 'branch-guard', reason: 'branch protection already built-in' });
    }
    if (content.includes('.env') && content.includes('git add') && !file.includes('secret-guard')) {
      suggestions.push({ file, suggest: 'secret-guard', reason: 'secret leak prevention already built-in' });
    }
  }

  if (suggestions.length > 0) {
    console.log();
    console.log(c.bold + '  Duplicate functionality detected:' + c.reset);
    for (const s of suggestions) {
      console.log('  ' + c.dim + s.file + c.reset + ' → ' + c.green + s.suggest + c.reset);
      console.log('    ' + c.dim + s.reason + c.reset);
    }
  }

  console.log();
  if (found === 0 && suggestions.length === 0) {
    console.log(c.green + '  No migration needed. All hooks are cc-safe-setup native.' + c.reset);
  } else {
    console.log(c.dim + '  Run npx cc-safe-setup to install built-in replacements.' + c.reset);
  }
  console.log();
}

async function compare(hookA, hookB) {
  const { spawnSync } = await import('child_process');
  const { statSync } = await import('fs');

  console.log();
  console.log(c.bold + '  cc-safe-setup --compare' + c.reset);
  console.log();

  if (!hookA || !hookB) {
    console.log(c.red + '  Usage: npx cc-safe-setup --compare <hook-a.sh> <hook-b.sh>' + c.reset);
    process.exit(1);
  }

  // Resolve paths
  const resolveHook = (h) => {
    if (existsSync(h)) return h;
    const inHooks = join(HOOKS_DIR, h);
    if (existsSync(inHooks)) return inHooks;
    const inExamples = join(__dirname, 'examples', h);
    if (existsSync(inExamples)) return inExamples;
    return null;
  };

  const pathA = resolveHook(hookA);
  const pathB = resolveHook(hookB);

  if (!pathA) { console.log(c.red + '  Hook A not found: ' + hookA + c.reset); process.exit(1); }
  if (!pathB) { console.log(c.red + '  Hook B not found: ' + hookB + c.reset); process.exit(1); }

  const nameA = hookA.split('/').pop();
  const nameB = hookB.split('/').pop();

  // Test cases
  const tests = [
    { name: 'empty input', input: '{}' },
    { name: 'safe command', input: '{"tool_input":{"command":"echo hello"}}' },
    { name: 'rm -rf /', input: '{"tool_input":{"command":"rm -rf /"}}' },
    { name: 'rm -rf ~', input: '{"tool_input":{"command":"rm -rf ~"}}' },
    { name: 'git push main', input: '{"tool_input":{"command":"git push origin main"}}' },
    { name: 'git push --force', input: '{"tool_input":{"command":"git push --force"}}' },
    { name: 'git add .env', input: '{"tool_input":{"command":"git add .env"}}' },
    { name: 'git reset --hard', input: '{"tool_input":{"command":"git reset --hard"}}' },
    { name: 'npm test', input: '{"tool_input":{"command":"npm test"}}' },
    { name: 'cd && git log', input: '{"tool_input":{"command":"cd /tmp && git log"}}' },
  ];

  function runHook(path, input) {
    const start = process.hrtime.bigint();
    const result = spawnSync('bash', [path], { input, timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] });
    const ms = Number(process.hrtime.bigint() - start) / 1_000_000;
    return { exit: result.status ?? -1, ms, stderr: (result.stderr || Buffer.alloc(0)).toString().slice(0, 80) };
  }

  // Header
  console.log('  ' + c.bold + 'Test'.padEnd(20) + nameA.padEnd(25) + nameB + c.reset);
  console.log('  ' + '-'.repeat(65));

  let sameCount = 0;
  let diffCount = 0;

  for (const test of tests) {
    const a = runHook(pathA, test.input);
    const b = runHook(pathB, test.input);
    const same = a.exit === b.exit;
    if (same) sameCount++; else diffCount++;

    const exitA = a.exit === 0 ? c.green + 'allow' + c.reset : a.exit === 2 ? c.red + 'BLOCK' + c.reset : c.yellow + 'err' + a.exit + c.reset;
    const exitB = b.exit === 0 ? c.green + 'allow' + c.reset : b.exit === 2 ? c.red + 'BLOCK' + c.reset : c.yellow + 'err' + b.exit + c.reset;
    const marker = same ? ' ' : c.yellow + '≠' + c.reset;

    console.log('  ' + marker + ' ' + test.name.padEnd(18) + (exitA + ' ' + a.ms.toFixed(0) + 'ms').padEnd(30) + exitB + ' ' + b.ms.toFixed(0) + 'ms');
  }

  // Size comparison
  const sizeA = statSync(pathA).size;
  const sizeB = statSync(pathB).size;

  console.log('  ' + '-'.repeat(65));
  console.log('  Same decisions: ' + sameCount + '/' + tests.length);
  if (diffCount > 0) console.log('  ' + c.yellow + 'Different: ' + diffCount + c.reset);
  console.log('  Size: ' + nameA + ' ' + sizeA + 'B vs ' + nameB + ' ' + sizeB + 'B');
  console.log();
}

function issues() {
  // Map hooks to the GitHub Issues they address
  const ISSUE_MAP = [
    { hook: 'destructive-guard', issues: ['#36339 rm -rf NTFS junction (93r)', '#36640 NFS mount deletion', '#37331 PowerShell Remove-Item (13r)', '#36233 Mac filesystem deleted (67r)'] },
    { hook: 'branch-guard', issues: ['Untested code pushed to main at 3am'] },
    { hook: 'secret-guard', issues: ['#6527 .env committed to public repo (94r)'] },
    { hook: 'syntax-check', issues: ['Syntax errors cascading through 30+ files'] },
    { hook: 'context-monitor', issues: ['Sessions dying at 3% context with no warning'] },
    { hook: 'comment-strip', issues: ['#29582 Bash comments break permissions (18r)'] },
    { hook: 'cd-git-allow', issues: ['#32985 cd+git permission spam (9r)', '#16561 Compound commands (101r)'] },
    { hook: 'api-error-alert', issues: ['Sessions silently dying from rate limits'] },
    { hook: 'block-database-wipe', issues: ['#37405 Database destroyed (0r)', '#34729 Prisma migrate reset data loss'] },
    { hook: 'compound-command-approver', issues: ['#30519 Permission matching broken (53r)', '#16561 Parse compound commands (101r)'] },
    { hook: 'case-sensitive-guard', issues: ['#37875 exFAT case collision (0r)'] },
    { hook: 'tmp-cleanup', issues: ['#8856 /tmp/claude-*-cwd leak (67r)', '#17609 tmp files not cleaned (29r)'] },
    { hook: 'loop-detector', issues: ['Command repetition loops wasting context'] },
    { hook: 'session-handoff', issues: ['#17428 Enhanced /compact (104r)', '#6354 CLAUDE.md lost after compact (27r)'] },
    { hook: 'cost-tracker', issues: ['No visibility into session token costs'] },
    { hook: 'deploy-guard', issues: ['#37314 Deploy without commit'] },
    { hook: 'protect-dotfiles', issues: ['#37478 .bashrc destroyed (3r)'] },
    { hook: 'scope-guard', issues: ['#36233 Files deleted outside project (67r)'] },
    { hook: 'env-source-guard', issues: ['#401 .env loaded into bash environment (54r)'] },
    { hook: 'diff-size-guard', issues: ['Unreviable mega-commits'] },
    { hook: 'dependency-audit', issues: ['Supply chain risk from unknown packages'] },
    { hook: 'read-before-edit', issues: ['old_string mismatch from editing unread files'] },
    { hook: 'symlink-guard', issues: ['#36339 NTFS junction traversal (93r)', '#764 Symlink resolution failure (63r)'] },
    { hook: 'binary-file-guard', issues: ['Binary file corruption from Write tool'] },
    { hook: 'stale-branch-guard', issues: ['Merge conflicts from stale branches'] },
    { hook: 'reinject-claudemd', issues: ['#6354 CLAUDE.md lost after compaction (27r)'] },
    { hook: 'no-sudo-guard', issues: ['Privilege escalation prevention'] },
    { hook: 'no-install-global', issues: ['System package pollution'] },
    { hook: 'protect-claudemd', issues: ['AI modifying its own config files'] },
    { hook: 'git-tag-guard', issues: ['Accidental tag push'] },
    { hook: 'npm-publish-guard', issues: ['Accidental publish without version check'] },
  ];

  console.log();
  console.log(c.bold + '  cc-safe-setup --issues' + c.reset);
  console.log(c.dim + '  Which GitHub Issues each hook addresses' + c.reset);
  console.log();

  let totalIssues = 0;
  for (const entry of ISSUE_MAP) {
    console.log('  ' + c.green + entry.hook + c.reset);
    for (const issue of entry.issues) {
      const isLink = issue.startsWith('#');
      if (isLink) {
        const num = issue.match(/#(\d+)/)?.[1];
        console.log('    ' + c.dim + 'https://github.com/anthropics/claude-code/issues/' + num + c.reset);
        console.log('    ' + issue.replace(/#\d+\s*/, ''));
      } else {
        console.log('    ' + c.dim + issue + c.reset);
      }
      totalIssues++;
    }
    console.log();
  }

  console.log(c.bold + '  ' + ISSUE_MAP.length + ' hooks addressing ' + totalIssues + ' issues/problems' + c.reset);
  console.log();
}

async function dashboard() {
  const fsModule = await import('fs');

  const BLOCK_LOG = join(HOME, '.claude', 'blocked-commands.log');
  const ERROR_LOG = join(HOME, '.claude', 'session-errors.log');
  const COST_FILE = '/tmp/cc-cost-tracker-calls';
  const CONTEXT_FILE = '/tmp/cc-context-pct';
  const HANDOFF_FILE = join(HOME, '.claude', 'session-handoff.md');
  const W = 60; // dashboard width

  const clear = () => process.stdout.write('\x1b[2J\x1b[H');

  // ANSI box drawing helpers
  const box = {
    tl: '┌', tr: '┐', bl: '└', br: '┘',
    h: '─', v: '│', lt: '├', rt: '┤',
  };

  function hline(left, right, w) { return left + box.h.repeat(w - 2) + right; }
  function pad(text, w) {
    const stripped = text.replace(/\x1b\[[0-9;]*m/g, '');
    const padding = Math.max(0, w - 2 - stripped.length);
    return box.v + ' ' + text + ' '.repeat(padding) + box.v;
  }
  function progressBar(pct, w, filledColor, emptyColor) {
    const barW = w - 2;
    const filled = Math.round(pct / 100 * barW);
    return filledColor + '█'.repeat(filled) + emptyColor + '░'.repeat(barW - filled) + c.reset;
  }
  function sparkline(values, w) {
    const chars = ' ▁▂▃▄▅▆▇';
    const max = Math.max(...values, 1);
    return values.slice(-w).map(v => chars[Math.min(7, Math.round(v / max * 7))]).join('');
  }

  // Collect hook info
  let hooksByTrigger = {};
  let totalHooks = 0;
  let scriptCount = 0;
  if (existsSync(SETTINGS_PATH)) {
    try {
      const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      for (const [trigger, entries] of Object.entries(s.hooks || {})) {
        const count = entries.reduce((n, e) => n + (e.hooks || []).length, 0);
        hooksByTrigger[trigger] = count;
        totalHooks += count;
      }
    } catch {}
  }
  if (existsSync(HOOKS_DIR)) {
    scriptCount = fsModule.readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh')).length;
  }

  // Audit score (cached)
  let auditScore = '?';
  try {
    // Quick inline audit
    let risks = 0;
    const s = existsSync(SETTINGS_PATH) ? JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')) : {};
    const pre = s.hooks?.PreToolUse || [];
    const post = s.hooks?.PostToolUse || [];
    if (pre.length === 0) risks += 30;
    const allCmds = JSON.stringify(pre).toLowerCase();
    if (!allCmds.match(/destructive|guard|rm.*rf/)) risks += 20;
    if (!allCmds.match(/branch|push|main/)) risks += 20;
    if (!allCmds.match(/secret|env|credential/)) risks += 20;
    if (post.length === 0) risks += 10;
    auditScore = Math.max(0, 100 - risks);
  } catch {}

  function render() {
    clear();

    const now = new Date();
    const timeStr = now.toLocaleTimeString();
    const dateStr = now.toLocaleDateString();

    // Read live data
    const contextPct = existsSync(CONTEXT_FILE) ? parseInt(readFileSync(CONTEXT_FILE, 'utf-8').trim()) || 0 : -1;
    const toolCalls = existsSync(COST_FILE) ? parseInt(readFileSync(COST_FILE, 'utf-8').trim()) || 0 : 0;
    const costEst = (toolCalls * 0.105).toFixed(2);

    // Parse block log
    let blocks = [];
    let blocksByHour = new Array(24).fill(0);
    let blockReasons = {};
    if (existsSync(BLOCK_LOG)) {
      const lines = readFileSync(BLOCK_LOG, 'utf-8').split('\n').filter(l => l.trim());
      for (const line of lines) {
        const m = line.match(/^\[([^\]]+)\]\s*BLOCKED:\s*(.+?)\s*\|\s*cmd:\s*(.+)$/);
        if (m) {
          const hour = new Date(m[1]).getHours();
          if (!isNaN(hour)) blocksByHour[hour]++;
          const reason = m[2].trim();
          blockReasons[reason] = (blockReasons[reason] || 0) + 1;
          blocks.push({ time: m[1], reason, cmd: m[3].trim() });
        }
      }
    }

    const totalBlocks = blocks.length;
    const todayBlocks = blocks.filter(b => b.time.startsWith(dateStr.split('/').reverse().join('-'))).length;

    // === RENDER ===
    console.log(hline(box.tl, box.tr, W));
    console.log(pad(c.bold + 'cc-safe-setup dashboard' + c.reset + '  ' + c.dim + timeStr + c.reset, W));
    console.log(hline(box.lt, box.rt, W));

    // Status panel
    const scoreColor = auditScore >= 80 ? c.green : auditScore >= 50 ? c.yellow : c.red;
    const grade = auditScore >= 80 ? 'A' : auditScore >= 60 ? 'B' : auditScore >= 40 ? 'C' : 'F';
    console.log(pad('Score: ' + scoreColor + auditScore + '/100' + c.reset + ' (Grade ' + grade + ')  Hooks: ' + c.green + totalHooks + c.reset + '  Scripts: ' + scriptCount, W));

    // Context bar
    if (contextPct >= 0) {
      const ctxColor = contextPct > 40 ? c.green : contextPct > 20 ? c.yellow : c.red;
      console.log(pad('Context: ' + ctxColor + contextPct + '%' + c.reset + ' ' + progressBar(contextPct, 30, ctxColor, c.dim), W));
    } else {
      console.log(pad('Context: ' + c.dim + 'unknown' + c.reset, W));
    }

    // Cost
    console.log(pad('Cost: ~$' + costEst + ' (' + toolCalls + ' tool calls, Opus)', W));
    console.log(pad('Blocks: ' + c.red + totalBlocks + c.reset + ' total  |  Today: ' + todayBlocks, W));

    // Hooks by trigger
    console.log(hline(box.lt, box.rt, W));
    console.log(pad(c.bold + 'Hooks by Trigger' + c.reset, W));
    for (const [trigger, count] of Object.entries(hooksByTrigger)) {
      const bar = '█'.repeat(Math.min(count, 20));
      console.log(pad(c.dim + trigger.padEnd(18) + c.reset + c.blue + bar + c.reset + ' ' + count, W));
    }

    // Hourly activity sparkline
    console.log(hline(box.lt, box.rt, W));
    console.log(pad(c.bold + 'Block Activity (24h)' + c.reset, W));
    console.log(pad(c.yellow + sparkline(blocksByHour, 24) + c.reset + '  ' + c.dim + '0h' + ' '.repeat(20) + '23h' + c.reset, W));

    // Top block reasons
    console.log(hline(box.lt, box.rt, W));
    console.log(pad(c.bold + 'Top Block Reasons' + c.reset, W));
    const sortedReasons = Object.entries(blockReasons).sort((a, b) => b[1] - a[1]).slice(0, 5);
    const maxR = sortedReasons[0]?.[1] || 1;
    for (const [reason, count] of sortedReasons) {
      const bar = '▓'.repeat(Math.ceil(count / maxR * 15));
      console.log(pad(c.red + bar + c.reset + ' ' + count + ' ' + c.dim + reason.slice(0, 25) + c.reset, W));
    }
    if (sortedReasons.length === 0) {
      console.log(pad(c.dim + '(no blocks recorded)' + c.reset, W));
    }

    // Recent blocks
    console.log(hline(box.lt, box.rt, W));
    console.log(pad(c.bold + 'Recent Blocks' + c.reset, W));
    const recent = blocks.slice(-5);
    for (const b of recent) {
      const time = b.time.replace(/T/, ' ').replace(/\+.*/, '').slice(11, 16);
      console.log(pad(c.dim + time + c.reset + ' ' + c.red + b.reason.slice(0, 35) + c.reset, W));
    }
    if (recent.length === 0) console.log(pad(c.dim + '(none)' + c.reset, W));

    // Session errors
    let errorCount = 0;
    if (existsSync(ERROR_LOG)) {
      errorCount = readFileSync(ERROR_LOG, 'utf-8').split('\n').filter(l => l.trim()).length;
    }
    if (errorCount > 0) {
      console.log(hline(box.lt, box.rt, W));
      console.log(pad(c.yellow + 'Session errors: ' + errorCount + c.reset, W));
    }

    console.log(hline(box.bl, box.br, W));
    console.log(c.dim + '  Refreshing every 3s. Ctrl+C to exit.' + c.reset);
  }

  render();
  setInterval(render, 3000);
  await new Promise(() => {});
}

async function benchmark() {
  const { spawnSync } = await import('child_process');

  console.log();
  console.log(c.bold + '  cc-safe-setup --benchmark' + c.reset);
  console.log(c.dim + '  Measuring hook execution time (10 runs each)...' + c.reset);
  console.log();

  if (!existsSync(SETTINGS_PATH)) {
    console.log(c.red + '  No settings.json found.' + c.reset);
    process.exit(1);
  }

  const settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
  const hooks = settings.hooks || {};
  const results = [];
  const testInput = JSON.stringify({ tool_input: { command: 'echo hello' } });
  const RUNS = 10;

  for (const [trigger, entries] of Object.entries(hooks)) {
    for (const entry of entries) {
      for (const h of (entry.hooks || [])) {
        if (h.type !== 'command') continue;
        let scriptPath = (h.command || '').replace(/^(bash|sh|node)\s+/, '').split(/\s+/)[0];
        scriptPath = scriptPath.replace(/^~/, HOME);
        if (!existsSync(scriptPath)) continue;

        const name = scriptPath.split('/').pop();
        const times = [];

        for (let i = 0; i < RUNS; i++) {
          const start = process.hrtime.bigint();
          spawnSync('bash', [scriptPath], {
            input: testInput,
            timeout: 5000,
            stdio: ['pipe', 'pipe', 'pipe'],
          });
          const end = process.hrtime.bigint();
          times.push(Number(end - start) / 1_000_000); // ms
        }

        const avg = times.reduce((a, b) => a + b, 0) / times.length;
        const max = Math.max(...times);
        const min = Math.min(...times);

        results.push({ name, trigger, avg, max, min, matcher: entry.matcher || '(all)' });
      }
    }
  }

  // Sort by avg time descending
  results.sort((a, b) => b.avg - a.avg);

  // Display
  const maxAvg = results[0]?.avg || 1;
  console.log(c.bold + '  Hook                          Avg     Min     Max    Trigger' + c.reset);
  console.log('  ' + '-'.repeat(75));

  for (const r of results) {
    const bar = '█'.repeat(Math.ceil(r.avg / maxAvg * 15));
    const avgColor = r.avg > 100 ? c.red : r.avg > 50 ? c.yellow : c.green;
    console.log(
      '  ' + r.name.padEnd(30) +
      avgColor + r.avg.toFixed(1).padStart(6) + 'ms' + c.reset +
      r.min.toFixed(1).padStart(6) + 'ms' +
      r.max.toFixed(1).padStart(6) + 'ms' +
      '  ' + c.dim + r.trigger + c.reset
    );
  }

  console.log();
  const totalAvg = results.reduce((s, r) => s + r.avg, 0);
  const slow = results.filter(r => r.avg > 50);

  console.log(c.dim + '  Total avg per tool call: ' + totalAvg.toFixed(1) + 'ms (sum of all hooks on that trigger)' + c.reset);
  if (slow.length > 0) {
    console.log(c.yellow + '  ' + slow.length + ' hook(s) over 50ms — consider optimizing' + c.reset);
  } else {
    console.log(c.green + '  All hooks under 50ms — good performance' + c.reset);
  }
  console.log();
}

function share() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --share' + c.reset);
  console.log();

  if (!existsSync(SETTINGS_PATH)) {
    console.log(c.red + '  No settings.json found.' + c.reset);
    process.exit(1);
  }

  const settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));

  // Strip sensitive data — only keep hooks and permissions structure
  const shareable = {
    hooks: settings.hooks || {},
    permissions: settings.permissions || {},
    defaultMode: settings.defaultMode,
  };

  // Remove full file paths, keep only script names
  for (const trigger of Object.keys(shareable.hooks)) {
    for (const entry of shareable.hooks[trigger]) {
      for (const h of (entry.hooks || [])) {
        if (h.command) {
          // Keep only the filename
          h.command = h.command.split('/').pop();
        }
      }
    }
  }

  const json = JSON.stringify(shareable);
  const encoded = Buffer.from(json).toString('base64');
  const url = 'https://yurukusa.github.io/cc-safe-setup/?config=' + encoded;

  console.log(c.green + '  Shareable URL:' + c.reset);
  console.log();
  console.log('  ' + url);
  console.log();
  console.log(c.dim + '  Anyone with this URL can audit your hook setup in their browser.' + c.reset);
  console.log(c.dim + '  Only hook names and permissions are shared (no file paths or secrets).' + c.reset);
  console.log();
}

function diff(otherFile) {
  console.log();
  console.log(c.bold + '  cc-safe-setup --diff' + c.reset);
  console.log();

  if (!existsSync(otherFile)) {
    console.log(c.red + '  File not found: ' + otherFile + c.reset);
    process.exit(1);
  }

  if (!existsSync(SETTINGS_PATH)) {
    console.log(c.red + '  No local settings.json found.' + c.reset);
    process.exit(1);
  }

  let local, other;
  try { local = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch { console.log(c.red + '  Cannot parse local settings.json' + c.reset); process.exit(1); }
  try { other = JSON.parse(readFileSync(otherFile, 'utf-8')); } catch { console.log(c.red + '  Cannot parse ' + otherFile + c.reset); process.exit(1); }

  const getHookCommands = (settings, trigger) => {
    return (settings.hooks?.[trigger] || []).flatMap(e => (e.hooks || []).map(h => {
      const cmd = h.command || '';
      return cmd.split('/').pop().replace(/\.sh$|\.js$|\.py$/, '');
    }));
  };

  const getAllow = (settings) => settings.permissions?.allow || [];
  const getDeny = (settings) => settings.permissions?.deny || [];

  console.log(c.dim + '  Local: ' + SETTINGS_PATH + c.reset);
  console.log(c.dim + '  Other: ' + otherFile + c.reset);
  console.log();

  // Compare hooks
  const triggers = [...new Set([...Object.keys(local.hooks || {}), ...Object.keys(other.hooks || {})])];

  let diffs = 0;
  for (const trigger of triggers) {
    const localHooks = new Set(getHookCommands(local, trigger));
    const otherHooks = new Set(getHookCommands(other, trigger));

    const onlyLocal = [...localHooks].filter(h => !otherHooks.has(h));
    const onlyOther = [...otherHooks].filter(h => !localHooks.has(h));
    const both = [...localHooks].filter(h => otherHooks.has(h));

    if (onlyLocal.length > 0 || onlyOther.length > 0) {
      console.log(c.bold + '  ' + trigger + c.reset);
      for (const h of both) console.log(c.dim + '    = ' + h + c.reset);
      for (const h of onlyLocal) { console.log(c.green + '    + ' + h + ' (local only)' + c.reset); diffs++; }
      for (const h of onlyOther) { console.log(c.red + '    - ' + h + ' (other only)' + c.reset); diffs++; }
      console.log();
    }
  }

  // Compare permissions
  const localAllow = getAllow(local);
  const otherAllow = getAllow(other);
  const onlyLocalAllow = localAllow.filter(a => !otherAllow.includes(a));
  const onlyOtherAllow = otherAllow.filter(a => !localAllow.includes(a));

  if (onlyLocalAllow.length > 0 || onlyOtherAllow.length > 0) {
    console.log(c.bold + '  permissions.allow' + c.reset);
    for (const a of onlyLocalAllow) { console.log(c.green + '    + ' + a + ' (local only)' + c.reset); diffs++; }
    for (const a of onlyOtherAllow) { console.log(c.red + '    - ' + a + ' (other only)' + c.reset); diffs++; }
    console.log();
  }

  // Compare deny
  const localDeny = getDeny(local);
  const otherDeny = getDeny(other);
  const onlyLocalDeny = localDeny.filter(a => !otherDeny.includes(a));
  const onlyOtherDeny = otherDeny.filter(a => !localDeny.includes(a));

  if (onlyLocalDeny.length > 0 || onlyOtherDeny.length > 0) {
    console.log(c.bold + '  permissions.deny' + c.reset);
    for (const d of onlyLocalDeny) { console.log(c.green + '    + ' + d + ' (local only)' + c.reset); diffs++; }
    for (const d of onlyOtherDeny) { console.log(c.red + '    - ' + d + ' (other only)' + c.reset); diffs++; }
    console.log();
  }

  // Compare mode
  if ((local.defaultMode || 'default') !== (other.defaultMode || 'default')) {
    console.log(c.bold + '  defaultMode' + c.reset);
    console.log(c.green + '    local: ' + (local.defaultMode || 'default') + c.reset);
    console.log(c.red + '    other: ' + (other.defaultMode || 'default') + c.reset);
    console.log();
    diffs++;
  }

  if (diffs === 0) {
    console.log(c.green + '  No differences found.' + c.reset);
  } else {
    console.log(c.dim + '  ' + diffs + ' difference(s) found.' + c.reset);
  }
  console.log();
}

async function lint() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --lint' + c.reset);
  console.log(c.dim + '  Static analysis of hook configuration...' + c.reset);
  console.log();

  if (!existsSync(SETTINGS_PATH)) {
    console.log(c.red + '  No settings.json found.' + c.reset);
    process.exit(1);
  }

  let settings;
  try {
    settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
  } catch (e) {
    console.log(c.red + '  settings.json parse error: ' + e.message + c.reset);
    process.exit(1);
  }

  let warnings = 0;
  let errors = 0;
  const warn = (msg) => { console.log(c.yellow + '  WARN: ' + c.reset + msg); warnings++; };
  const error = (msg) => { console.log(c.red + '  ERROR: ' + c.reset + msg); errors++; };
  const info = (msg) => { console.log(c.green + '  OK: ' + c.reset + msg); };

  const hooks = settings.hooks || {};

  // 1. Check for duplicate hook commands within same trigger
  for (const [trigger, entries] of Object.entries(hooks)) {
    const commands = [];
    for (const entry of entries) {
      for (const h of (entry.hooks || [])) {
        if (h.command) {
          if (commands.includes(h.command)) {
            warn(trigger + ': duplicate hook "' + h.command.split('/').pop() + '"');
          }
          commands.push(h.command);
        }
      }
    }
    if (commands.length > 0 && new Set(commands).size === commands.length) {
      info(trigger + ': no duplicates (' + commands.length + ' hooks)');
    }
  }

  // 2. Check for empty matcher on PreToolUse (runs on every tool = slow)
  for (const entry of (hooks.PreToolUse || [])) {
    if (!entry.matcher || entry.matcher === '') {
      const hookNames = (entry.hooks || []).map(h => (h.command || '').split('/').pop()).join(', ');
      warn('PreToolUse hook with empty matcher runs on EVERY tool call: ' + hookNames);
    }
  }

  // 3. Check for empty matcher on PostToolUse with heavy scripts
  for (const entry of (hooks.PostToolUse || [])) {
    if (!entry.matcher || entry.matcher === '') {
      const hookNames = (entry.hooks || []).map(h => (h.command || '').split('/').pop()).join(', ');
      // Check if any of these scripts are large (>5KB = potentially slow)
      for (const h of (entry.hooks || [])) {
        if (h.command) {
          const resolved = h.command.replace(/^(bash|sh|node)\s+/, '').split(/\s+/)[0].replace(/^~/, HOME);
          try {
            const { statSync } = await import('fs');
            const size = statSync(resolved).size;
            if (size > 5000) {
              warn('PostToolUse empty matcher + large script (' + (size/1024).toFixed(1) + 'KB): ' + resolved.split('/').pop());
            }
          } catch {}
        }
      }
    }
  }

  // 4. Check for hooks that exist in settings but script is missing
  for (const [trigger, entries] of Object.entries(hooks)) {
    for (const entry of entries) {
      for (const h of (entry.hooks || [])) {
        if (h.command) {
          let scriptPath = h.command.replace(/^(bash|sh|node|python3?)\s+/, '').split(/\s+/)[0];
          scriptPath = scriptPath.replace(/^~/, HOME);
          if (!existsSync(scriptPath)) {
            error(trigger + ': missing script "' + scriptPath.split('/').pop() + '"');
          }
        }
      }
    }
  }

  // 5. Check for overly broad allow rules combined with no hooks
  const allows = settings.permissions?.allow || [];
  if (allows.includes('Bash(*)') && (hooks.PreToolUse || []).length === 0) {
    error('Bash(*) in allow list with no PreToolUse hooks = no safety net');
  } else if (allows.includes('Bash(*)') && (hooks.PreToolUse || []).length > 0) {
    info('Bash(*) with PreToolUse hooks = hooks provide safety');
  }

  // 6. Check for conflicting allow and deny
  const denies = settings.permissions?.deny || [];
  for (const d of denies) {
    if (allows.includes(d)) {
      warn('Same pattern in both allow and deny: ' + d);
    }
  }

  // 7. Check total hook count and warn about performance
  let totalHooks = 0;
  for (const entries of Object.values(hooks)) {
    for (const entry of entries) {
      totalHooks += (entry.hooks || []).length;
    }
  }
  if (totalHooks > 20) {
    warn(totalHooks + ' total hooks registered — may slow down tool calls');
  } else if (totalHooks > 0) {
    info(totalHooks + ' hooks registered');
  }

  // 8. Check for hooks without type: "command"
  for (const [trigger, entries] of Object.entries(hooks)) {
    for (const entry of entries) {
      for (const h of (entry.hooks || [])) {
        if (h.type !== 'command') {
          warn(trigger + ': hook with type "' + h.type + '" (only "command" is supported)');
        }
      }
    }
  }

  // Summary
  console.log();
  if (errors === 0 && warnings === 0) {
    console.log(c.bold + c.green + '  Clean. No issues found.' + c.reset);
  } else if (errors === 0) {
    console.log(c.bold + c.yellow + '  ' + warnings + ' warning(s). No errors.' + c.reset);
  } else {
    console.log(c.bold + c.red + '  ' + errors + ' error(s), ' + warnings + ' warning(s).' + c.reset);
  }
  console.log();

  process.exit(errors > 0 ? 1 : 0);
}

async function createHook(description) {
  console.log();
  console.log(c.bold + '  cc-safe-setup --create' + c.reset);
  console.log(c.dim + '  Generating hook from: "' + description + '"' + c.reset);
  console.log();

  const desc = description.toLowerCase();

  // Pattern matching engine — matches description to hook templates
  const patterns = [
    {
      match: /block.*(npm\s+publish|yarn\s+publish|pnpm\s+publish)/,
      name: 'block-publish-without-tests',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '(npm|yarn|pnpm)\\s+publish'; then
    # Check if tests were run recently
    if [ -f "package.json" ]; then
        TEST_CMD=$(python3 -c "import json; print(json.load(open('package.json')).get('scripts',{}).get('test',''))" 2>/dev/null)
        if [ -n "$TEST_CMD" ]; then
            echo "BLOCKED: Run tests before publishing." >&2
            echo "Command: $COMMAND" >&2
            echo "Run: npm test && npm publish" >&2
            exit 2
        fi
    fi
fi
exit 0`,
    },
    {
      match: /block.*(docker\s+rm|docker\s+system\s+prune|docker.*(?:remove|delete|prune))/,
      name: 'block-docker-destructive',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qiE 'docker\\s+(system\\s+prune|rm\\s+-f|rmi\\s+-f|volume\\s+rm|network\\s+rm)'; then
    echo "BLOCKED: Destructive docker command." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi
exit 0`,
    },
    {
      match: /block.*(curl.*pipe|curl.*\|.*sh|wget.*pipe|wget.*\|)/,
      name: 'block-curl-pipe-sh',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '(curl|wget)\\s.*\\|\\s*(bash|sh|zsh|python)'; then
    echo "BLOCKED: Piping remote content to shell." >&2
    echo "Command: $COMMAND" >&2
    echo "Download first, review, then execute." >&2
    exit 2
fi
exit 0`,
    },
    {
      match: /block.*(pip\s+install|pip3\s+install).*(?:sudo|system|global)/,
      name: 'block-global-pip',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '(sudo\\s+)?(pip3?|python3?\\s+-m\\s+pip)\\s+install' && ! echo "$COMMAND" | grep -qE '(--user|venv|virtualenv|-e\\s+\\.)'; then
    echo "BLOCKED: pip install without --user or virtual environment." >&2
    echo "Command: $COMMAND" >&2
    echo "Use: pip install --user, or activate a virtualenv first." >&2
    exit 2
fi
exit 0`,
    },
    {
      match: /block.*(large\s+file|big\s+file|file\s+size|over\s+\d+)/,
      name: 'block-large-writes',
      trigger: 'PreToolUse', matcher: 'Write',
      script: `#!/bin/bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
SIZE=\${#CONTENT}
LIMIT=\${CC_MAX_WRITE_SIZE:-500000}
if [ "$SIZE" -gt "$LIMIT" ]; then
    echo "WARNING: Writing $SIZE bytes to $FILE (limit: $LIMIT)." >&2
    echo "Set CC_MAX_WRITE_SIZE to adjust the limit." >&2
    exit 2
fi
exit 0`,
    },
    {
      match: /block.*(drop\s+table|truncate|delete\s+from|alter\s+table)/,
      name: 'block-raw-sql-destructive',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qiE '(DROP\\s+TABLE|TRUNCATE\\s+TABLE|DELETE\\s+FROM\\s+[a-z]|ALTER\\s+TABLE.*DROP)'; then
    echo "BLOCKED: Destructive SQL command detected." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi
exit 0`,
    },
    {
      match: /auto.?approve.*(test|jest|pytest|mocha|vitest)/,
      name: 'auto-approve-tests',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\\s*(npm\\s+test|npx\\s+(jest|vitest|mocha)|pytest|python3?\\s+-m\\s+pytest|cargo\\s+test|go\\s+test)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"test command auto-approved"}}'
fi
exit 0`,
    },
    {
      match: /warn.*(todo|fixme|hack|xxx)/i,
      name: 'warn-todo-markers',
      trigger: 'PostToolUse', matcher: 'Edit|Write',
      script: `#!/bin/bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0
COUNT=$(grep -ciE '(TODO|FIXME|HACK|XXX)' "$FILE" 2>/dev/null || echo 0)
[ "$COUNT" -gt 0 ] && echo "NOTE: $FILE has $COUNT TODO/FIXME markers." >&2
exit 0`,
    },
    {
      match: /block.*(commit|push).*without.*(test|lint|check)/,
      name: 'block-commit-without-checks',
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE 'git\\s+(commit|push)' && ! echo "$COMMAND" | grep -qE '(--no-verify|--allow-empty)'; then
    if [ -f "package.json" ] && command -v npm &>/dev/null; then
        npm test --silent 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "BLOCKED: Tests failing. Fix tests before commit/push." >&2
            exit 2
        fi
    fi
fi
exit 0`,
    },
  ];

  // Find matching pattern
  let matched = null;
  for (const p of patterns) {
    if (p.match.test(desc)) {
      matched = p;
      break;
    }
  }

  if (!matched) {
    // Generate a generic blocking hook from the description
    const keywords = desc.match(/block\s+(.+)/i)?.[1] || desc;
    const sanitized = keywords.replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').slice(0, 30);
    matched = {
      name: 'custom-' + sanitized,
      trigger: 'PreToolUse', matcher: 'Bash',
      script: `#!/bin/bash
# Custom hook: ${description}
# Generated by cc-safe-setup --create
# Edit the grep pattern to match your specific commands
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
# TODO: Replace this pattern with the commands you want to block
if echo "$COMMAND" | grep -qiE '${keywords.replace(/'/g, '').replace(/\s+/g, '.*')}'; then
    echo "BLOCKED: ${description}" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi
exit 0`,
    };
    console.log(c.yellow + '  No exact template match. Generated a generic hook.' + c.reset);
    console.log(c.dim + '  Edit the grep pattern in the generated script.' + c.reset);
    console.log();
  }

  // Write the hook script
  mkdirSync(HOOKS_DIR, { recursive: true });
  const hookPath = join(HOOKS_DIR, matched.name + '.sh');
  writeFileSync(hookPath, matched.script);
  chmodSync(hookPath, 0o755);

  console.log(c.green + '  ✓ Created: ' + hookPath + c.reset);
  console.log(c.dim + '  Trigger: ' + matched.trigger + ', Matcher: ' + matched.matcher + c.reset);

  // Register in settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks[matched.trigger]) settings.hooks[matched.trigger] = [];

  // Check if already registered
  const existing = settings.hooks[matched.trigger].flatMap(e => (e.hooks || []).map(h => h.command));
  if (!existing.some(cmd => cmd.includes(matched.name))) {
    settings.hooks[matched.trigger].push({
      matcher: matched.matcher,
      hooks: [{ type: 'command', command: hookPath }],
    });
    writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
    console.log(c.green + '  ✓ Registered in settings.json' + c.reset);
  } else {
    console.log(c.dim + '  Already registered in settings.json' + c.reset);
  }

  // Quick test
  const { spawnSync } = await import('child_process');
  const testResult = spawnSync('bash', [hookPath], {
    input: '{}',
    timeout: 5000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  if (testResult.status === 0) {
    console.log(c.green + '  ✓ Hook passes empty input test' + c.reset);
  } else {
    console.log(c.yellow + '  ! Hook exits ' + testResult.status + ' on empty input (may need adjustment)' + c.reset);
  }

  console.log();
  console.log(c.dim + '  Test it: npx cc-hook-test ' + hookPath + c.reset);
  console.log(c.dim + '  Restart Claude Code to activate.' + c.reset);
  console.log();
}

async function stats() {
  const LOG_PATH = join(HOME, '.claude', 'blocked-commands.log');

  console.log();
  console.log(c.bold + '  cc-safe-setup --stats' + c.reset);
  console.log(c.dim + '  Block statistics from your hook history' + c.reset);
  console.log();

  if (!existsSync(LOG_PATH)) {
    console.log(c.dim + '  No blocked-commands.log found. Hooks haven\'t blocked anything yet.' + c.reset);
    console.log(c.dim + '  This is normal if you just installed hooks.' + c.reset);
    console.log();
    process.exit(0);
  }

  const lines = readFileSync(LOG_PATH, 'utf-8').split('\n').filter(l => l.trim());
  if (lines.length === 0) {
    console.log(c.dim + '  Log is empty. No blocks recorded yet.' + c.reset);
    console.log();
    process.exit(0);
  }

  // Parse log entries: [timestamp] BLOCKED: reason | cmd: command
  const entries = [];
  const reasonCounts = {};
  const hourCounts = {};
  const dayCounts = {};
  const commandPatterns = {};

  for (const line of lines) {
    const match = line.match(/^\[([^\]]+)\]\s*BLOCKED:\s*(.+?)\s*\|\s*cmd:\s*(.+)$/);
    if (!match) continue;

    const [, ts, reason, cmd] = match;
    const date = new Date(ts);
    const day = ts.split('T')[0];
    const hour = date.getHours();

    entries.push({ ts, reason: reason.trim(), cmd: cmd.trim(), date, day, hour });

    // Count reasons
    const r = reason.trim();
    reasonCounts[r] = (reasonCounts[r] || 0) + 1;

    // Count by hour
    hourCounts[hour] = (hourCounts[hour] || 0) + 1;

    // Count by day
    dayCounts[day] = (dayCounts[day] || 0) + 1;

    // Categorize commands
    const cmdLower = cmd.toLowerCase();
    let pattern = 'other';
    if (cmdLower.includes('rm ')) pattern = 'rm (delete)';
    else if (cmdLower.includes('git push')) pattern = 'git push';
    else if (cmdLower.includes('git reset')) pattern = 'git reset';
    else if (cmdLower.includes('git clean')) pattern = 'git clean';
    else if (cmdLower.includes('git add')) pattern = 'git add (secrets)';
    else if (cmdLower.includes('remove-item')) pattern = 'PowerShell delete';
    else if (cmdLower.includes('git checkout') || cmdLower.includes('git switch')) pattern = 'git checkout --force';
    commandPatterns[pattern] = (commandPatterns[pattern] || 0) + 1;
  }

  if (entries.length === 0) {
    console.log(c.dim + '  No parseable entries in log.' + c.reset);
    console.log();
    process.exit(0);
  }

  // Summary
  const firstDate = entries[0].day;
  const lastDate = entries[entries.length - 1].day;
  const daySpan = Object.keys(dayCounts).length;

  console.log(c.bold + '  Summary' + c.reset);
  console.log('  Total blocks: ' + c.bold + entries.length + c.reset);
  console.log('  Period: ' + firstDate + ' to ' + lastDate + ' (' + daySpan + ' days)');
  console.log('  Average: ' + (entries.length / Math.max(daySpan, 1)).toFixed(1) + ' blocks/day');
  console.log();

  // Top reasons
  console.log(c.bold + '  Top Block Reasons' + c.reset);
  const sortedReasons = Object.entries(reasonCounts).sort((a, b) => b[1] - a[1]);
  const maxReasonCount = sortedReasons[0]?.[1] || 1;
  for (const [reason, count] of sortedReasons.slice(0, 8)) {
    const bar = '█'.repeat(Math.ceil(count / maxReasonCount * 20));
    const pct = ((count / entries.length) * 100).toFixed(0);
    console.log('  ' + c.red + bar + c.reset + ' ' + count + ' (' + pct + '%) ' + reason);
  }
  console.log();

  // Command categories
  console.log(c.bold + '  Command Categories' + c.reset);
  const sortedPatterns = Object.entries(commandPatterns).sort((a, b) => b[1] - a[1]);
  for (const [pattern, count] of sortedPatterns) {
    const pct = ((count / entries.length) * 100).toFixed(0);
    console.log('  ' + c.yellow + count.toString().padStart(4) + c.reset + ' ' + pattern + ' (' + pct + '%)');
  }
  console.log();

  // Activity by hour
  console.log(c.bold + '  Blocks by Hour' + c.reset);
  const maxHour = Math.max(...Object.values(hourCounts), 1);
  for (let h = 0; h < 24; h++) {
    const count = hourCounts[h] || 0;
    if (count === 0) continue;
    const bar = '▓'.repeat(Math.ceil(count / maxHour * 15));
    console.log('  ' + h.toString().padStart(2) + ':00 ' + c.blue + bar + c.reset + ' ' + count);
  }
  console.log();

  // Recent blocks (last 5)
  console.log(c.bold + '  Recent Blocks' + c.reset);
  for (const entry of entries.slice(-5)) {
    const time = entry.ts.replace(/T/, ' ').replace(/\+.*/, '');
    console.log('  ' + c.dim + time + c.reset + ' ' + entry.reason);
    console.log('    ' + c.dim + entry.cmd.slice(0, 100) + c.reset);
  }
  console.log();
}

async function exportConfig() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --export' + c.reset);
  console.log(c.dim + '  Exporting hooks config for team sharing...' + c.reset);
  console.log();

  if (!existsSync(SETTINGS_PATH)) {
    console.log(c.red + '  No settings.json found. Run npx cc-safe-setup first.' + c.reset);
    process.exit(1);
  }

  const settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
  const hooks = settings.hooks || {};

  // Collect installed hook scripts
  const exportData = {
    version: '1.0',
    generator: 'cc-safe-setup',
    exported_at: new Date().toISOString(),
    hooks: {},
    scripts: {},
  };

  // Copy hook configuration
  exportData.hooks = JSON.parse(JSON.stringify(hooks));

  // Read and embed script contents
  const scriptPaths = new Set();
  for (const trigger of Object.keys(hooks)) {
    for (const entry of hooks[trigger]) {
      for (const h of (entry.hooks || [])) {
        if (h.type === 'command' && h.command) {
          let scriptPath = h.command.replace(/^(bash|sh|node)\s+/, '').split(/\s+/)[0];
          scriptPath = scriptPath.replace(/^~/, HOME);
          if (existsSync(scriptPath)) {
            const relName = scriptPath.replace(HOME, '~');
            exportData.scripts[relName] = readFileSync(scriptPath, 'utf-8');
            scriptPaths.add(relName);
          }
        }
      }
    }
  }

  const outputFile = 'cc-safe-setup-export.json';
  writeFileSync(outputFile, JSON.stringify(exportData, null, 2));

  console.log(c.green + '  ✓ Exported to ' + outputFile + c.reset);
  console.log(c.dim + '  Contains: ' + Object.keys(exportData.hooks).length + ' trigger types, ' + scriptPaths.size + ' hook scripts' + c.reset);
  console.log();
  console.log(c.dim + '  Share this file with your team. They can import with:' + c.reset);
  console.log(c.bold + '  npx cc-safe-setup --import ' + outputFile + c.reset);
  console.log();
}

async function importConfig(file) {
  console.log();
  console.log(c.bold + '  cc-safe-setup --import ' + file + c.reset);
  console.log(c.dim + '  Importing hooks config...' + c.reset);
  console.log();

  if (!existsSync(file)) {
    console.log(c.red + '  File not found: ' + file + c.reset);
    process.exit(1);
  }

  let exportData;
  try {
    exportData = JSON.parse(readFileSync(file, 'utf-8'));
  } catch (e) {
    console.log(c.red + '  Invalid JSON in ' + file + c.reset);
    process.exit(1);
  }

  if (!exportData.hooks || !exportData.scripts) {
    console.log(c.red + '  Invalid export file (missing hooks or scripts section)' + c.reset);
    process.exit(1);
  }

  // Install scripts
  mkdirSync(HOOKS_DIR, { recursive: true });
  let installed = 0;

  for (const [relPath, content] of Object.entries(exportData.scripts)) {
    const absPath = relPath.replace(/^~/, HOME);
    const dir = dirname(absPath);
    mkdirSync(dir, { recursive: true });
    writeFileSync(absPath, content);
    chmodSync(absPath, 0o755);
    console.log(c.green + '  ✓ ' + c.reset + relPath);
    installed++;
  }

  // Merge hooks into settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try {
      settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
    } catch {}
  }

  if (!settings.hooks) settings.hooks = {};

  for (const [trigger, entries] of Object.entries(exportData.hooks)) {
    if (!settings.hooks[trigger]) settings.hooks[trigger] = [];
    // Add entries that don't already exist (by command path)
    const existing = new Set(
      settings.hooks[trigger].flatMap(e => (e.hooks || []).map(h => h.command))
    );
    for (const entry of entries) {
      const newCommands = (entry.hooks || []).filter(h => !existing.has(h.command));
      if (newCommands.length > 0) {
        settings.hooks[trigger].push({ ...entry, hooks: newCommands });
      }
    }
  }

  mkdirSync(dirname(SETTINGS_PATH), { recursive: true });
  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));

  console.log();
  console.log(c.bold + c.green + '  ✓ Imported ' + installed + ' hook scripts' + c.reset);
  console.log(c.dim + '  Restart Claude Code to activate.' + c.reset);
  console.log();
}

async function watch() {
  const { spawn } = await import('child_process');
  const { createReadStream, watchFile } = await import('fs');
  const { createInterface: createRL } = await import('readline');

  const LOG_PATH = join(HOME, '.claude', 'blocked-commands.log');
  const ERROR_LOG = join(HOME, '.claude', 'session-errors.log');

  console.log();
  console.log(c.bold + '  cc-safe-setup --watch' + c.reset);
  console.log(c.dim + '  Live safety dashboard — watching blocked commands' + c.reset);
  console.log(c.dim + '  Log: ' + LOG_PATH + c.reset);
  console.log();

  let blockCount = 0;
  let lastPrint = 0;

  function formatLine(line) {
    // Format: [2026-03-24T01:30:00+09:00] BLOCKED: reason | cmd: actual command
    const match = line.match(/^\[([^\]]+)\]\s*BLOCKED:\s*(.+?)\s*\|\s*cmd:\s*(.+)$/);
    if (!match) return c.dim + '  ' + line + c.reset;

    const [, ts, reason, cmd] = match;
    const time = ts.replace(/T/, ' ').replace(/\+.*/, '');
    blockCount++;

    let severity = c.yellow;
    if (reason.match(/rm|reset|clean|Remove-Item|drop/i)) severity = c.red;
    if (reason.match(/push|force/i)) severity = c.red;
    if (reason.match(/env|secret|credential/i)) severity = c.red;

    return severity + '  BLOCKED' + c.reset + ' ' + c.dim + time + c.reset + '\n' +
           '    ' + c.bold + reason.trim() + c.reset + '\n' +
           '    ' + c.dim + cmd.trim().slice(0, 120) + c.reset;
  }

  function printStats() {
    const now = Date.now();
    if (now - lastPrint < 30000) return;
    lastPrint = now;
    console.log(c.dim + '  --- ' + blockCount + ' blocks total | ' + new Date().toLocaleTimeString() + ' ---' + c.reset);
  }

  // Print existing log entries
  if (existsSync(LOG_PATH)) {
    const rl = createRL({ input: createReadStream(LOG_PATH) });
    for await (const line of rl) {
      if (line.trim()) console.log(formatLine(line));
    }
    if (blockCount > 0) {
      console.log();
      console.log(c.dim + '  === History: ' + blockCount + ' blocks ===' + c.reset);
      console.log(c.dim + '  Watching for new blocks... (Ctrl+C to stop)' + c.reset);
      console.log();
    }
  } else {
    console.log(c.dim + '  No blocked-commands.log yet. Hooks will create it on first block.' + c.reset);
    console.log(c.dim + '  Watching... (Ctrl+C to stop)' + c.reset);
    console.log();
  }

  // Watch for new entries using tail -f
  let tailProcess;
  try {
    // Ensure log file exists for tail
    if (!existsSync(LOG_PATH)) {
      const { mkdirSync: mkDir, writeFileSync: writeFile } = await import('fs');
      mkDir(dirname(LOG_PATH), { recursive: true });
      writeFile(LOG_PATH, '', 'utf-8');
    }

    tailProcess = spawn('tail', ['-f', '-n', '0', LOG_PATH], { stdio: ['ignore', 'pipe', 'ignore'] });

    const tailRL = createRL({ input: tailProcess.stdout });
    for await (const line of tailRL) {
      if (line.trim()) {
        console.log(formatLine(line));
        printStats();
      }
    }
  } catch (e) {
    // tail not available — fall back to polling
    let lastSize = 0;
    try {
      const { statSync } = await import('fs');
      lastSize = statSync(LOG_PATH).size;
    } catch {}

    console.log(c.dim + '  (tail not available, using polling)' + c.reset);

    setInterval(async () => {
      try {
        const { statSync, readFileSync: readFile } = await import('fs');
        const stat = statSync(LOG_PATH);
        if (stat.size > lastSize) {
          const content = readFile(LOG_PATH, 'utf-8');
          const lines = content.split('\n').slice(-10);
          for (const line of lines) {
            if (line.trim()) console.log(formatLine(line));
          }
          lastSize = stat.size;
          printStats();
        }
      } catch {}
    }, 2000);

    // Keep process alive
    await new Promise(() => {});
  }
}

async function doctor() {
  const { execSync, spawnSync } = await import('child_process');
  const { statSync, readdirSync } = await import('fs');

  console.log();
  console.log(c.bold + '  cc-safe-setup --doctor' + c.reset);
  console.log(c.dim + '  Diagnosing why hooks might not be working...' + c.reset);
  console.log();

  let issues = 0;
  let warnings = 0;

  const pass = (msg) => console.log(c.green + '  ✓ ' + c.reset + msg);
  const fail = (msg) => { console.log(c.red + '  ✗ ' + c.reset + msg); issues++; };
  const warn = (msg) => { console.log(c.yellow + '  ! ' + c.reset + msg); warnings++; };

  // 1. Check jq
  try {
    execSync('which jq', { stdio: 'pipe' });
    const ver = execSync('jq --version', { stdio: 'pipe' }).toString().trim();
    pass('jq installed (' + ver + ')');
  } catch {
    fail('jq is not installed — hooks cannot parse JSON input');
    console.log(c.dim + '    Fix: brew install jq (macOS) | apt install jq (Linux) | choco install jq (Windows)' + c.reset);
  }

  // 2. Check settings.json exists
  if (!existsSync(SETTINGS_PATH)) {
    fail('~/.claude/settings.json does not exist');
    console.log(c.dim + '    Fix: npx cc-safe-setup' + c.reset);
  } else {
    pass('settings.json exists');

    // 3. Parse settings.json
    let settings;
    try {
      settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      pass('settings.json is valid JSON');
    } catch (e) {
      fail('settings.json has invalid JSON: ' + e.message);
      console.log(c.dim + '    Fix: npx cc-safe-setup --uninstall && npx cc-safe-setup' + c.reset);
    }

    if (settings) {
      // 4. Check hooks section exists
      const hooks = settings.hooks;
      if (!hooks) {
        fail('No "hooks" section in settings.json');
      } else {
        pass('"hooks" section exists in settings.json');

        // 5. Check each hook trigger type
        for (const trigger of ['PreToolUse', 'PostToolUse', 'Stop']) {
          const entries = hooks[trigger] || [];
          if (entries.length > 0) {
            pass(trigger + ': ' + entries.length + ' hook(s) registered');

            // 6. Check each hook command path
            for (const entry of entries) {
              const hookList = entry.hooks || [];
              for (const h of hookList) {
                if (h.type !== 'command') continue;
                const cmd = h.command;
                // Extract the script path from commands like "bash ~/.claude/hooks/x.sh" or "~/bin/x.sh arg1 arg2"
                let scriptPath = cmd;
                // Strip leading interpreter (bash, sh, node, python3, etc.)
                scriptPath = scriptPath.replace(/^(bash|sh|node|python3?)\s+/, '');
                // Take first token (before arguments)
                scriptPath = scriptPath.split(/\s+/)[0];
                // Resolve ~ to HOME
                const resolved = scriptPath.replace(/^~/, HOME);

                if (!existsSync(resolved)) {
                  fail('Hook script not found: ' + scriptPath + (scriptPath !== cmd ? ' (from: ' + cmd + ')' : ''));
                  console.log(c.dim + '    Fix: create the missing script or update settings.json' + c.reset);
                  continue;
                }

                // 7. Check executable permission
                try {
                  const stat = statSync(resolved);
                  const isExec = (stat.mode & 0o111) !== 0;
                  if (!isExec) {
                    fail('Not executable: ' + cmd);
                    console.log(c.dim + '    Fix: chmod +x ' + resolved + c.reset);
                  }
                } catch {}

                // 8. Check shebang
                try {
                  const content = readFileSync(resolved, 'utf-8');
                  if (!content.startsWith('#!/')) {
                    warn('Missing shebang (#!/bin/bash) in: ' + cmd);
                    console.log(c.dim + '    Add #!/bin/bash as the first line' + c.reset);
                  }
                } catch {}

                // 9. Test hook with empty input
                try {
                  const result = spawnSync('bash', [resolved], {
                    input: '{}',
                    timeout: 5000,
                    stdio: ['pipe', 'pipe', 'pipe'],
                  });
                  if (result.status !== 0 && result.status !== 2) {
                    warn('Hook exits with code ' + result.status + ' on empty input: ' + cmd);
                    const stderr = (result.stderr || '').toString().trim();
                    if (stderr) console.log(c.dim + '    stderr: ' + stderr.slice(0, 200) + c.reset);
                  }
                } catch {}
              }
            }
          }
        }
      }

      // 10. Check for common misconfigurations
      if (settings.defaultMode === 'bypassPermissions') {
        warn('defaultMode is "bypassPermissions" — hooks may be skipped entirely');
        console.log(c.dim + '    Consider using "dontAsk" instead (hooks still run)' + c.reset);
      }

      // 11. Check for dangerouslySkipPermissions in allow
      const allows = settings.permissions?.allow || [];
      if (allows.includes('Bash(*)')) {
        warn('Bash(*) in allow list — commands auto-approved before hooks run');
      }
    }
  }

  // 12. Check hooks directory
  if (!existsSync(HOOKS_DIR)) {
    fail('~/.claude/hooks/ directory does not exist');
    console.log(c.dim + '    Fix: npx cc-safe-setup' + c.reset);
  } else {
    const files = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'));
    pass('hooks directory exists (' + files.length + ' scripts)');
  }

  // 13. Check Claude Code version (needs hooks support)
  try {
    const ver = execSync('claude --version 2>/dev/null || echo "not found"', { stdio: 'pipe' }).toString().trim();
    if (ver === 'not found') {
      warn('Claude Code CLI not found in PATH');
    } else {
      pass('Claude Code: ' + ver);
    }
  } catch {
    warn('Could not check Claude Code version');
  }

  // Summary
  console.log();
  if (issues === 0 && warnings === 0) {
    console.log(c.bold + c.green + '  All checks passed. Hooks should be working.' + c.reset);
    console.log(c.dim + '  If hooks still don\'t fire, restart Claude Code (hooks load on startup).' + c.reset);
  } else if (issues === 0) {
    console.log(c.bold + c.yellow + '  ' + warnings + ' warning(s), but no blocking issues.' + c.reset);
    console.log(c.dim + '  Hooks should work. Restart Claude Code if they don\'t fire.' + c.reset);
  } else {
    console.log(c.bold + c.red + '  ' + issues + ' issue(s) found that prevent hooks from working.' + c.reset);
    console.log(c.dim + '  Fix the issues above, then restart Claude Code.' + c.reset);
  }
  console.log();

  process.exit(issues > 0 ? 1 : 0);
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
  if (DOCTOR) return doctor();
  if (WATCH) return watch();
  if (GENERATE_CI) return generateCI();
  if (MIGRATE) return migrate();
  if (COMPARE) return compare(COMPARE.a, COMPARE.b);
  if (ISSUES) return issues();
  if (DASHBOARD) return dashboard();
  if (BENCHMARK) return benchmark();
  if (SHARE) return share();
  if (DIFF_FILE) return diff(DIFF_FILE);
  if (LINT) return lint();
  if (CREATE_DESC) return createHook(CREATE_DESC);
  if (STATS) return stats();
  if (EXPORT) return exportConfig();
  if (IMPORT_FILE) return importConfig(IMPORT_FILE);

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
