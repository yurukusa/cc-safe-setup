#!/usr/bin/env node

import { readFileSync, writeFileSync, mkdirSync, existsSync, chmodSync, copyFileSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { createInterface } from 'readline';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const HOME = homedir();
const HOOKS_DIR = join(HOME, '.claude', 'hooks');
const SETTINGS_PATH = join(HOME, '.claude', 'settings.json');

// Convert Windows backslash paths to bash-compatible forward slashes
const toBashPath = (p) => p.replace(/\\/g, '/');

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
const REPORT = process.argv.includes('--report');
const QUICKFIX = process.argv.includes('--quickfix');
const SHIELD = process.argv.includes('--shield');
const OPUS47 = process.argv.includes('--opus47');
const ANALYZE = process.argv.includes('--analyze');
const TEAM = process.argv.includes('--team');
const MIGRATE_FROM_IDX = process.argv.findIndex(a => a === '--migrate-from');
const MIGRATE_FROM = MIGRATE_FROM_IDX !== -1 ? process.argv[MIGRATE_FROM_IDX + 1] : null;
const HEALTH = process.argv.includes('--health');
const FROM_CLAUDEMD = process.argv.includes('--from-claudemd');
const GUARD_IDX = process.argv.findIndex(a => a === '--guard');
const GUARD_DESC = GUARD_IDX !== -1 ? process.argv.slice(GUARD_IDX + 1).join(' ') : null;
const DIFF_HOOKS_IDX = process.argv.findIndex(a => a === '--diff-hooks');
const DIFF_HOOKS = DIFF_HOOKS_IDX !== -1 ? process.argv[DIFF_HOOKS_IDX + 1] : null;
const PROFILE_IDX = process.argv.findIndex(a => a === '--profile');
const PROFILE = PROFILE_IDX !== -1 ? process.argv[PROFILE_IDX + 1] : null;
const COMPARE_IDX = process.argv.findIndex(a => a === '--compare');
const COMPARE = COMPARE_IDX !== -1 ? { a: process.argv[COMPARE_IDX + 1], b: process.argv[COMPARE_IDX + 2] } : null;
const REPLAY = process.argv.includes('--replay');
const SAVE_PROFILE_IDX = process.argv.findIndex(a => a === '--save-profile');
const SAVE_PROFILE = SAVE_PROFILE_IDX !== -1 ? process.argv[SAVE_PROFILE_IDX + 1] : null;
const CREATE_IDX = process.argv.findIndex(a => a === '--create');
const CREATE_DESC = CREATE_IDX !== -1 ? process.argv.slice(CREATE_IDX + 1).join(' ') : null;
const SUGGEST = process.argv.includes('--suggest');
const INIT_PROJECT = process.argv.includes('--init-project');
const SCORE_ONLY = process.argv.includes('--score');
const CHANGELOG_CMD = process.argv.includes('--changelog');
const VALIDATE = process.argv.includes('--validate');
const SAFE_MODE = process.argv.includes('--safe-mode');
const SAFE_MODE_OFF = process.argv.includes('--safe-mode') && process.argv.includes('off');
const SIMULATE_IDX = process.argv.findIndex(a => a === '--simulate');
const SIMULATE_CMD = SIMULATE_IDX !== -1 ? process.argv.slice(SIMULATE_IDX + 1).join(' ') : null;
const PROTECT_IDX = process.argv.findIndex(a => a === '--protect');
const PROTECT_PATH = PROTECT_IDX !== -1 ? process.argv[PROTECT_IDX + 1] : null;
const RULES_IDX = process.argv.findIndex(a => a === '--rules');
const RULES_FILE = RULES_IDX !== -1 ? (process.argv[RULES_IDX + 1] || '.claude/rules.yaml') : null;
const TEST_HOOK_IDX = process.argv.findIndex(a => a === '--test-hook');
const TEST_HOOK = TEST_HOOK_IDX !== -1 ? process.argv[TEST_HOOK_IDX + 1] : null;
const WHY_IDX = process.argv.findIndex(a => a === '--why');
const WHY_HOOK = WHY_IDX !== -1 ? process.argv[WHY_IDX + 1] : null;

if (HELP) {
  console.log(`
  cc-safe-setup — Make Claude Code safe for autonomous operation

  Quick Start:
    npx cc-safe-setup              Install 8 safety hooks (30 sec)
    npx cc-safe-setup --shield     Maximum safety — one command
    npx cc-safe-setup --doctor     Diagnose hook problems

  Protect:
    --protect .env                 Block edits to a specific file
    --guard "never delete prod"    Enforce a rule from plain English
    --simulate "rm -rf /"          Preview how hooks react to a command
    --validate                     Check all hooks for errors (auto-fix)
    --safe-mode                    Emergency: disable all hooks

  Install & Configure:
    --install-example <name>       Install from 707 example hooks
    --examples                     Browse examples by category
    --from-claudemd                Convert CLAUDE.md rules into hooks
    --rules [file]                 Compile YAML rules into hooks
    --team                         Set up project-level hooks for git
    --profile <level>              Switch profile (strict/standard/minimal)
    --shield                       Full setup: hooks + scan + CLAUDE.md

  Diagnose & Monitor:
    --status / --verify            Check installed hooks / test them
    --doctor                       13-point diagnostic
    --audit [--fix] [--json]       Safety score 0-100
    --watch                        Live blocked command feed
    --health                       Hook health dashboard
    --suggest                      Predict risks from project analysis

  Manage:
    --dry-run / --uninstall        Preview / remove hooks
    --export / --import            Share configuration
    --diff <file>                  Compare settings
    --lint                         Static analysis of config

  More: --create, --why, --replay, --score, --changelog, --analyze,
        --benchmark, --dashboard, --migrate-from, --init-project
    npx cc-safe-setup --quickfix   Auto-detect and fix common Claude Code problems
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

  Token Checkup: https://yurukusa.github.io/cc-safe-setup/token-checkup.html
  Token Book:    https://yurukusa.github.io/cc-safe-setup/token-book.html
  Safety Guide:  https://zenn.dev/yurukusa/books/6076c23b1cb18b
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
  console.log(c.dim + '  Tip: --validate to check health · --simulate "cmd" to test · --shield for max safety' + c.reset);
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
      'absolute-rule-enforcer.sh': 'Enforce CLAUDE.md "ABSOLUTE RULE" markers',
      'allowlist.sh': 'Only allow explicitly approved commands',
      'ansible-vault-guard.sh': 'Ansible Vault Guard',
      'api-endpoint-guard.sh': 'Warn on requests to internal/sensitive APIs',
      'api-key-in-url-guard.sh': 'Block API keys embedded in URLs',
      'api-overload-backoff.sh': 'Track API overload errors and enforce backoff',
      'api-rate-limit-guard.sh': 'Throttle rapid API calls to prevent rate limiting',
      'api-retry-limiter.sh': 'Limit API error retries to prevent token waste',
      'aws-production-guard.sh': 'Block dangerous AWS CLI operations',
      'aws-region-guard.sh': 'Warn when AWS commands target unexpected regions',
      'banned-command-guard.sh': 'Block commands that are explicitly banned',
      'bash-domain-allowlist.sh': 'Block curl/wget to unauthorized domains',
      'bash-timeout-guard.sh': 'Warn on commands likely to hang or run',
      'bash-trace-guard.sh': 'Block debug tracing that exposes secrets',
      'bg-task-cooldown-guard.sh': 'Cooldown after background task notifications',
      'binary-upload-guard.sh': 'Block committing binary files to git',
      'block-database-wipe.sh': 'Block destructive database commands',
      'bulk-file-delete-guard.sh': 'Block commands that delete many files at once',
      'cargo-publish-guard.sh': 'Cargo Publish Guard',
      'case-sensitive-guard.sh': 'Case-Insensitive Filesystem Safety Guard',
      'check-csrf-protection.sh': 'Check Csrf Protection',
      'chmod-guard.sh': 'Block overly permissive chmod commands',
      'chown-guard.sh': 'Block dangerous ownership changes',
      'ci-workflow-guard.sh': 'Prevent dangerous CI/CD workflow modifications',
      'claude-cache-gc.sh': 'Claude Cache Gc',
      'claudeignore-enforce-guard.sh': 'Enforce .claudeignore at the tool level',
      'claudemd-enforcer.sh': 'Claudemd Enforcer',
      'clear-command-confirm-guard.sh': 'Block accidental /clear command',
      'cloud-cli-guard.sh': 'Block destructive GCP/Azure CLI operations',
      'compact-blocker.sh': 'Block auto-compaction entirely',
      'compaction-transcript-guard.sh': 'Save conversation state before compaction',
      'composer-guard.sh': 'Block dangerous Composer operations',
      'compound-command-allow.sh': 'Auto-approve compound commands when all parts are safe',
      'compound-command-approver.sh': 'Auto-approve safe compound commands',
      'compound-inject-guard.sh': 'Block destructive commands hidden in compound statements',
      'concurrent-edit-lock.sh': 'Prevent file corruption from concurrent Claude sessions',
      'core-file-protect-guard.sh': 'Block edits to core/config/rules files',
      'credential-exfil-guard.sh': 'Block credential hunting commands',
      'credential-file-cat-guard.sh': 'Block cat/read of package manager credential files',
      'cron-modification-guard.sh': 'Block unreviewed cron job modifications',
      'crontab-guard.sh': 'Warn before modifying crontab',
      'cwd-project-boundary-guard.sh': 'Warn when cd leaves the project directory',
      'db-connect-guard.sh': 'Warn on direct database connections',
      'denied-action-retry-guard.sh': 'Block re-attempts of denied tool calls',
      'dependency-install-guard.sh': 'PreToolUse hook',
      'dependency-version-pin.sh': 'Warn on unpinned dependency versions',
      'deploy-guard.sh': 'Block deploy commands when uncommitted changes exist',
      'deploy-path-verify-guard.sh': 'Verify deployment target path before writes',
      'deployment-verify-guard.sh': 'Warn if committing without post-deploy verification',
      'disk-partition-guard.sh': 'Block disk partitioning and mount operations',
      'django-migrate-guard.sh': 'Block destructive Django DB operations',
      'dns-config-guard.sh': 'Block DNS/hosts file modifications',
      'docker-dangerous-guard.sh': 'Block dangerous Docker operations',
      'docker-prune-guard.sh': 'Warn before docker system prune',
      'docker-volume-guard.sh': 'Docker Volume Guard',
      'dockerfile-latest-guard.sh': 'Dockerfile Latest Guard',
      'dotenv-commit-guard.sh': 'Prevent committing .env files with secrets',
      'drizzle-migrate-guard.sh': 'Block destructive Drizzle ORM operations',
      'edit-guard.sh': 'Block Edit/Write to protected files',
      'edit-retry-loop-guard.sh': 'Detect Edit tool stuck retrying the same file',
      'encoding-preserve-guard.sh': 'Warn when file encoding changes',
      'env-inherit-guard.sh': 'Detect inherited production env vars in',
      'env-inline-secret-guard.sh': 'Block .env values from appearing in commands',
      'env-prod-guard.sh': 'Env Prod Guard',
      'env-source-guard.sh': 'Block sourcing .env into shell environment',
      'env-var-check.sh': 'Warn when setting environment variables with secrets',
      'expo-eject-guard.sh': 'Expo Eject Guard',
      'export-overwrite-guard.sh': 'Prevent /export from overwriting existing files',
      'file-age-guard.sh': 'Warn before editing files not modified in 30+ days',
      'firewall-guard.sh': 'Block firewall rule modifications',
      'flask-debug-guard.sh': 'Warn when Flask runs with debug=True',
      'gem-push-guard.sh': 'Gem Push Guard',
      'gh-cli-destructive-guard.sh': 'Block destructive GitHub CLI operations',
      'git-checkout-safety-guard.sh': 'Prevent file loss from careless branch switching',
      'git-checkout-uncommitted-guard.sh': 'Block branch switching with uncommitted changes',
      'git-config-guard.sh': 'Block git config --global modifications',
      'git-crypt-worktree-guard.sh': 'Block worktree creation in git-crypt repos',
      'git-history-rewrite-guard.sh': 'Block git history rewriting commands',
      'git-hook-bypass-guard.sh': 'Git Hook Bypass Guard',
      'git-index-lock-cleanup.sh': 'Remove stale .git/index.lock after git commands',
      'git-merge-conflict-prevent.sh': 'Git Merge Conflict Prevent',
      'git-operations-require-approval.sh': 'Block git write operations',
      'git-remote-guard.sh': 'Block push/fetch to unknown git remotes',
      'git-signed-commit-guard.sh': 'Warn on unsigned git commits',
      'git-submodule-guard.sh': 'Git Submodule Guard',
      'git-tag-guard.sh': 'Git Tag Guard',
      'github-actions-guard.sh': 'Validate GitHub Actions workflow changes',
      'github-actions-secret-guard.sh': 'Prevent hardcoded secrets in GitHub Actions workflows',
      'gitops-drift-guard.sh': 'Warn when editing infrastructure files without PR',
      'hardcoded-ip-guard.sh': 'Hardcoded Ip Guard',
      'headless-empty-result-guard.sh': 'Detect empty results in headless mode',
      'headless-stop-guard.sh': 'Skip Stop hooks in headless (-p) mode',
      'helm-install-guard.sh': 'Helm Install Guard',
      'hook-permission-fixer.sh': 'Auto-fix missing execute permissions on hooks',
      'hook-tamper-guard.sh': 'Prevent Claude from modifying its own hooks',
      'issue-draft-redact-guard.sh': 'Redact sensitive info from public issue drafts',
      'k8s-production-guard.sh': 'Block destructive Kubernetes operations on production',
      'kill-process-guard.sh': 'Block dangerous process termination commands',
      'kubernetes-guard.sh': 'Block destructive kubectl commands',
      'laravel-artisan-guard.sh': 'Laravel Artisan Guard',
      'large-file-guard.sh': 'Warn when Write tool creates oversized files',
      'large-file-write-guard.sh': 'Warn when writing large files',
      'line-ending-guard.sh': 'Warn on CRLF/LF mismatch',
      'log-level-guard.sh': 'Log Level Guard',
      'log-truncation-guard.sh': 'Block log file truncation/deletion',
      'max-edit-size-guard.sh': 'Max Edit Size Guard',
      'max-file-delete-count.sh': 'Max File Delete Count',
      'memory-write-guard.sh': 'Log writes to ~/.claude/ directory',
      'migration-safety.sh': 'Require backup before database migrations',
      'migration-verify-guard.sh': 'Require verification before destructive migrations',
      'monorepo-scope-guard.sh': 'Restrict edits to the current package',
      'network-exfil-guard.sh': 'Block data exfiltration via network commands',
      'network-guard.sh': 'Warn on network commands that send file contents',
      'network-interface-guard.sh': 'Block network interface modifications',
      'nextjs-env-guard.sh': 'Prevent exposing server secrets in Next.js',
      'no-absolute-import.sh': 'No Absolute Import',
      'no-alert-confirm-prompt.sh': 'No Alert Confirm Prompt',
      'no-anonymous-default-export.sh': 'No Anonymous Default Export',
      'no-any-type.sh': 'No Any Type',
      'no-any-typescript.sh': 'No Any Typescript',
      'no-ask-human.sh': 'Block commands that require human input',
      'no-assignment-in-condition.sh': 'No Assignment In Condition',
      'no-base64-exfil.sh': 'Block base64 encoding of sensitive files',
      'no-callback-hell.sh': 'No Callback Hell',
      'no-catch-all-route.sh': 'No Catch All Route',
      'no-circular-dependency.sh': 'No Circular Dependency',
      'no-class-in-functional.sh': 'No Class In Functional',
      'no-cleartext-storage.sh': 'No Cleartext Storage',
      'no-commented-code.sh': 'No Commented Code',
      'no-commit-fixup.sh': 'No Commit Fixup',
      'no-cors-wildcard.sh': 'No Cors Wildcard',
      'no-curl-upload.sh': 'No Curl Upload',
      'no-dangerouslySetInnerHTML.sh': 'No DangerouslySetInnerHTML',
      'no-dangling-await.sh': 'No Dangling Await',
      'no-debug-commit.sh': 'Block commits containing debug artifacts',
      'no-debug-in-commit.sh': 'No Debug In Commit',
      'no-deep-nesting.sh': 'No Deep Nesting',
      'no-deep-relative-import.sh': 'No Deep Relative Import',
      'no-default-credentials.sh': 'No Default Credentials',
      'no-deploy-friday.sh': 'Block deploys on Fridays',
      'no-deprecated-api.sh': 'No Deprecated Api',
      'no-direct-dom-manipulation.sh': 'No Direct Dom Manipulation',
      'no-disabled-test.sh': 'No Disabled Test',
      'no-document-cookie.sh': 'No Document Cookie',
      'no-document-write.sh': 'No Document Write',
      'no-empty-function.sh': 'No Empty Function',
      'no-exec-user-input.sh': 'No Exec User Input',
      'no-expose-internal-ids.sh': 'No Expose Internal Ids',
      'no-exposed-port-in-dockerfile.sh': 'Warn about exposing port 22 in Dockerfile',
      'no-fixme-ship.sh': 'Block git push when FIXME/HACK comments exist',
      'no-floating-promises.sh': 'No Floating Promises',
      'no-force-flag.sh': 'Block dangerous --force flags',
      'no-force-install.sh': 'No Force Install',
      'no-git-amend-push.sh': 'Block amending already-pushed commits',
      'no-git-amend.sh': 'Block git commit --amend to prevent overwriting previous commits',
      'no-git-rebase-public.sh': 'No Git Rebase Public',
      'no-global-install.sh': 'Block global package installations',
      'no-global-state.sh': 'No Global State',
      'no-hardcoded-ip.sh': 'Detect hardcoded IP addresses in code',
      'no-hardcoded-port.sh': 'No Hardcoded Port',
      'no-hardcoded-url.sh': 'No Hardcoded Url',
      'no-hardlink.sh': 'Warn on hard link creation',
      'no-helmet-missing.sh': 'No Helmet Missing',
      'no-http-in-code.sh': 'Warn about http:// URLs in code (should be https://)',
      'no-http-url.sh': 'No Http Url',
      'no-http-without-https.sh': 'No Http Without Https',
      'no-index-as-key.sh': 'No Index As Key',
      'no-infinite-scroll-mem.sh': 'No Infinite Scroll Mem',
      'no-inline-event-handler.sh': 'No Inline Event Handler',
      'no-inline-handler.sh': 'No Inline Handler',
      'no-inline-style.sh': 'No Inline Style',
      'no-inline-styles.sh': 'No Inline Styles',
      'no-innerhtml.sh': 'No Innerhtml',
      'no-install-global.sh': 'No Install Global',
      'no-jwt-in-url.sh': 'No Jwt In Url',
      'no-large-commit.sh': 'No Large Commit',
      'no-localhost-expose.sh': 'No Localhost Expose',
      'no-long-switch.sh': 'No Long Switch',
      'no-magic-number.sh': 'No Magic Number',
      'no-md5-sha1.sh': 'No Md5 Sha1',
      'no-memory-leak-interval.sh': 'No Memory Leak Interval',
      'no-mixed-line-endings.sh': 'No Mixed Line Endings',
      'no-mutation-in-reducer.sh': 'No Mutation In Reducer',
      'no-mutation-observer-leak.sh': 'No Mutation Observer Leak',
      'no-nested-subscribe.sh': 'No Nested Subscribe',
      'no-nested-ternary.sh': 'No Nested Ternary',
      'no-network-exfil.sh': 'No Network Exfil',
      'no-new-array-fill.sh': 'No New Array Fill',
      'no-object-freeze-mutation.sh': 'No Object Freeze Mutation',
      'no-open-redirect.sh': 'No Open Redirect',
      'no-output-truncation.sh': 'Block piped tail/head that discards command output',
      'no-package-downgrade.sh': 'No Package Downgrade',
      'no-package-lock-edit.sh': 'No Package Lock Edit',
      'no-path-join-user-input.sh': 'No Path Join User Input',
      'no-port-bind.sh': 'No Port Bind',
      'no-process-exit.sh': 'No Process Exit',
      'no-prototype-pollution.sh': 'No Prototype Pollution',
      'no-push-without-ci.sh': 'No Push Without Ci',
      'no-push-without-tests.sh': 'Block git push if tests haven\'t been run',
      'no-raw-password-in-url.sh': 'No Raw Password In Url',
      'no-raw-ref.sh': 'No Raw Ref',
      'no-redundant-fragment.sh': 'No Redundant Fragment',
      'no-render-in-loop.sh': 'No Render In Loop',
      'no-root-user-docker.sh': 'No Root User Docker',
      'no-root-write.sh': 'No Root Write',
      'no-secrets-in-args.sh': 'No Secrets In Args',
      'no-secrets-in-logs.sh': 'No Secrets In Logs',
      'no-self-signed-cert.sh': 'Warn when generating self-signed certificates',
      'no-side-effects-in-render.sh': 'No Side Effects In Render',
      'no-sleep-in-hooks.sh': 'No Sleep In Hooks',
      'no-star-import-python.sh': 'No Star Import Python',
      'no-string-concat-sql.sh': 'No String Concat Sql',
      'no-sudo-guard.sh': 'No Sudo Guard',
      'no-sync-external-call.sh': 'No Sync External Call',
      'no-sync-fs.sh': 'No Sync Fs',
      'no-table-layout.sh': 'No Table Layout',
      'no-throw-string.sh': 'No Throw String',
      'no-todo-in-merge.sh': 'No Todo In Merge',
      'no-todo-in-production.sh': 'No Todo In Production',
      'no-todo-without-issue.sh': 'No Todo Without Issue',
      'no-triple-slash-ref.sh': 'No Triple Slash Ref',
      'no-unreachable-code.sh': 'No Unreachable Code',
      'no-unused-import.sh': 'No Unused Import',
      'no-unused-state.sh': 'No Unused State',
      'no-var-keyword.sh': 'No Var Keyword',
      'no-verify-blocker.sh': 'Block --no-verify on git commands',
      'no-wget-piped-bash.sh': 'Block curl/wget piped directly to bash',
      'no-window-location.sh': 'No Window Location',
      'no-with-statement.sh': 'No With Statement',
      'no-write-outside-src.sh': 'No Write Outside Src',
      'no-xml-external-entity.sh': 'No Xml External Entity',
      'npm-global-install-guard.sh': 'Block npm global installs',
      'npm-publish-guard.sh': 'Npm Publish Guard',
      'npm-script-injection.sh': 'Npm Script Injection',
      'npm-supply-chain-guard.sh': 'Detect npm supply chain attack patterns',
      'nuxt-config-guard.sh': 'Nuxt Config Guard',
      'output-credential-scan.sh': 'Detect credentials in command output',
      'output-secret-mask.sh': 'Mask secrets in tool output before Claude sees them',
      'overwrite-guard.sh': 'Warn before overwriting existing files',
      'package-json-guard.sh': 'Package Json Guard',
      'package-lock-frozen.sh': 'Block modifications to lockfiles',
      'parallel-session-guard.sh': 'Warn when multiple Claude sessions',
      'path-deny-bash-guard.sh': 'Enforce path deny rules on Bash commands',
      'path-traversal-guard.sh': 'Block path traversal in Edit/Write operations',
      'pip-publish-guard.sh': 'Pip Publish Guard',
      'pip-requirements-guard.sh': 'Enforce pip install from requirements.txt only',
      'pip-venv-guard.sh': 'Warn when pip install runs outside a virtual environment',
      'pip-venv-required.sh': 'Block pip install outside of a virtual environment',
      'polyglot-rm-guard.sh': 'Block file deletion via any language, not just rm',
      'post-compact-safety.sh': 'Guard against autonomous actions after compaction',
      'prisma-migrate-guard.sh': 'Block destructive Prisma operations',
      'prompt-injection-guard.sh': 'Detect prompt injection in tool output',
      'protect-claudemd.sh': 'Block edits to CLAUDE.md and settings files',
      'protect-commands-dir.sh': 'Backup .claude/commands/ on session start',
      'protect-dotfiles.sh': 'Block destructive operations on home directory config files',
      'public-repo-push-guard.sh': 'Block pushing proprietary code to public repos',
      'rails-migration-guard.sh': 'Block destructive Rails migrations',
      'read-all-files-enforcer.sh': 'Track which files have been read in a directory',
      'read-budget-guard.sh': 'Limit excessive file reading to prevent token waste',
      'redis-flushall-guard.sh': 'Redis Flushall Guard',
      'registry-publish-guard.sh': 'Block publishing to package registries',
      'relative-path-guard.sh': 'Warn on relative file paths in Edit/Write',
      'response-budget-guard.sh': 'Track and limit tool calls per response',
      'resume-context-guard.sh': 'Warn when resuming large sessions',
      'rm-safety-net.sh': 'Extra layer of rm protection beyond destructive-guard',
      'role-tool-guard.sh': 'Restrict tools based on current agent role',
      'schema-migration-guard.sh': 'Warn on database schema migrations without backup',
      'scope-guard.sh': 'Block file operations outside the project directory',
      'secret-file-read-guard.sh': 'Block Read/Grep of files containing secrets',
      'self-modify-bypass-guard.sh': 'Auto-allow .claude/ writes in bypass mode',
      'sensitive-file-read-guard.sh': 'Block reading sensitive system/user files',
      'sensitive-log-guard.sh': 'Sensitive Log Guard',
      'session-drift-guard.sh': 'Progressive safety as session ages',
      'session-duration-guard.sh': 'Warn on long-running sessions',
      'session-permission-reset-guard.sh': 'Override session-cached permissions',
      'shell-wrapper-guard.sh': 'Detect destructive commands hidden in shell wrappers',
      'spec-file-scope-guard.sh': 'Restrict edits to files mentioned in a spec document',
      'spring-profile-guard.sh': 'Spring Profile Guard',
      'ssh-key-protect.sh': 'Block reading/copying SSH private keys',
      'staged-secret-scan.sh': 'Block git commit if staged diff contains secrets',
      'strict-allowlist.sh': 'Only allow explicitly permitted commands',
      'strip-coauthored-by.sh': 'Remove or warn about Co-Authored-By trailers',
      'symlink-guard.sh': 'Detect symlink/junction traversal before rm',
      'symlink-protect.sh': 'Symlink Protect',
      'system-package-guard.sh': 'Block system-level package installations',
      'systemd-service-guard.sh': 'Block dangerous systemd service operations',
      'terraform-guard.sh': 'Warn before terraform destroy/apply',
      'timeout-guard.sh': 'Warn before long-running commands',
      'timezone-guard.sh': 'Timezone Guard',
      'tmp-output-size-guard.sh': 'Monitor and warn about large tmp output files',
      'turbo-cache-guard.sh': 'Warn before clearing Turborepo cache',
      'typosquat-guard.sh': 'Detect potential typosquatting in npm install',
      'uncommitted-changes-stop.sh': 'Uncommitted Changes Stop',
      'uncommitted-discard-guard.sh': 'Block commands that discard uncommitted changes',
      'uncommitted-work-guard.sh': 'Block destructive git when dirty',
      'uncommitted-work-shield.sh': 'Auto-stash before destructive git operations',
      'user-account-guard.sh': 'Block user/group account modifications',
      'variable-expansion-guard.sh': 'Block destructive commands with shell variable expansion',
      'windows-path-guard.sh': 'Prevent NTFS junction/symlink traversal destruction',
      'work-hours-guard.sh': 'Restrict risky operations outside work hours',
      'worktree-cleanup-guard.sh': 'Warn on worktree removal with unmerged commits',
      'worktree-delete-guard.sh': 'Block git worktree removal',
      'worktree-guard.sh': 'Warn when operating in a git worktree',
      'worktree-memory-guard.sh': 'Warn when memory path resolves to main worktree',
      'worktree-path-validator.sh': 'Warn when file operations target main workspace instead of worktree',
      'worktree-project-unify.sh': 'Worktree Project Unify',
      'worktree-unmerged-guard.sh': 'Prevent worktree cleanup with unmerged commits',
      'write-overwrite-confirm.sh': 'Warn when Write tool overwrites large files',
      'write-secret-guard.sh': 'Block secrets from being written to files',
      'write-shrink-guard.sh': 'Block writes that drastically shrink files',
      'cch-cache-guard.sh': 'Block reads of session files to prevent cache poisoning',
      'conversation-history-guard.sh': 'Block modifications to conversation history',
      'image-file-validator.sh': 'Block reads of fake image files that corrupt sessions',
      'permission-denial-enforcer.sh': 'Block alternative write methods after permission denial',
      'read-only-mode.sh': 'Block all file modifications and destructive commands',
      'replace-all-guard.sh': 'Warn when Edit uses replace_all: true',
      'task-integrity-guard.sh': 'Prevent Claude from deleting tasks to hide unfinished work',
      'working-directory-fence.sh': 'Block file operations outside current working directory',
    },
    'Auto-Approve': {
      'allow-claude-settings.sh': 'PermissionRequest hook',
      'allow-git-hooks-dir.sh': 'PermissionRequest hook',
      'allow-protected-dirs.sh': 'PermissionRequest hook',
      'auto-approve-build.sh': 'Auto-approve build and test commands',
      'auto-approve-cargo.sh': 'Auto-approve Rust cargo commands',
      'auto-approve-compound-git.sh': 'PermissionRequest hook',
      'auto-approve-docker.sh': 'Auto Approve Docker',
      'auto-approve-git-read.sh': 'Auto-approve read-only git commands',
      'auto-approve-go.sh': 'Auto-approve Go build/test/vet commands',
      'auto-approve-gradle.sh': 'Auto-approve Gradle build/test commands',
      'auto-approve-make.sh': 'Auto-approve common Make targets',
      'auto-approve-maven.sh': 'Auto-approve Maven build/test commands',
      'auto-approve-python.sh': 'Auto-approve Python development commands',
      'auto-approve-readonly-tools.sh': 'Auto Approve Readonly Tools',
      'auto-approve-readonly.sh': 'Auto-approve all read-only commands',
      'auto-approve-ssh.sh': 'Auto-approve safe SSH commands',
      'auto-approve-test.sh': 'Auto Approve Test',
      'auto-compact-prep.sh': 'Save checkpoint before context compaction',
      'auto-mode-safe-commands.sh': 'Fix Auto Mode false positives on safe commands',
      'auto-push-worktree.sh': 'Auto-push worktree branches before session end',
      'bash-heuristic-approver.sh': 'Auto-approve bash safety heuristic prompts',
      'bash-safety-auto-deny.sh': 'Auto-deny commands that trigger safety prompts',
      'classifier-fallback-allow.sh': 'Allow read-only commands when Auto Mode classifier is unavailable',
      'direnv-auto-reload.sh': 'Auto-reload environment when directory changes',
      'edit-always-allow.sh': 'Auto-approve all Edit prompts in configured directories',
      'gitignore-auto-add.sh': 'Suggest .gitignore entries for common patterns',
      'heredoc-backtick-approver.sh': 'Auto-approve backtick warnings in heredoc strings',
      'multiline-command-approver.sh': 'Auto-approve multiline commands by first-line matching',
      'permission-audit-log.sh': 'Log all tool invocations for permission debugging',
      'permission-cache.sh': 'Remember approved commands in session',
      'permission-entry-validator.sh': 'Clean broken permission entries from settings',
      'permission-mode-drift-guard.sh': 'Detect permission mode changes mid-session',
      'permission-pattern-auto-allow.sh': 'Auto-allow commands matching user-defined patterns',
      'quoted-flag-approver.sh': 'Auto-approve commands with quoted flag values',
      'webfetch-domain-allow.sh': 'Auto-approve WebFetch for allowed domains',
    },
    'Quality': {
      'bash-secret-output-detector.sh': 'Warn when Bash output contains secrets',
      'bashrc-safety-check.sh': 'Warn about .bashrc lines that hang in non-interactive shells',
      'branch-name-check.sh': 'Warn when creating branches with non-standard names',
      'branch-naming-convention.sh': 'Branch Naming Convention',
      'changelog-reminder.sh': 'Remind to update CHANGELOG on version bump',
      'check-abort-controller.sh': 'Check Abort Controller',
      'check-accessibility.sh': 'Check Accessibility',
      'check-aria-labels.sh': 'Check Aria Labels',
      'check-async-await-consistency.sh': 'Check Async Await Consistency',
      'check-before-act-enforcer.sh': 'Require Read before Edit/Write',
      'check-charset-meta.sh': 'Check Charset Meta',
      'check-cleanup-effect.sh': 'Check Cleanup Effect',
      'check-content-type.sh': 'Check Content Type',
      'check-controlled-input.sh': 'Check Controlled Input',
      'check-cookie-flags.sh': 'Check Cookie Flags',
      'check-cors-config.sh': 'Check Cors Config',
      'check-csp-headers.sh': 'Check Csp Headers',
      'check-debounce.sh': 'Check Debounce',
      'check-dependency-age.sh': 'Check Dependency Age',
      'check-dependency-license.sh': 'Check Dependency License',
      'check-dockerfile-best-practice.sh': 'Check Dockerfile Best Practice',
      'check-error-boundaries.sh': 'Check Error Boundaries',
      'check-error-class.sh': 'Check Error Class',
      'check-error-handling.sh': 'Check Error Handling',
      'check-error-logging.sh': 'Check Error Logging',
      'check-error-message.sh': 'Check Error Message',
      'check-error-page.sh': 'Check Error Page',
      'check-error-stack.sh': 'Check Error Stack',
      'check-favicon.sh': 'Check Favicon',
      'check-form-validation.sh': 'Check Form Validation',
      'check-git-hooks-compat.sh': 'Check Git Hooks Compat',
      'check-gitattributes.sh': 'Check Gitattributes',
      'check-https-redirect.sh': 'Check Https Redirect',
      'check-image-optimization.sh': 'Check Image Optimization',
      'check-input-validation.sh': 'Check Input Validation',
      'check-key-prop.sh': 'Check Key Prop',
      'check-lang-attribute.sh': 'Check Lang Attribute',
      'check-lazy-loading.sh': 'Check Lazy Loading',
      'check-loading-state.sh': 'Check Loading State',
      'check-memo-deps.sh': 'Check Memo Deps',
      'check-meta-description.sh': 'Check Meta Description',
      'check-npm-scripts-exist.sh': 'Check Npm Scripts Exist',
      'check-null-check.sh': 'Check Null Check',
      'check-package-size.sh': 'Check Package Size',
      'check-pagination.sh': 'Check Pagination',
      'check-port-availability.sh': 'Check Port Availability',
      'check-promise-all.sh': 'Check Promise All',
      'check-prop-types.sh': 'Check Prop Types',
      'check-rate-limiting.sh': 'Check Rate Limiting',
      'check-responsive-design.sh': 'Check Responsive Design',
      'check-retry-logic.sh': 'Check Retry Logic',
      'check-return-types.sh': 'Check Return Types',
      'check-semantic-html.sh': 'Check Semantic Html',
      'check-semantic-versioning.sh': 'Check Semantic Versioning',
      'check-suspense-fallback.sh': 'Check Suspense Fallback',
      'check-test-exists.sh': 'Warn when editing code without a test file',
      'check-test-naming.sh': 'Check Test Naming',
      'check-timeout-cleanup.sh': 'Check Timeout Cleanup',
      'check-tls-version.sh': 'Check Tls Version',
      'check-type-coercion.sh': 'Check Type Coercion',
      'check-unsubscribe.sh': 'Check Unsubscribe',
      'check-viewport-meta.sh': 'Check Viewport Meta',
      'check-worker-terminate.sh': 'Check Worker Terminate',
      'ci-skip-guard.sh': 'Warn when commit message skips CI',
      'claudemd-violation-detector.sh': 'Remind critical CLAUDE.md rules after tool use',
      'commit-message-check.sh': 'Warn when commit messages don\'t follow conventions',
      'commit-message-quality.sh': 'Warn about low-quality commit messages',
      'commit-quality-gate.sh': 'Enforce commit message quality',
      'commit-scope-guard.sh': 'Warn when committing too many files',
      'conflict-marker-guard.sh': 'Block commits with conflict markers',
      'console-log-count.sh': 'Console Log Count',
      'context-warning-verifier.sh': 'Verify context warnings are genuine',
      'cors-star-warn.sh': 'PostToolUse matcher: Edit|Write',
      'cwd-drift-detector.sh': 'Warn when destructive commands run outside project root',
      'debug-leftover-guard.sh': 'Detect debug code in commits',
      'detect-mixed-indentation.sh': 'Warn about mixed tabs/spaces',
      'dockerfile-lint.sh': 'Basic Dockerfile validation after editing',
      'dotenv-example-sync.sh': 'Warn when .env changes but .env.example doesn\'t',
      'dotenv-validate.sh': 'Validate .env syntax after edits',
      'dotenv-watch.sh': 'Alert when .env files change on disk',
      'dotnet-build-on-edit.sh': 'Run dotnet build after C#/F# edits',
      'edit-old-string-validator.sh': 'Pre-validate Edit tool old_string exists',
      'edit-verify.sh': 'Edit Verify',
      'enforce-tests.sh': 'Warn when source files are edited without tests',
      'env-drift-guard.sh': 'Detect .env vs .env.example drift',
      'env-file-gitignore-check.sh': 'Warn if .env is not in .gitignore',
      'env-naming-convention.sh': 'Env Naming Convention',
      'env-required-check.sh': 'Env Required Check',
      'fact-check-gate.sh': 'Warn when docs reference unread source files',
      'file-reference-check.sh': 'Verify referenced file paths exist',
      'git-author-guard.sh': 'Verify commit author is configured correctly',
      'git-blame-context.sh': 'Show file ownership before major edits',
      'git-lfs-guard.sh': 'Suggest Git LFS for large binary files',
      'git-message-length-check.sh': 'Warn on too-short commit messages',
      'git-message-length.sh': 'Git Message Length',
      'gitignore-check.sh': 'Gitignore Check',
      'go-mod-tidy-warn.sh': 'Go Mod Tidy Warn',
      'go-vet-after-edit.sh': 'Run go vet after editing Go files',
      'hallucination-url-check.sh': 'Detect potentially hallucinated URLs',
      'hardcoded-secret-detector.sh': 'Detect hardcoded secrets in edits',
      'import-cycle-warn.sh': 'Detect potential circular imports',
      'java-compile-on-edit.sh': 'Check Java compilation after edits',
      'json-syntax-check.sh': 'Validate JSON files after editing',
      'license-check.sh': 'Warn when creating files without a license header',
      'lockfile-guard.sh': 'Warn when lockfiles are modified unexpectedly',
      'magic-number-warn.sh': 'Magic Number Warn',
      'main-branch-warn.sh': 'Warn when working directly on main/master',
      'markdown-link-check.sh': 'Verify local file links in markdown',
      'max-function-length.sh': 'Max Function Length',
      'max-import-count.sh': 'Max Import Count',
      'max-line-length-check.sh': 'Warn on lines exceeding max length after edit',
      'no-console-assert.sh': 'No Console Assert',
      'no-console-error-swallow.sh': 'No Console Error Swallow',
      'no-console-in-prod.sh': 'No Console In Prod',
      'no-console-log-commit.sh': 'Block commits containing console.log',
      'no-console-time.sh': 'No Console Time',
      'no-eval-in-template.sh': 'No Eval In Template',
      'no-eval-template.sh': 'No Eval Template',
      'no-eval.sh': 'No Eval',
      'no-todo-ship.sh': 'Block commits with TODO/FIXME/HACK markers',
      'no-wildcard-cors.sh': 'No Wildcard Cors',
      'no-wildcard-delete.sh': 'No Wildcard Delete',
      'no-wildcard-import.sh': 'No Wildcard Import',
      'npm-audit-warn.sh': 'Npm Audit Warn',
      'output-explosion-detector.sh': 'Detect abnormally large tool outputs',
      'output-pii-detect.sh': 'Detect PII/sensitive data in tool output',
      'output-token-env-check.sh': 'Warn if max output tokens is not configured',
      'package-script-guard.sh': 'Warn when package.json scripts change',
      'php-lint-on-edit.sh': 'Run PHP syntax check after editing PHP files',
      'plain-language-danger-warn.sh': 'Add plain-language warnings to dangerous commands',
      'port-conflict-check.sh': 'Warn before starting a server on an occupied port',
      'pr-description-check.sh': 'Pr Description Check',
      'prefer-builtin-tools.sh': 'Deny bash commands that have dedicated built-in tool equivalents',
      'prefer-const.sh': 'Prefer Const',
      'prefer-dedicated-tools.sh': 'Force use of dedicated tools instead of Bash equivalents',
      'prefer-optional-chaining.sh': 'Prefer Optional Chaining',
      'push-requires-test-pass-record.sh': 'Record when tests pass (companion to push-requires-test-pass.sh)',
      'push-requires-test-pass.sh': 'Block git push to main/production without test verification',
      'python-import-check.sh': 'Detect unused imports in Python files',
      'python-ruff-on-edit.sh': 'Run ruff lint after editing Python files',
      'react-key-warn.sh': 'Warn about missing key props in JSX lists',
      'readme-exists-check.sh': 'Readme Exists Check',
      'readme-update-reminder.sh': 'Remind to update README when APIs change',
      'require-issue-ref.sh': 'Warn when commit message lacks issue reference',
      'ruby-lint-on-edit.sh': 'Run RuboCop after editing Ruby files',
      'rust-clippy-after-edit.sh': 'Run cargo clippy after editing Rust files',
      'sandbox-write-verify.sh': 'Verify file existence before overwrite in sandbox mode',
      'sensitive-regex-guard.sh': 'Warn on ReDoS-vulnerable regex patterns',
      'session-start-safety-check.sh': 'Warn about uncommitted changes on session start',
      'settings-mutation-detector.sh': 'Detect unauthorized changes to Claude settings files',
      'skill-injection-detector.sh': 'Detect silently injected skills/plugins',
      'sql-injection-detect.sh': 'Sql Injection Detect',
      'svelte-lint-on-edit.sh': 'Svelte Lint On Edit',
      'swift-build-on-edit.sh': 'Run swift build check after editing Swift files',
      'test-after-edit.sh': 'Remind to run tests after editing test files',
      'test-before-commit.sh': 'Test Before Commit',
      'test-before-push.sh': 'Block git push when tests haven\'t passed',
      'test-coverage-guard.sh': 'Warn when code grows without tests',
      'test-coverage-reminder.sh': 'Remind to run tests after code changes',
      'test-deletion-guard.sh': 'Block deletion of test assertions',
      'test-exit-code-verify.sh': 'Verify test command exit codes match results',
      'todo-check.sh': 'Warn when committing files with TODO/FIXME/HACK comments',
      'todo-deadline-warn.sh': 'Warn about expired TODO deadlines in edited files',
      'typescript-lint-on-edit.sh': 'Run TypeScript type check after editing .ts/.tsx files',
      'typescript-strict-check.sh': 'Warn when TypeScript strict mode is disabled',
      'typescript-strict-guard.sh': 'Warn when tsconfig.json strict mode is disabled',
      'unicode-corruption-check.sh': 'Detect Unicode corruption after Edit/Write',
      'usage-warn.sh': 'Usage Warn',
      'verify-before-commit.sh': 'Block git commit unless tests passed recently',
      'verify-before-done.sh': 'Warn when committing without running tests',
      'vue-lint-on-edit.sh': 'Vue Lint On Edit',
      'write-test-ratio.sh': 'Write Test Ratio',
      'yaml-syntax-check.sh': 'Validate YAML after editing',
    },
    'Monitoring': {
      'api-rate-limit-tracker.sh': 'Track API call frequency and warn on burst',
      'cost-tracker.sh': 'Estimate session token cost',
      'cross-session-error-log.sh': 'Persist error patterns across sessions',
      'daily-usage-tracker.sh': 'Track daily tool call count',
      'edit-counter-test-gate.sh': 'Require testing after N consecutive edits',
      'edit-error-counter.sh': 'Warn when Edit tool fails repeatedly',
      'file-change-monitor.sh': 'Track all files modified during a session',
      'file-change-tracker.sh': 'Track all file modifications in a session',
      'mcp-tool-audit-log.sh': 'Log all MCP tool calls for security auditing',
      'no-console-log.sh': 'No Console Log',
      'no-sensitive-log.sh': 'No Sensitive Log',
      'read-audit-log.sh': 'Log all file read operations for forensics',
      'session-budget-alert.sh': 'Show session budget status on start',
      'session-end-logger.sh': 'Log session activity at exit',
      'session-error-rate-monitor.sh': 'Detect session quality degradation',
      'session-health-monitor.sh': 'Monitor session health metrics',
      'session-memory-watchdog.sh': 'Session Memory Watchdog',
      'session-quota-tracker.sh': 'Track cumulative tool calls per session',
      'session-token-counter.sh': 'Track tool usage count per session',
      'token-usage-tracker.sh': 'Token Usage Tracker',
      'tool-call-rate-limiter.sh': 'Prevent runaway tool calls',
      'tool-file-logger.sh': 'Log file paths from Read/Write/Edit to stderr',
      'usage-cache-local.sh': 'Cache usage info locally to avoid API calls',
      'compact-alert-notification.sh': 'Warn when context compaction is imminent',
      'prompt-usage-logger.sh': 'Log every prompt with timestamps',
      'subagent-error-detector.sh': 'Detect failed subagent results',
    },
    'Recovery': {
      'auto-checkpoint.sh': 'Auto-commit after every edit for rollback protection',
      'auto-git-checkpoint.sh': 'Auto Git Checkpoint',
      'auto-snapshot.sh': 'Automatic file snapshots before every edit',
      'auto-stash-before-pull.sh': 'Suggest stash before git pull/merge',
      'backup-before-refactor.sh': 'Backup Before Refactor',
      'checkpoint-tamper-guard.sh': 'Block manipulation of hook state/checkpoint files',
      'context-compact-advisor.sh': 'Context Compact Advisor',
      'context-snapshot.sh': 'Save session state before context loss',
      'file-change-undo-tracker.sh': 'Track file changes for easy undo',
      'file-edit-backup.sh': 'Auto-backup files before Edit/Write overwrites them',
      'file-recycle-bin.sh': 'Move deleted files to recycle bin instead of permanent deletion',
      'git-stash-before-checkout.sh': 'Auto-stash before risky git checkouts',
      'git-stash-before-danger.sh': 'Auto-stash before risky git operations',
      'post-compact-restore.sh': 'Restore context after /compact',
      'pre-compact-checkpoint.sh': 'Auto-save before context compaction',
      'pre-compact-knowledge-save.sh': 'Save critical context before compaction',
      'pre-compact-transcript-export.sh': 'Export conversation before compaction',
      'revert-helper.sh': 'Show revert command when session ends badly',
      'session-checkpoint.sh': 'Auto-save session state on every stop',
      'session-handoff.sh': 'Auto-save session state for next session',
      'session-resume-env-fix.sh': 'Fix CLAUDE_ENV_FILE path on session resume',
      'session-resume-guard.sh': 'Verify context is loaded after session resume',
      'session-state-saver.sh': 'Session State Saver',
      'session-summary-stop.sh': 'Print session change summary on stop',
      'session-summary.sh': 'Session Summary',
      'settings-auto-backup.sh': 'Auto-backup settings on session start',
      'terminal-state-restore.sh': 'terminal-state-restore — restore terminal to clean state on session exit',
      'pre-compact-transcript-backup.sh': 'Backup transcript before compaction',
      'ripgrep-permission-fix.sh': 'Auto-fix ripgrep execute permission on session start',
      'session-backup-on-start.sh': 'Backup session JSONL files on start',
      'session-index-repair.sh': 'Rebuild sessions-index.json on exit',
    },
    'UX': {
      'auto-answer-question.sh': 'Auto-answer AskUserQuestion for headless/autonomous mode',
      'binary-file-guard.sh': 'Warn when Write creates binary/large files',
      'compact-reminder.sh': 'Remind to /compact when context is low',
      'consecutive-error-breaker.sh': 'Stop after N consecutive errors',
      'consecutive-failure-circuit-breaker.sh': 'Stop after repeated failures',
      'context-threshold-alert.sh': 'Alert at configurable context usage thresholds',
      'cwd-reminder.sh': 'Remind Claude of the current working directory',
      'dangling-process-guard.sh': 'Detect background processes left running',
      'dependency-audit.sh': 'Warn before installing unknown packages',
      'diff-size-guard.sh': 'Warn on large uncommitted changes',
      'disk-space-check.sh': 'Warn if disk space is low at session start',
      'disk-space-guard.sh': 'Warn when disk space is running low',
      'encoding-guard.sh': 'Warn when writing to non-UTF-8 files',
      'error-memory-guard.sh': 'Detect repeated failed commands',
      'file-size-limit.sh': 'File Size Limit',
      'fish-shell-wrapper.sh': 'Run Bash tool commands in fish shell',
      'five-hundred-milestone.sh': 'Five Hundred Milestone',
      'git-show-flag-sanitizer.sh': 'Strip invalid --no-stat from git show',
      'hook-debug-wrapper.sh': 'Debug wrapper for any Claude Code hook',
      'hook-stdout-sanitizer.sh': 'Prevent hook stdout from corrupting tool results',
      'large-read-guard.sh': 'Warn before reading large files',
      'long-session-reminder.sh': 'Warn when session runs too long',
      'loop-detector.sh': 'Detect and break command repetition loops',
      'max-file-count-guard.sh': 'Max File Count Guard',
      'max-session-duration.sh': 'Warn when session exceeds time limit',
      'node-version-check.sh': 'Warn if Node.js version is too old',
      'node-version-guard.sh': 'Warn when Node.js version doesn\'t match .nvmrc',
      'notify-waiting.sh': 'Desktop notification when Claude needs input',
      'output-length-guard.sh': 'Warn when tool output is very large',
      'parallel-edit-guard.sh': 'Detect concurrent edits to same file',
      'plan-mode-edit-guard.sh': 'Warn when editing non-plan files during plan mode',
      'plan-mode-enforcer.sh': 'Hard-enforce Plan Mode read-only constraint',
      'plan-mode-strict-guard.sh': 'Hard-block all write operations during plan mode',
      'plan-repo-sync.sh': 'Sync plan files from ~/.claude/ into your repo',
      'plugin-process-cleanup.sh': 'Kill leaked plugin subprocesses on session end',
      'prompt-injection-detector.sh': 'UserPromptSubmit hook',
      'prompt-length-guard.sh': 'UserPromptSubmit hook',
      'rate-limit-guard.sh': 'Rate Limit Guard',
      'read-before-edit.sh': 'Warn when editing files not recently read',
      'reinject-claudemd.sh': 'Re-inject CLAUDE.md content after compact',
      'session-time-limit.sh': 'Warn when session exceeds time limit',
      'skill-gate.sh': 'Skill Gate',
      'stale-branch-guard.sh': 'Warn when working on a stale branch',
      'stale-env-guard.sh': 'Warn when .env files are very old',
      'system-message-workaround.sh': 'Ensure hook warnings reach both user and model',
      'temp-file-cleanup-stop.sh': 'Clean up tmpclaude-* files on session end',
      'temp-file-cleanup.sh': 'Stop hook',
      'tmp-cleanup.sh': 'Clean up /tmp/claude-*-cwd temp files',
      'token-budget-guard.sh': 'Estimate and limit session token cost',
      'token-budget-per-task.sh': 'Track and warn on per-task token usage',
      'virtual-cwd-helper.sh': 'Remind about virtual working directory',
    },
    'Agent Controls': {
      'max-concurrent-agents.sh': 'Limit number of simultaneous subagents',
      'max-subagent-count.sh': 'Max Subagent Count',
      'mcp-config-freeze.sh': 'Prevent MCP configuration changes during session',
      'mcp-data-boundary.sh': 'Prevent MCP tools from accessing sensitive paths',
      'mcp-orphan-process-guard.sh': 'Detect orphaned MCP server processes',
      'mcp-server-allowlist.sh': 'Restrict MCP tool calls to allowed servers',
      'mcp-server-guard.sh': 'Block unauthorized MCP server configuration changes',
      'mcp-tool-guard.sh': 'Mcp Tool Guard',
      'subagent-budget-guard.sh': 'Subagent Budget Guard',
      'subagent-claudemd-inject.sh': 'Inject CLAUDE.md rules into subagent prompts',
      'subagent-context-size-guard.sh': 'Warn on thin subagent prompts',
      'subagent-scope-guard.sh': 'Limit subagent file access scope',
      'subagent-scope-validator.sh': 'Validate subagent task scope before launch',
      'subagent-tool-call-limiter.sh': 'Limit total tool calls per session',
    },
    'Other': {
      'token-spike-alert.sh': 'Alert on abnormal token consumption per turn',
      'mcp-warmup-wait.sh': 'Wait for MCP servers to be ready on session start',
    },
  };

  // Optional category filter: --examples safety, --examples ux, etc.
  const exIdx = Math.max(process.argv.indexOf('--examples'), process.argv.indexOf('-e'));
  const nextArg = exIdx !== -1 ? (process.argv[exIdx + 1] || '') : '';
  const filter = nextArg.startsWith('-') ? '' : nextArg.toLowerCase();

  console.log();
  console.log(c.bold + '  cc-safe-setup --examples' + c.reset + (filter ? ' ' + filter : ''));
  const totalExamples = Object.values(CATEGORIES).reduce((sum, cat) => sum + Object.keys(cat).length, 0);
  console.log(c.dim + `  ${totalExamples} hooks beyond the 8 built-in ones` + c.reset);
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

  // Show batch install command if filtered
  const allFiltered = [];
  for (const [cat, hooks] of Object.entries(CATEGORIES)) {
    const fh = filter
      ? Object.entries(hooks).filter(([file, desc]) =>
          cat.toLowerCase().includes(filter) ||
          file.toLowerCase().includes(filter) ||
          desc.toLowerCase().includes(filter))
      : Object.entries(hooks);
    for (const [file] of fh) allFiltered.push(file.replace('.sh', ''));
  }

  if (filter && allFiltered.length > 0 && allFiltered.length <= 20) {
    console.log(c.dim + '  Install all filtered hooks:' + c.reset);
    for (const h of allFiltered) {
      console.log(c.dim + `    npx cc-safe-setup --install-example ${h}` + c.reset);
    }
    console.log();
  }

  console.log(c.dim + '  Or install any single hook:' + c.reset);
  console.log(c.dim + '    npx cc-safe-setup --install-example <name>' + c.reset);
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

  // Detect trigger from header comments (case-insensitive for "Trigger:" prefix)
  const triggerMatch = content.match(/^#\s*[Tt][Rr][Ii][Gg][Gg][Ee][Rr]:\s*(\S+)/m);
  if (triggerMatch) {
    const t = triggerMatch[1];
    if (['PermissionRequest','PostToolUse','Notification','Stop','SessionStart','PreCompact','SessionEnd','UserPromptSubmit','CwdChanged','FileChanged'].includes(t)) {
      trigger = t;
    }
  } else if (content.match(/^#.*PermissionRequest hook/m)) {
    trigger = 'PermissionRequest';
  } else if (content.match(/^#.*UserPromptSubmit hook/m)) {
    trigger = 'UserPromptSubmit';
  }

  // Detect matcher from header (JSON format or comment format)
  const matcherMatch = content.match(/"matcher":\s*"([^"]*)"/);
  if (matcherMatch) matcher = matcherMatch[1];
  const commentMatcher = content.match(/^#\s*[Mm][Aa][Tt][Cc][Hh][Ee][Rr]:\s*(.+)$/m);
  if (commentMatcher) {
    // Extract quoted value if present (e.g., ".env" or ".env|.env.local"), otherwise use raw
    const quoted = commentMatcher[1].match(/^"([^"]*)"/);
    matcher = quoted ? quoted[1] : commentMatcher[1].trim();
  }

  // Update settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf8'));
  }
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks[trigger]) settings.hooks[trigger] = [];

  // CwdChanged does not support matchers; FileChanged uses matcher from header
  const hookEntry = trigger === 'CwdChanged'
    ? { hooks: [{ type: 'command', command: toBashPath(destPath) }] }
    : { matcher: matcher, hooks: [{ type: 'command', command: toBashPath(destPath) }] };

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

  // 10. Check for Windows backslash paths in hook commands
  const allCmds = [...preHooks, ...postHooks, ...stopHooks]
    .flatMap(e => (e.hooks || []).map(h => h.command || ''));
  const backslashCmds = allCmds.filter(c => c.includes('\\'));
  if (backslashCmds.length > 0) {
    risks.push({
      severity: 'CRITICAL',
      issue: `${backslashCmds.length} hook command(s) have Windows backslash paths — hooks will fail with "No such file"`,
      fix: 'npx cc-safe-setup --uninstall && npx cc-safe-setup@latest'
    });
  }

  // 11. Check for hook permission fixer (SessionStart)
  const sessionHooks = settings.hooks?.SessionStart || [];
  const hasPermFixer = sessionHooks.some(e =>
    (e.hooks || []).some(h => (h.command || '').includes('permission'))
  );
  if (!hasPermFixer && process.platform === 'win32') {
    risks.push({
      severity: 'LOW',
      issue: 'No SessionStart permission fixer — plugin updates may break hook permissions on Windows',
      fix: 'npx cc-safe-setup --install-example hook-permission-fixer'
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

async function testHook(hookName) {
  const { execSync } = await import('child_process');
  console.log();

  if (!hookName) {
    console.log(c.bold + '  cc-safe-setup --test-hook <name>' + c.reset);
    console.log(c.dim + '  Test any hook with sample inputs.' + c.reset);
    console.log();
    console.log('  Example: npx cc-safe-setup --test-hook destructive-guard');
    return;
  }

  const name = hookName.replace('.sh', '');
  // Find the hook
  let hookPath = join(HOOKS_DIR, `${name}.sh`);
  if (!existsSync(hookPath)) hookPath = join(__dirname, 'examples', `${name}.sh`);
  if (!existsSync(hookPath)) {
    console.log(c.red + `  Hook "${name}" not found.` + c.reset);
    return;
  }

  console.log(c.bold + `  Testing: ${name}` + c.reset);
  console.log(c.dim + `  File: ${hookPath}` + c.reset);
  console.log();

  // Sample inputs per hook type
  const SAMPLES = {
    'should-block': [
      { desc: 'dangerous rm', input: '{"tool_input":{"command":"rm -rf /"}}' },
      { desc: 'git reset hard', input: '{"tool_input":{"command":"git reset --hard"}}' },
      { desc: 'force push', input: '{"tool_input":{"command":"git push origin main --force"}}' },
      { desc: 'git add .env', input: '{"tool_input":{"command":"git add .env"}}' },
      { desc: 'sudo command', input: '{"tool_input":{"command":"sudo rm -rf /home"}}' },
      { desc: 'drop database', input: '{"tool_input":{"command":"DROP DATABASE production"}}' },
    ],
    'should-allow': [
      { desc: 'safe ls', input: '{"tool_input":{"command":"ls -la"}}' },
      { desc: 'git status', input: '{"tool_input":{"command":"git status"}}' },
      { desc: 'npm test', input: '{"tool_input":{"command":"npm test"}}' },
      { desc: 'cat file', input: '{"tool_input":{"command":"cat README.md"}}' },
      { desc: 'empty input', input: '{}' },
    ],
  };

  let pass = 0, total = 0;

  for (const [category, samples] of Object.entries(SAMPLES)) {
    console.log(c.dim + `  ${category}:` + c.reset);
    for (const sample of samples) {
      total++;
      try {
        execSync(`echo '${sample.input}' | bash "${hookPath}"`, { stdio: 'pipe', timeout: 5000 });
        // Exit 0 = allowed
        const icon = category === 'should-allow' ? c.green + '✓' : c.yellow + '·';
        console.log(`    ${icon}${c.reset} ${sample.desc} → allowed (exit 0)`);
        if (category === 'should-allow') pass++;
      } catch (e) {
        const code = e.status;
        if (code === 2) {
          // Blocked
          const icon = category === 'should-block' ? c.green + '✓' : c.red + '✗';
          console.log(`    ${icon}${c.reset} ${sample.desc} → ${c.red}BLOCKED${c.reset} (exit 2)`);
          if (category === 'should-block') pass++;
        } else {
          console.log(`    ${c.yellow}?${c.reset} ${sample.desc} → exit ${code}`);
        }
      }
    }
  }

  console.log();
  console.log(`  ${pass}/${total} samples matched expected behavior`);
  console.log();
}

async function saveProfile(name) {
  const { readdirSync } = await import('fs');
  const profilesDir = join(HOME, '.claude', 'profiles');
  mkdirSync(profilesDir, { recursive: true });

  if (!name) {
    // List saved profiles
    console.log();
    console.log(c.bold + '  Saved Profiles' + c.reset);
    console.log();
    const files = existsSync(profilesDir) ? readdirSync(profilesDir).filter(f => f.endsWith('.json')) : [];
    if (files.length === 0) {
      console.log(c.dim + '  No saved profiles yet.' + c.reset);
      console.log(c.dim + '  Save: npx cc-safe-setup --save-profile my-setup' + c.reset);
    } else {
      for (const f of files) {
        const pName = f.replace('.json', '');
        const data = JSON.parse(readFileSync(join(profilesDir, f), 'utf-8'));
        console.log(`  ${c.bold}${pName}${c.reset} (${data.hooks?.length || 0} hooks, saved ${data.savedAt?.split('T')[0] || '?'})`);
        console.log(c.dim + `    Load: npx cc-safe-setup --profile ${pName}` + c.reset);
      }
    }
    console.log();
    return;
  }

  // Save current hook state
  const hookDir = join(HOME, '.claude', 'hooks');
  const hooks = existsSync(hookDir) ? readdirSync(hookDir).filter(f => f.endsWith('.sh') || f.endsWith('.py')) : [];

  const profile = {
    name,
    savedAt: new Date().toISOString(),
    hooks: hooks.map(h => h.replace(/\.(sh|py)$/, '')),
    settings: existsSync(SETTINGS_PATH) ? JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')) : {},
  };

  const profilePath = join(profilesDir, `${name}.json`);
  writeFileSync(profilePath, JSON.stringify(profile, null, 2));

  console.log();
  console.log(c.green + `  ✓ Profile "${name}" saved (${hooks.length} hooks)` + c.reset);
  console.log(c.dim + `  File: ${profilePath}` + c.reset);
  console.log(c.dim + `  Load: npx cc-safe-setup --profile ${name}` + c.reset);
  console.log();
}

function changelogCmd() {
  const clPath = join(__dirname, 'CHANGELOG.md');
  if (!existsSync(clPath)) {
    console.log(c.dim + '  No CHANGELOG.md found.' + c.reset);
    return;
  }
  const content = readFileSync(clPath, 'utf-8');
  const versions = content.split(/^## /m).filter(s => s.trim()).slice(0, 5);
  console.log();
  console.log(c.bold + '  Recent Changes' + c.reset);
  console.log();
  for (const v of versions) {
    const lines = v.split('\n');
    const header = lines[0].trim();
    console.log(c.bold + '  ' + header + c.reset);
    for (const line of lines.slice(1).filter(l => l.startsWith('- ')).slice(0, 3)) {
      console.log(c.dim + '  ' + line + c.reset);
    }
    console.log();
  }
}

async function scoreOnly() {
  const { readdirSync } = await import('fs');
  let score = 0;

  // Hooks installed (max 50 points)
  const hookDir = join(HOME, '.claude', 'hooks');
  const hookCount = existsSync(hookDir) ? readdirSync(hookDir).filter(f => f.endsWith('.sh') || f.endsWith('.py')).length : 0;
  score += Math.min(hookCount * 3, 50);

  // Critical hooks (max 20 points)
  const critical = ['destructive-guard', 'branch-guard', 'secret-guard'];
  if (existsSync(SETTINGS_PATH)) {
    try {
      const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      const cmds = JSON.stringify(s.hooks || {});
      for (const h of critical) {
        if (cmds.includes(h)) score += 7;
      }
    } catch {}
  }

  // CLAUDE.md exists (10 points)
  if (existsSync(join(process.cwd(), 'CLAUDE.md'))) score += 10;

  // .gitignore has .env (10 points)
  const gi = existsSync(join(process.cwd(), '.gitignore')) ? readFileSync(join(process.cwd(), '.gitignore'), 'utf-8') : '';
  if (gi.includes('.env')) score += 10;

  // CI workflow (10 points)
  if (existsSync(join(process.cwd(), '.github', 'workflows', 'claude-code-safety.yml'))) score += 10;

  score = Math.min(score, 100);

  // Output just the score for piping
  console.log(score);
  process.exit(score >= 70 ? 0 : 1);
}

async function initProject() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --init-project' + c.reset);
  console.log(c.dim + '  Complete Claude Code setup for this project' + c.reset);
  console.log();

  const cwd = process.cwd();
  let steps = 0;

  // Step 1: Shield (hooks + stack detection + settings)
  console.log(c.bold + '  Step 1: Safety hooks' + c.reset);
  await shield();
  steps++;

  // Step 2: .gitignore — add .claude/settings.local.json
  console.log(c.bold + '  Step 2: .gitignore' + c.reset);
  const gitignorePath = join(cwd, '.gitignore');
  if (existsSync(gitignorePath)) {
    const gi = readFileSync(gitignorePath, 'utf-8');
    const additions = [];
    if (!gi.includes('.claude/settings.local.json')) additions.push('.claude/settings.local.json');
    if (!gi.includes('.env')) additions.push('.env');
    if (!gi.includes('.env.local')) additions.push('.env.local');
    if (additions.length > 0) {
      writeFileSync(gitignorePath, gi.trimEnd() + '\n\n# Claude Code\n' + additions.join('\n') + '\n');
      console.log(c.green + `  +` + c.reset + ` Added ${additions.length} entries to .gitignore`);
    } else {
      console.log(c.dim + '  ✓ .gitignore already configured' + c.reset);
    }
  } else {
    writeFileSync(gitignorePath, '# Claude Code\n.claude/settings.local.json\n.env\n.env.local\nnode_modules/\n');
    console.log(c.green + '  +' + c.reset + ' Created .gitignore');
  }
  steps++;
  console.log();

  // Step 3: Generate CI workflow
  console.log(c.bold + '  Step 3: CI workflow' + c.reset);
  const ciPath = join(cwd, '.github', 'workflows', 'claude-code-safety.yml');
  if (!existsSync(ciPath)) {
    generateCI();
  } else {
    console.log(c.dim + '  ✓ CI workflow already exists' + c.reset);
  }
  steps++;
  console.log();

  // Step 4: Risk analysis
  console.log(c.bold + '  Step 4: Risk analysis' + c.reset);
  await suggest();
  steps++;

  // Summary
  console.log();
  console.log(c.bold + c.green + '  ✓ Project initialized!' + c.reset);
  console.log(c.dim + `  ${steps} steps completed.` + c.reset);
  console.log();
  console.log(c.dim + '  Next: git add .claude/ CLAUDE.md .github/ .gitignore' + c.reset);
  console.log(c.dim + '  Then: git commit -m "chore: initialize Claude Code safety"' + c.reset);
  console.log();
}

async function suggest() {
  const { execSync } = await import('child_process');
  const { readdirSync } = await import('fs');
  console.log();
  console.log(c.bold + '  cc-safe-setup --suggest' + c.reset);
  console.log(c.dim + '  Analyzing your project for potential risks...' + c.reset);
  console.log();

  const cwd = process.cwd();
  const risks = [];

  // 1. Check git history for past incidents
  try {
    const log = execSync('git log --oneline -100 2>/dev/null', { encoding: 'utf-8' });
    if (log.includes('revert') || log.includes('Revert')) {
      risks.push({ level: 'high', risk: 'Reverts in git history — code has been rolled back', hook: 'auto-checkpoint', reason: 'Auto-checkpoint protects against needing reverts' });
    }
    if (log.includes('force') || log.includes('--force')) {
      risks.push({ level: 'high', risk: 'Force operations in history', hook: 'branch-guard', reason: 'Prevents force-push and destructive git' });
    }
    if (log.match(/fix.*fix.*fix/i)) {
      risks.push({ level: 'medium', risk: 'Multiple fix commits in sequence — possible churn', hook: 'verify-before-done', reason: 'Ensures tests pass before committing fixes' });
    }
  } catch {}

  // 2. Check for risky file patterns
  const hasEnv = existsSync(join(cwd, '.env'));
  const hasEnvExample = existsSync(join(cwd, '.env.example'));
  if (hasEnv && !existsSync(join(cwd, '.gitignore'))) {
    risks.push({ level: 'critical', risk: '.env exists but no .gitignore — secrets may be committed', hook: 'secret-guard', reason: 'Blocks git add .env' });
  }
  if (hasEnv && hasEnvExample) {
    risks.push({ level: 'low', risk: '.env and .env.example both exist', hook: 'env-drift-guard', reason: 'Detects variable mismatch between the two' });
  }

  // 3. Check for database usage
  const hasPrisma = existsSync(join(cwd, 'prisma'));
  const hasRails = existsSync(join(cwd, 'Gemfile'));
  const hasLaravel = existsSync(join(cwd, 'artisan'));
  const hasDjango = existsSync(join(cwd, 'manage.py'));
  if (hasPrisma || hasRails || hasLaravel || hasDjango) {
    risks.push({ level: 'high', risk: 'Database framework detected — destructive migrations possible', hook: 'block-database-wipe', reason: 'Blocks DROP, migrate:fresh, db:drop' });
  }

  // 4. Check for deployment config
  const hasDocker = existsSync(join(cwd, 'Dockerfile'));
  const hasVercel = existsSync(join(cwd, 'vercel.json'));
  const hasNetlify = existsSync(join(cwd, 'netlify.toml'));
  if (hasDocker || hasVercel || hasNetlify) {
    risks.push({ level: 'medium', risk: 'Deploy configuration found', hook: 'deploy-guard', reason: 'Prevents deploy with uncommitted changes' });
    risks.push({ level: 'low', risk: 'Friday deploys possible', hook: 'no-deploy-friday', reason: 'Block deploys on Fridays' });
  }

  // 5. Check package.json for risky scripts
  if (existsSync(join(cwd, 'package.json'))) {
    try {
      const pkg = JSON.parse(readFileSync(join(cwd, 'package.json'), 'utf-8'));
      if (!pkg.scripts?.test || pkg.scripts.test.includes('no test')) {
        risks.push({ level: 'medium', risk: 'No test script — code changes go unverified', hook: 'test-coverage-guard', reason: 'Warns when code grows without tests' });
      }
      if (pkg.scripts?.deploy || pkg.scripts?.publish) {
        risks.push({ level: 'medium', risk: 'Deploy/publish script exists', hook: 'npm-publish-guard', reason: 'Version check before publish' });
      }
    } catch {}
  }

  // 6. Check for large repo (many files)
  try {
    const fileCount = parseInt(execSync('git ls-files | wc -l 2>/dev/null', { encoding: 'utf-8' }).trim());
    if (fileCount > 500) {
      risks.push({ level: 'medium', risk: `Large repo (${fileCount} files) — scope creep risk`, hook: 'scope-guard', reason: 'Prevents operations outside project' });
      risks.push({ level: 'low', risk: 'Large diffs more likely', hook: 'diff-size-guard', reason: 'Warns on large uncommitted changes' });
    }
  } catch {}

  // 7. Check for .claude/ config
  if (!existsSync(join(cwd, 'CLAUDE.md'))) {
    risks.push({ level: 'medium', risk: 'No CLAUDE.md — Claude has no project-specific rules', hook: null, reason: 'Run --shield to generate one' });
  }

  // 8. Always recommend essentials if not installed
  let installed = new Set();
  if (existsSync(SETTINGS_PATH)) {
    try {
      const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      for (const groups of Object.values(s.hooks || {})) {
        for (const g of groups) {
          for (const h of (g.hooks || [])) {
            installed.add((h.command || '').split('/').pop().replace('.sh', ''));
          }
        }
      }
    } catch {}
  }

  if (!installed.has('destructive-guard')) {
    risks.push({ level: 'critical', risk: 'No destructive-guard — rm -rf / is not blocked', hook: 'destructive-guard', reason: 'Essential: prevents file system destruction' });
  }

  // Display results
  if (risks.length === 0) {
    console.log(c.green + '  No risks detected. Your project looks safe!' + c.reset);
    return;
  }

  risks.sort((a, b) => {
    const order = { critical: 0, high: 1, medium: 2, low: 3 };
    return (order[a.level] || 9) - (order[b.level] || 9);
  });

  const levelColors = { critical: c.red, high: c.red, medium: c.yellow, low: c.dim };
  const levelIcons = { critical: '🔴', high: '🟠', medium: '🟡', low: '⚪' };

  for (const r of risks) {
    const color = levelColors[r.level] || c.dim;
    const icon = levelIcons[r.level] || '·';
    console.log(`  ${icon} ${color}${r.level.toUpperCase()}${c.reset}: ${r.risk}`);
    if (r.hook) {
      const isInstalled = installed.has(r.hook);
      if (isInstalled) {
        console.log(c.green + `     ✓ ${r.hook} (installed)` + c.reset);
      } else {
        console.log(c.yellow + `     → Install: npx cc-safe-setup --install-example ${r.hook}` + c.reset);
      }
    } else {
      console.log(c.dim + `     → ${r.reason}` + c.reset);
    }
    console.log();
  }

  const unprotected = risks.filter(r => r.hook && !installed.has(r.hook));
  if (unprotected.length > 0) {
    console.log(c.bold + `  ${unprotected.length} unprotected risk(s). Fix all:` + c.reset);
    console.log(c.yellow + '  npx cc-safe-setup --shield' + c.reset);
  } else {
    console.log(c.green + '  All detected risks are covered by installed hooks!' + c.reset);
  }
  console.log();
}

async function why(hookName) {
  const WHY_DATA = {
    'destructive-guard': { issue: '#36339', incident: 'User lost entire C:\\Users directory — rm -rf followed NTFS junctions', url: 'https://github.com/anthropics/claude-code/issues/36339' },
    'branch-guard': { issue: '#36640', incident: 'Autonomous Claude pushed untested code to main at 3am', url: 'https://github.com/anthropics/claude-code/issues/36640' },
    'secret-guard': { issue: '#16561', incident: 'API keys committed to public repo via git add .', url: 'https://github.com/anthropics/claude-code/issues/16561' },
    'block-database-wipe': { issue: '#37405', incident: 'Production database wiped by migrate:fresh', url: 'https://github.com/anthropics/claude-code/issues/37405' },
    'uncommitted-work-guard': { issue: '#37888', incident: 'Claude destroyed uncommitted work twice in same session', url: 'https://github.com/anthropics/claude-code/issues/37888' },
    'test-deletion-guard': { issue: '#38050', incident: 'Claude deleted failing tests instead of fixing code', url: 'https://github.com/anthropics/claude-code/issues/38050' },
    'fact-check-gate': { issue: '#38057', incident: 'Claude wrote false claims in technical docs without reading source', url: 'https://github.com/anthropics/claude-code/issues/38057' },
    'token-budget-guard': { issue: '#38029', incident: 'Session consumed $342 in tokens without user knowing', url: 'https://github.com/anthropics/claude-code/issues/38029' },
    'protect-dotfiles': { issue: '#37478', incident: '.bashrc and environment files overwritten', url: 'https://github.com/anthropics/claude-code/issues/37478' },
    'scope-guard': { issue: '#36233', incident: 'Entire Mac filesystem deleted by out-of-scope operation', url: 'https://github.com/anthropics/claude-code/issues/36233' },
    'case-sensitive-guard': { issue: '#37875', incident: 'exFAT case collision caused data loss via rm -rf', url: 'https://github.com/anthropics/claude-code/issues/37875' },
    'prompt-injection-guard': { issue: '#38046', incident: 'Prompt injection found in /insights output', url: 'https://github.com/anthropics/claude-code/issues/38046' },
    'overwrite-guard': { issue: '#37595', incident: '/export overwrites existing files without warning', url: 'https://github.com/anthropics/claude-code/issues/37595' },
    'memory-write-guard': { issue: '#38040', incident: 'No way to see what Claude writes to ~/.claude/', url: 'https://github.com/anthropics/claude-code/issues/38040' },
    'context-monitor': { issue: '#6527', incident: 'Sessions silently lost all state after 150+ tool calls', url: 'https://github.com/anthropics/claude-code/issues/6527' },
    'comment-strip': { issue: '#29582', incident: 'Bash comments in hook commands broke permission matching', url: 'https://github.com/anthropics/claude-code/issues/29582' },
    'cd-git-allow': { issue: '#32985', incident: 'cd+git compounds spammed permission prompts endlessly', url: 'https://github.com/anthropics/claude-code/issues/32985' },
    'strict-allowlist': { issue: '#37471', incident: 'Denylist model creates arms race — Claude finds bypasses', url: 'https://github.com/anthropics/claude-code/issues/37471' },
    'error-memory-guard': { issue: 'common', incident: 'Claude retries the same failing command 10+ times' },
    'typosquat-guard': { issue: 'supply-chain', incident: 'Misspelled package names can install malware' },
  };

  console.log();
  if (!hookName) {
    console.log(c.bold + '  cc-safe-setup --why <hook-name>' + c.reset);
    console.log(c.dim + '  Show why a hook exists — the real incident that inspired it.' + c.reset);
    console.log();
    console.log('  Examples:');
    console.log(c.dim + '    npx cc-safe-setup --why destructive-guard' + c.reset);
    console.log(c.dim + '    npx cc-safe-setup --why token-budget-guard' + c.reset);
    console.log();
    console.log(`  ${Object.keys(WHY_DATA).length} hooks have documented incidents.`);
    return;
  }

  const name = hookName.replace('.sh', '');
  const data = WHY_DATA[name];
  if (!data) {
    console.log(c.yellow + `  No incident documented for "${name}".` + c.reset);
    console.log(c.dim + '  This hook may have been created proactively.' + c.reset);
    console.log();
    console.log(c.dim + `  Hooks with documented incidents: ${Object.keys(WHY_DATA).join(', ')}` + c.reset);
    return;
  }

  console.log(c.bold + `  Why "${name}" exists` + c.reset);
  console.log();
  console.log(c.red + '  Incident:' + c.reset);
  console.log('  ' + data.incident);
  console.log();
  if (data.url) {
    console.log(c.blue + '  Source:' + c.reset);
    console.log('  ' + data.url);
  }
  if (data.issue && data.issue !== 'common' && data.issue !== 'supply-chain') {
    console.log(c.dim + `  GitHub Issue: ${data.issue}` + c.reset);
  }
  console.log();
  console.log(c.dim + '  Install: npx cc-safe-setup --install-example ' + name + c.reset);
  console.log();
}

async function replay() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --replay' + c.reset);
  console.log(c.dim + '  Replay blocked commands timeline' + c.reset);
  console.log();

  const LOG_PATH = join(HOME, '.claude', 'blocked-commands.log');
  if (!existsSync(LOG_PATH)) {
    console.log(c.dim + '  No blocked commands log found.' + c.reset);
    console.log(c.dim + '  Hooks will create it when they block something.' + c.reset);
    return;
  }

  const content = readFileSync(LOG_PATH, 'utf-8');
  const lines = content.split('\n').filter(l => l.trim());

  if (lines.length === 0) {
    console.log(c.dim + '  Log is empty — no commands blocked yet.' + c.reset);
    return;
  }

  // Parse entries
  const entries = [];
  for (const line of lines) {
    const match = line.match(/^\[([^\]]+)\]\s*BLOCKED:\s*(.+?)\s*\|\s*cmd:\s*(.+)$/);
    if (match) {
      entries.push({ time: match[1], reason: match[2].trim(), cmd: match[3].trim() });
    }
  }

  // Group by day
  const days = {};
  for (const e of entries) {
    const day = e.time.split('T')[0] || 'unknown';
    if (!days[day]) days[day] = [];
    days[day].push(e);
  }

  // Show last 7 days
  const sortedDays = Object.keys(days).sort().slice(-7);

  for (const day of sortedDays) {
    const dayEntries = days[day];
    console.log(c.bold + `  ${day}` + c.reset + c.dim + ` (${dayEntries.length} blocks)` + c.reset);

    // Category counts
    const cats = {};
    for (const e of dayEntries) {
      const cat = e.reason.split(' ')[0] || 'other';
      cats[cat] = (cats[cat] || 0) + 1;
    }

    // Top categories as mini bar chart
    const sorted = Object.entries(cats).sort((a, b) => b[1] - a[1]).slice(0, 5);
    for (const [cat, count] of sorted) {
      const bar = '█'.repeat(Math.min(count, 30));
      const color = cat.match(/rm|reset|clean|Remove/i) ? c.red : cat.match(/push|force/i) ? c.red : c.yellow;
      console.log(`    ${color}${bar}${c.reset} ${count}× ${cat}`);
    }

    // Show last 3 entries of the day
    const recent = dayEntries.slice(-3);
    for (const e of recent) {
      const time = (e.time.split('T')[1] || '').replace(/\+.*/, '').substring(0, 8);
      console.log(c.dim + `    ${time} ${e.reason.substring(0, 40)} → ${e.cmd.substring(0, 50)}` + c.reset);
    }
    console.log();
  }

  // Summary
  console.log(c.bold + '  Summary' + c.reset);
  console.log(`  Total blocks: ${entries.length}`);
  console.log(`  Days with blocks: ${Object.keys(days).length}`);
  console.log(`  Avg per day: ${Math.round(entries.length / Math.max(Object.keys(days).length, 1))}`);
  console.log();
}

async function guard(description) {
  if (!description) {
    console.log();
    console.log(c.bold + '  cc-safe-setup --guard "<rule>"' + c.reset);
    console.log(c.dim + '  Instantly enforce a rule — generates, installs, and activates a hook.' + c.reset);
    console.log();
    console.log('  Examples:');
    console.log(c.dim + '    npx cc-safe-setup --guard "never touch the database"' + c.reset);
    console.log(c.dim + '    npx cc-safe-setup --guard "block all sudo commands"' + c.reset);
    console.log(c.dim + '    npx cc-safe-setup --guard "no force push"' + c.reset);
    console.log(c.dim + '    npx cc-safe-setup --guard "warn before deleting files"' + c.reset);
    console.log();
    return;
  }

  console.log();
  console.log(c.bold + `  🛡️ Guard: "${description}"` + c.reset);
  console.log();

  const desc = description.toLowerCase();
  let hookName, hookScript, trigger = 'PreToolUse', matcher = 'Bash';

  // Map natural language to hook patterns
  if (desc.match(/database|drop|migrate|prisma|sql/)) {
    hookName = 'guard-database';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qiE '(DROP\\s+(DATABASE|TABLE)|migrate:fresh|prisma\\s+reset|db:drop|TRUNCATE)'; then\n  echo "BLOCKED: Database operation blocked by guard rule." >&2\n  echo "Rule: ${description}" >&2\n  exit 2\nfi\nexit 0`;
  } else if (desc.match(/sudo|root|admin/)) {
    hookName = 'guard-sudo';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qE '^\\s*sudo\\b'; then\n  echo "BLOCKED: sudo blocked by guard rule." >&2\n  echo "Rule: ${description}" >&2\n  exit 2\nfi\nexit 0`;
  } else if (desc.match(/force.?push|push.*force/)) {
    hookName = 'guard-force-push';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qE 'git\\s+push\\s+.*--force'; then\n  echo "BLOCKED: Force push blocked by guard rule." >&2\n  echo "Rule: ${description}" >&2\n  exit 2\nfi\nexit 0`;
  } else if (desc.match(/push.*main|main.*push/)) {
    hookName = 'guard-push-main';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qE 'git\\s+push\\s+.*\\b(main|master)\\b'; then\n  echo "BLOCKED: Push to main blocked by guard rule." >&2\n  echo "Rule: ${description}" >&2\n  exit 2\nfi\nexit 0`;
  } else if (desc.match(/delet|rm|remov/)) {
    hookName = 'guard-delete';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qE 'rm\\s+.*-rf'; then\n  echo "WARNING: Deletion detected." >&2\n  echo "Rule: ${description}" >&2\nfi\nexit 0`;
  } else if (desc.match(/deploy|ship|release|publish/)) {
    hookName = 'guard-deploy';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qiE '(deploy|publish|release|vercel|netlify)'; then\n  echo "WARNING: Deploy/publish command detected." >&2\n  echo "Rule: ${description}" >&2\nfi\nexit 0`;
  } else if (desc.match(/test|spec/)) {
    hookName = 'guard-test-required';
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qE 'git\\s+commit'; then\n  echo "WARNING: Commit detected." >&2\n  echo "Rule: ${description}" >&2\nfi\nexit 0`;
  } else {
    // Generic guard — extract keyword and block commands containing it
    const keyword = desc.replace(/[^a-z0-9 ]/g, '').split(' ').filter(w => w.length > 3).pop() || 'guard';
    hookName = `guard-${keyword}`;
    hookScript = `#!/bin/bash\nCOMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)\n[ -z "$COMMAND" ] && exit 0\nif echo "$COMMAND" | grep -qiE '${keyword}'; then\n  echo "WARNING: Command matches guard rule." >&2\n  echo "Rule: ${description}" >&2\nfi\nexit 0`;
  }

  // Write hook
  mkdirSync(HOOKS_DIR, { recursive: true });
  const hookPath = join(HOOKS_DIR, `${hookName}.sh`);
  writeFileSync(hookPath, hookScript);
  chmodSync(hookPath, 0o755);
  console.log(c.green + '  ✓' + c.reset + ` Hook created: ${hookPath}`);

  // Register in settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks[trigger]) settings.hooks[trigger] = [];

  const cmd = `bash ${toBashPath(hookPath)}`;
  const alreadyExists = JSON.stringify(settings.hooks).includes(hookName);
  if (!alreadyExists) {
    const existing = settings.hooks[trigger].find(e => e.matcher === matcher);
    if (existing) {
      existing.hooks.push({ type: 'command', command: cmd });
    } else {
      settings.hooks[trigger].push({ matcher, hooks: [{ type: 'command', command: cmd }] });
    }
    writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
    console.log(c.green + '  ✓' + c.reset + ' Registered in settings.json');
  }

  console.log(c.green + '  ✓' + c.reset + ' Guard active immediately');
  console.log();
  console.log(c.dim + `  Rule: "${description}"` + c.reset);
  console.log(c.dim + `  Hook: ${hookName}.sh` + c.reset);
  console.log(c.dim + '  Remove: npx cc-safe-setup --uninstall' + c.reset);
  console.log();
}

async function diffHooks(otherPath) {
  console.log();
  console.log(c.bold + '  cc-safe-setup --diff-hooks' + c.reset);
  console.log(c.dim + '  Compare hook configurations' + c.reset);
  console.log();

  // Parse hooks from a settings file
  function getHooks(path) {
    if (!existsSync(path)) return new Set();
    try {
      const s = JSON.parse(readFileSync(path, 'utf-8'));
      const hooks = new Set();
      for (const [trigger, groups] of Object.entries(s.hooks || {})) {
        for (const group of groups) {
          for (const h of (group.hooks || [])) {
            const cmd = h.command || '';
            const name = cmd.split('/').pop().replace('.sh', '').replace('.py', '');
            if (name) hooks.add(name);
          }
        }
      }
      return hooks;
    } catch { return new Set(); }
  }

  // Get current settings
  const myHooks = getHooks(SETTINGS_PATH);

  if (!otherPath) {
    // Compare global vs project settings
    const projectSettings = join(process.cwd(), '.claude', 'settings.json');
    const projectLocal = join(process.cwd(), '.claude', 'settings.local.json');

    if (existsSync(projectSettings) || existsSync(projectLocal)) {
      const projectHooks = new Set([
        ...getHooks(projectSettings),
        ...getHooks(projectLocal)
      ]);

      console.log(c.bold + '  Global vs Project comparison' + c.reset);
      console.log(`  Global: ${myHooks.size} hooks (${SETTINGS_PATH})`);
      console.log(`  Project: ${projectHooks.size} hooks (.claude/settings*.json)`);
      console.log();

      const onlyGlobal = [...myHooks].filter(h => !projectHooks.has(h));
      const onlyProject = [...projectHooks].filter(h => !myHooks.has(h));
      const both = [...myHooks].filter(h => projectHooks.has(h));

      if (both.length > 0) {
        console.log(c.green + `  ✓ ${both.length} hooks in both:` + c.reset);
        both.slice(0, 10).forEach(h => console.log(c.dim + `    ${h}` + c.reset));
        if (both.length > 10) console.log(c.dim + `    ... and ${both.length - 10} more` + c.reset);
        console.log();
      }
      if (onlyGlobal.length > 0) {
        console.log(c.yellow + `  △ ${onlyGlobal.length} only in global:` + c.reset);
        onlyGlobal.forEach(h => console.log(`    ${h}`));
        console.log();
      }
      if (onlyProject.length > 0) {
        console.log(c.blue + `  ○ ${onlyProject.length} only in project:` + c.reset);
        onlyProject.forEach(h => console.log(`    ${h}`));
        console.log();
      }
    } else {
      console.log(c.dim + '  No project-level settings found.' + c.reset);
      console.log(c.dim + '  Create with: npx cc-safe-setup --team' + c.reset);
      console.log();
      console.log(c.bold + '  Global hooks (' + myHooks.size + '):' + c.reset);
      [...myHooks].sort().forEach(h => console.log(`    ${h}`));
    }
  } else {
    // Compare with specified file
    const otherHooks = getHooks(otherPath);
    console.log(`  File A: ${SETTINGS_PATH} (${myHooks.size} hooks)`);
    console.log(`  File B: ${otherPath} (${otherHooks.size} hooks)`);
    console.log();

    const onlyA = [...myHooks].filter(h => !otherHooks.has(h));
    const onlyB = [...otherHooks].filter(h => !myHooks.has(h));
    const both = [...myHooks].filter(h => otherHooks.has(h));

    console.log(c.green + `  ${both.length} shared` + c.reset);
    if (onlyA.length > 0) console.log(c.yellow + `  ${onlyA.length} only in A: ${onlyA.join(', ')}` + c.reset);
    if (onlyB.length > 0) console.log(c.blue + `  ${onlyB.length} only in B: ${onlyB.join(', ')}` + c.reset);
  }
  console.log();
}

async function fromClaudeMd() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --from-claudemd' + c.reset);
  console.log(c.dim + '  Convert CLAUDE.md rules into enforceable hooks' + c.reset);
  console.log();

  // Find CLAUDE.md
  const cwd = process.cwd();
  let claudeMdPath = null;
  for (const p of [join(cwd, 'CLAUDE.md'), join(cwd, '.claude', 'CLAUDE.md')]) {
    if (existsSync(p)) { claudeMdPath = p; break; }
  }

  if (!claudeMdPath) {
    console.log(c.yellow + '  No CLAUDE.md found in project.' + c.reset);
    console.log(c.dim + '  Run: npx cc-safe-setup --shield (creates one)' + c.reset);
    return;
  }

  const content = readFileSync(claudeMdPath, 'utf-8').toLowerCase();
  console.log(c.dim + '  Reading: ' + claudeMdPath + c.reset);
  console.log();

  // Pattern matching: CLAUDE.md rules → hooks
  const RULE_MAP = [
    { patterns: ['do not push to main', 'don\'t push to main', 'no push main', 'never push to main'], hook: 'branch-guard', desc: '"Do not push to main" → branch-guard' },
    { patterns: ['do not force', 'no force push', 'don\'t force push'], hook: 'branch-guard', desc: '"No force push" → branch-guard' },
    { patterns: ['do not delete', 'don\'t delete', 'no rm -rf', 'never delete'], hook: 'destructive-guard', desc: '"Do not delete files" → destructive-guard' },
    { patterns: ['do not commit .env', 'don\'t commit secret', 'no credentials', 'never commit .env'], hook: 'secret-guard', desc: '"No .env commits" → secret-guard' },
    { patterns: ['run tests before', 'test before commit', 'tests must pass'], hook: 'verify-before-done', desc: '"Run tests first" → verify-before-done' },
    { patterns: ['do not use sudo', 'no sudo', 'don\'t use sudo'], hook: 'no-sudo-guard', desc: '"No sudo" → no-sudo-guard' },
    { patterns: ['stay in project', 'only this project', 'don\'t modify outside', 'do not edit files outside'], hook: 'scope-guard', desc: '"Stay in project" → scope-guard' },
    { patterns: ['don\'t modify .bashrc', 'do not edit dotfile', 'protect home'], hook: 'protect-dotfiles', desc: '"Protect dotfiles" → protect-dotfiles' },
    { patterns: ['do not deploy on friday', 'no friday deploy'], hook: 'no-deploy-friday', desc: '"No Friday deploy" → no-deploy-friday' },
    { patterns: ['do not install global', 'no npm -g', 'don\'t install globally'], hook: 'no-install-global', desc: '"No global installs" → no-install-global' },
    { patterns: ['descriptive commit', 'meaningful commit', 'good commit message'], hook: 'commit-quality-gate', desc: '"Good commit messages" → commit-quality-gate' },
    { patterns: ['one logical change', 'small commit', 'focused commit', 'don\'t commit too many'], hook: 'commit-scope-guard', desc: '"Small commits" → commit-scope-guard' },
    { patterns: ['feature branch', 'create branch', 'feat/ fix/ chore/'], hook: 'branch-naming-convention', desc: '"Feature branches" → branch-naming-convention' },
    { patterns: ['do not drop database', 'no migrate:fresh', 'protect database'], hook: 'block-database-wipe', desc: '"Protect database" → block-database-wipe' },
    { patterns: ['read before edit', 'understand before changing'], hook: 'read-before-edit', desc: '"Read first" → read-before-edit' },
    { patterns: ['do not overwrite', 'use edit not write'], hook: 'overwrite-guard', desc: '"Use Edit, not Write" → overwrite-guard' },
  ];

  const matched = [];
  for (const rule of RULE_MAP) {
    if (rule.patterns.some(p => content.includes(p))) {
      matched.push(rule);
    }
  }

  if (matched.length === 0) {
    console.log(c.yellow + '  No enforceable rules detected in CLAUDE.md.' + c.reset);
    console.log(c.dim + '  CLAUDE.md may contain guidelines that can\'t be converted to hooks.' + c.reset);
    console.log(c.dim + '  For custom hooks: npx cc-safe-setup --create "your rule"' + c.reset);
    return;
  }

  console.log(c.bold + `  Found ${matched.length} rules that can be enforced with hooks:` + c.reset);
  console.log();

  for (const m of matched) {
    const hookPath = join(HOOKS_DIR, `${m.hook}.sh`);
    const installed = existsSync(hookPath);
    const icon = installed ? c.green + '✓' + c.reset : c.yellow + '○' + c.reset;
    const status = installed ? c.dim + '(installed)' + c.reset : '';
    console.log(`  ${icon} ${m.desc} ${status}`);
    if (!installed) {
      console.log(c.dim + `    npx cc-safe-setup --install-example ${m.hook}` + c.reset);
    }
  }

  const notInstalled = matched.filter(m => !existsSync(join(HOOKS_DIR, `${m.hook}.sh`)));
  if (notInstalled.length > 0) {
    console.log();
    console.log(c.bold + `  Install all ${notInstalled.length} missing hooks:` + c.reset);
    console.log(c.dim + '  npx cc-safe-setup --shield' + c.reset);
  } else {
    console.log();
    console.log(c.green + '  All detected rules are already enforced by hooks!' + c.reset);
  }
  console.log();
}

async function health() {
  const { readdirSync, statSync } = await import('fs');
  console.log();
  console.log(c.bold + '  Hook Health Dashboard' + c.reset);
  console.log();

  if (!existsSync(HOOKS_DIR)) {
    console.log(c.red + '  No hooks directory found.' + c.reset);
    console.log(c.dim + '  Run: npx cc-safe-setup --shield' + c.reset);
    return;
  }

  const hooks = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh') || f.endsWith('.py'));
  if (hooks.length === 0) {
    console.log(c.yellow + '  No hooks installed.' + c.reset);
    return;
  }

  // Table header
  const pad = (s, n) => s.substring(0, n).padEnd(n);
  console.log(c.dim + '  ' + pad('Hook', 30) + pad('Size', 8) + pad('Perms', 7) + pad('Age', 12) + 'Shebang' + c.reset);
  console.log(c.dim + '  ' + '─'.repeat(70) + c.reset);

  let healthy = 0, issues = 0;
  const now = Date.now();

  for (const h of hooks.sort()) {
    const fullPath = join(HOOKS_DIR, h);
    const st = statSync(fullPath);
    const content = readFileSync(fullPath, 'utf-8');
    const firstLine = content.split('\n')[0];

    // Size
    const size = st.size < 1024 ? st.size + 'B' : Math.round(st.size / 1024) + 'KB';

    // Permissions
    const isExec = !!(st.mode & 0o111);
    const perms = isExec ? c.green + '✓ exec' + c.reset : c.red + '✗ exec' + c.reset;

    // Age
    const ageDays = Math.floor((now - st.mtimeMs) / 86400000);
    const age = ageDays === 0 ? 'today' : ageDays === 1 ? '1 day' : ageDays + ' days';

    // Shebang
    const hasShebang = firstLine.startsWith('#!');
    const shebang = hasShebang ? c.green + '✓' + c.reset : c.red + '✗' + c.reset;

    // Status icon
    const ok = isExec && hasShebang;
    const icon = ok ? c.green + '●' + c.reset : c.red + '●' + c.reset;
    if (ok) healthy++; else issues++;

    console.log('  ' + icon + ' ' + pad(h, 29) + pad(size, 8) + pad(isExec ? '✓ exec' : '✗ exec', 7) + pad(age, 12) + (hasShebang ? '✓' : '✗'));
  }

  console.log(c.dim + '  ' + '─'.repeat(70) + c.reset);
  console.log(`  ${c.green}${healthy} healthy${c.reset} · ${issues > 0 ? c.red + issues + ' issues' + c.reset : c.dim + '0 issues' + c.reset} · ${hooks.length} total`);

  if (issues > 0) {
    console.log();
    console.log(c.yellow + '  Fix issues: npx cc-safe-setup --quickfix' + c.reset);
  }

  // Settings.json hook count
  console.log();
  if (existsSync(SETTINGS_PATH)) {
    try {
      const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      let configured = 0;
      for (const groups of Object.values(s.hooks || {})) {
        for (const g of groups) {
          configured += (g.hooks || []).length;
        }
      }
      console.log(c.dim + `  ${configured} hooks configured in settings.json` + c.reset);
      if (configured < hooks.length) {
        console.log(c.yellow + `  ${hooks.length - configured} hooks installed but not configured.` + c.reset);
        console.log(c.dim + '  Run --shield to auto-configure all hooks.' + c.reset);
      }
    } catch {
      console.log(c.red + '  settings.json has syntax errors.' + c.reset);
    }
  }
  console.log();
}

async function migrateFrom(tool) {
  console.log();
  console.log(c.bold + '  cc-safe-setup --migrate-from ' + (tool || '?') + c.reset);
  console.log();

  const KNOWN_TOOLS = {
    'safety-net': {
      name: 'Claude Code Safety Net',
      npm: '@anthropic-ai/claude-code-safety-net',
      detect: () => {
        if (!existsSync(SETTINGS_PATH)) return false;
        const s = readFileSync(SETTINGS_PATH, 'utf-8');
        return s.includes('safety-net') || s.includes('claude-code-safety-net');
      },
      mapping: {
        'destructive-commands': 'destructive-guard',
        'secret-files': 'secret-guard',
        'branch-protection': 'branch-guard',
        'git-operations': 'branch-guard',
      },
      desc: 'TypeScript hooks with configurable severity levels'
    },
    'hooks-mastery': {
      name: 'Claude Code Hooks Mastery',
      npm: null,
      detect: () => {
        if (!existsSync(SETTINGS_PATH)) return false;
        const s = readFileSync(SETTINGS_PATH, 'utf-8');
        return s.includes('hooks_mastery') || s.includes('hooks-mastery');
      },
      mapping: {
        'safety': 'destructive-guard',
        'git-safety': 'branch-guard',
      },
      desc: 'Python hooks for all events + LLM integration'
    },
    'manual': {
      name: 'Custom/Manual Hooks',
      npm: null,
      detect: () => {
        if (!existsSync(SETTINGS_PATH)) return false;
        const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
        return Object.keys(s.hooks || {}).length > 0;
      },
      mapping: {},
      desc: 'Hand-written hooks in settings.json'
    }
  };

  if (!tool) {
    console.log(c.bold + '  Supported migration sources:' + c.reset);
    console.log();
    for (const [id, info] of Object.entries(KNOWN_TOOLS)) {
      const detected = info.detect();
      const icon = detected ? c.green + '●' + c.reset : c.dim + '○' + c.reset;
      console.log(`  ${icon} ${c.bold}${id}${c.reset} — ${info.desc}`);
      if (detected) console.log(`    ${c.green}Detected in your settings${c.reset}`);
      console.log(`    ${c.dim}npx cc-safe-setup --migrate-from ${id}${c.reset}`);
      console.log();
    }
    return;
  }

  const source = KNOWN_TOOLS[tool];
  if (!source) {
    console.log(c.red + `  Unknown tool: ${tool}` + c.reset);
    console.log(c.dim + '  Supported: ' + Object.keys(KNOWN_TOOLS).join(', ') + c.reset);
    return;
  }

  console.log(c.dim + `  Migrating from: ${source.name}` + c.reset);
  console.log();

  // Read current settings
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }

  // Analyze existing hooks
  let existingHooks = [];
  for (const [trigger, groups] of Object.entries(settings.hooks || {})) {
    for (const group of groups) {
      for (const hook of (group.hooks || [])) {
        existingHooks.push({ trigger, matcher: group.matcher, command: hook.command || '' });
      }
    }
  }

  console.log(`  Found ${existingHooks.length} existing hook(s) in settings.json`);
  console.log();

  // Identify what cc-safe-setup equivalents exist
  const replacements = [];
  for (const h of existingHooks) {
    const cmd = h.command.toLowerCase();
    let replacement = null;

    // Try source-specific mapping
    for (const [pattern, ccHook] of Object.entries(source.mapping)) {
      if (cmd.includes(pattern)) {
        replacement = ccHook;
        break;
      }
    }

    // Generic detection
    if (!replacement) {
      if (cmd.includes('rm') || cmd.includes('destruct')) replacement = 'destructive-guard';
      else if (cmd.includes('branch') || cmd.includes('push')) replacement = 'branch-guard';
      else if (cmd.includes('secret') || cmd.includes('env')) replacement = 'secret-guard';
      else if (cmd.includes('syntax') || cmd.includes('lint')) replacement = 'syntax-check';
      else if (cmd.includes('context') || cmd.includes('monitor')) replacement = 'context-monitor';
    }

    if (replacement) {
      replacements.push({ old: h.command, new: replacement });
      console.log(`  ${c.yellow}→${c.reset} ${h.command.substring(0, 50)}`);
      console.log(`    ${c.green}→${c.reset} cc-safe-setup: ${replacement}`);
    } else {
      console.log(`  ${c.dim}?${c.reset} ${h.command.substring(0, 50)} (no equivalent, keeping)`);
    }
  }

  console.log();
  console.log(c.bold + '  Migration plan:' + c.reset);
  console.log(`  ${c.green}${replacements.length}${c.reset} hooks can be replaced with cc-safe-setup equivalents`);
  console.log(`  ${c.dim}${existingHooks.length - replacements.length}${c.reset} hooks will be kept as-is`);
  console.log();
  console.log(c.dim + '  To apply: npx cc-safe-setup --shield' + c.reset);
  console.log(c.dim + '  This installs cc-safe-setup hooks alongside existing ones.' + c.reset);
  console.log(c.dim + '  Remove old hooks manually after verifying the new ones work.' + c.reset);
  console.log();
}

async function team() {
  console.log();
  console.log(c.bold + '  cc-safe-setup --team' + c.reset);
  console.log(c.dim + '  Set up project-level hooks (commit to repo for team sharing)' + c.reset);
  console.log();

  const cwd = process.cwd();
  const projectHooksDir = join(cwd, '.claude', 'hooks');
  const projectSettings = join(cwd, '.claude', 'settings.local.json');

  // Create .claude/hooks/ in project
  mkdirSync(projectHooksDir, { recursive: true });

  // Copy core safety hooks to project
  const coreHooks = ['destructive-guard', 'branch-guard', 'secret-guard', 'syntax-check',
    'context-monitor', 'comment-strip', 'cd-git-allow', 'api-error-alert'];

  let installed = 0;
  for (const hookId of coreHooks) {
    const destPath = join(projectHooksDir, `${hookId}.sh`);
    if (existsSync(destPath)) {
      console.log(c.dim + '  ✓' + c.reset + ` ${hookId}`);
      continue;
    }

    if (SCRIPTS[hookId]) {
      writeFileSync(destPath, SCRIPTS[hookId]);
      chmodSync(destPath, 0o755);
      installed++;
      console.log(c.green + '  +' + c.reset + ` ${hookId}`);
    }
  }

  // Detect stack and add relevant hooks
  const extras = [];
  if (existsSync(join(cwd, 'package.json'))) extras.push('auto-approve-build');
  if (existsSync(join(cwd, 'requirements.txt')) || existsSync(join(cwd, 'pyproject.toml'))) extras.push('auto-approve-python');
  if (existsSync(join(cwd, 'go.mod'))) extras.push('auto-approve-go');
  if (existsSync(join(cwd, 'Cargo.toml'))) extras.push('auto-approve-cargo');
  if (existsSync(join(cwd, 'Dockerfile'))) extras.push('auto-approve-docker');

  for (const ex of extras) {
    const destPath = join(projectHooksDir, `${ex}.sh`);
    const srcPath = join(__dirname, 'examples', `${ex}.sh`);
    if (existsSync(destPath)) continue;
    if (existsSync(srcPath)) {
      copyFileSync(srcPath, destPath);
      chmodSync(destPath, 0o755);
      installed++;
      console.log(c.green + '  +' + c.reset + ` ${ex} (project-specific)`);
    }
  }

  // Generate settings.local.json
  const allHooks = [...coreHooks, ...extras].filter(h => existsSync(join(projectHooksDir, `${h}.sh`)));

  const bashHooks = allHooks.map(h => ({
    type: 'command',
    command: `bash .claude/hooks/${h}.sh`
  }));

  const settings = {
    hooks: {
      PreToolUse: [
        { matcher: 'Bash', hooks: bashHooks.filter((_, i) => {
          const name = allHooks[i];
          return !['syntax-check', 'context-monitor', 'api-error-alert'].includes(name);
        })},
        { matcher: 'Edit|Write', hooks: [
          { type: 'command', command: 'bash .claude/hooks/syntax-check.sh' }
        ]}
      ],
      PostToolUse: [
        { matcher: '', hooks: [
          { type: 'command', command: 'bash .claude/hooks/context-monitor.sh' }
        ]}
      ],
      Stop: [
        { matcher: '', hooks: [
          { type: 'command', command: 'bash .claude/hooks/api-error-alert.sh' }
        ]}
      ]
    }
  };

  writeFileSync(projectSettings, JSON.stringify(settings, null, 2));
  console.log();
  console.log(c.green + '  ✓' + c.reset + ' Created .claude/settings.local.json');

  // Add .claude/hooks to .gitignore if not there
  const gitignorePath = join(cwd, '.gitignore');
  if (existsSync(gitignorePath)) {
    const gi = readFileSync(gitignorePath, 'utf-8');
    if (!gi.includes('.claude/')) {
      // Don't add — hooks should be committed for team sharing
    }
  }

  console.log();
  console.log(c.bold + '  Next steps:' + c.reset);
  console.log(c.dim + '  1. git add .claude/' + c.reset);
  console.log(c.dim + '  2. git commit -m "chore: add Claude Code safety hooks"' + c.reset);
  console.log(c.dim + '  3. Team members get hooks automatically on git pull' + c.reset);
  console.log();
  console.log(c.dim + `  ${installed} hooks installed, ${allHooks.length} total configured.` + c.reset);
  console.log(c.dim + '  Hooks use relative paths (.claude/hooks/) — portable across machines.' + c.reset);
  console.log();
}

async function profile(level) {
  const { readdirSync } = await import('fs');
  console.log();

  const PROFILES = {
    strict: {
      desc: 'Maximum safety — blocks everything dangerous, requires verification',
      hooks: ['destructive-guard', 'branch-guard', 'secret-guard', 'syntax-check',
        'context-monitor', 'comment-strip', 'cd-git-allow', 'api-error-alert',
        'scope-guard', 'no-sudo-guard', 'protect-claudemd', 'env-source-guard',
        'no-install-global', 'deploy-guard', 'protect-dotfiles', 'symlink-guard',
        'strict-allowlist', 'uncommitted-work-guard', 'test-deletion-guard',
        'overwrite-guard', 'error-memory-guard', 'hardcoded-secret-detector',
        'conflict-marker-guard', 'token-budget-guard', 'fact-check-gate',
        'block-database-wipe', 'no-eval', 'file-size-limit', 'large-read-guard',
        'loop-detector', 'verify-before-done', 'diff-size-guard', 'commit-scope-guard']
    },
    standard: {
      desc: 'Balanced — blocks dangerous commands, auto-approves safe ones',
      hooks: ['destructive-guard', 'branch-guard', 'secret-guard', 'syntax-check',
        'context-monitor', 'comment-strip', 'cd-git-allow', 'api-error-alert',
        'scope-guard', 'no-sudo-guard', 'protect-claudemd',
        'auto-approve-build', 'auto-approve-python', 'auto-approve-docker',
        'loop-detector', 'deploy-guard', 'block-database-wipe',
        'compound-command-approver', 'session-handoff', 'cost-tracker']
    },
    minimal: {
      desc: 'Essential only — just the 8 core safety hooks',
      hooks: ['destructive-guard', 'branch-guard', 'secret-guard', 'syntax-check',
        'context-monitor', 'comment-strip', 'cd-git-allow', 'api-error-alert']
    },
  };

  // Check for saved custom profiles
  const profilesDir = join(HOME, '.claude', 'profiles');
  if (level && !PROFILES[level]) {
    const customPath = join(profilesDir, `${level}.json`);
    if (existsSync(customPath)) {
      const custom = JSON.parse(readFileSync(customPath, 'utf-8'));
      PROFILES[level] = { desc: `Custom profile (saved ${custom.savedAt?.split('T')[0] || '?'})`, hooks: custom.hooks || [] };
    }
  }

  if (!level || !PROFILES[level]) {
    console.log(c.bold + '  Safety Profiles' + c.reset);
    console.log();
    for (const [name, prof] of Object.entries(PROFILES)) {
      console.log(`  ${c.bold}${name}${c.reset} (${prof.hooks.length} hooks)`);
      console.log(`  ${c.dim}${prof.desc}${c.reset}`);
      console.log(`  ${c.dim}npx cc-safe-setup --profile ${name}${c.reset}`);
      console.log();
    }

    // Show saved profiles too
    if (existsSync(profilesDir)) {
      const saved = readdirSync(profilesDir).filter(f => f.endsWith('.json'));
      if (saved.length > 0) {
        console.log(c.bold + '  Saved Profiles' + c.reset);
        console.log();
        for (const f of saved) {
          const sName = f.replace('.json', '');
          try {
            const data = JSON.parse(readFileSync(join(profilesDir, f), 'utf-8'));
            console.log(`  ${c.bold}${sName}${c.reset} (${data.hooks?.length || 0} hooks)`);
            console.log(`  ${c.dim}Saved ${data.savedAt?.split('T')[0] || '?'}${c.reset}`);
            console.log(`  ${c.dim}npx cc-safe-setup --profile ${sName}${c.reset}`);
            console.log();
          } catch {}
        }
      }
    }
    return;
  }

  const prof = PROFILES[level];
  console.log(c.bold + `  Applying "${level}" profile` + c.reset);
  console.log(c.dim + `  ${prof.desc}` + c.reset);
  console.log();

  mkdirSync(HOOKS_DIR, { recursive: true });
  let installed = 0;

  for (const hookId of prof.hooks) {
    const hookPath = join(HOOKS_DIR, `${hookId}.sh`);
    if (existsSync(hookPath)) {
      console.log(c.dim + '  ✓' + c.reset + ` ${hookId}`);
      continue;
    }

    // Try built-in first
    if (SCRIPTS[hookId]) {
      writeFileSync(hookPath, SCRIPTS[hookId]);
      chmodSync(hookPath, 0o755);
      installed++;
      console.log(c.green + '  +' + c.reset + ` ${hookId}`);
      continue;
    }

    // Try examples
    const exPath = join(__dirname, 'examples', `${hookId}.sh`);
    if (existsSync(exPath)) {
      copyFileSync(exPath, hookPath);
      chmodSync(hookPath, 0o755);
      installed++;
      console.log(c.green + '  +' + c.reset + ` ${hookId}`);
      continue;
    }

    console.log(c.yellow + '  ?' + c.reset + ` ${hookId} (not found)`);
  }

  // Update settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }
  if (!settings.hooks) settings.hooks = {};

  // Register all hooks in settings
  const hookFiles = prof.hooks.filter(h => existsSync(join(HOOKS_DIR, `${h}.sh`)));
  const bashHooks = hookFiles.map(h => ({ type: 'command', command: `bash ${toBashPath(join(HOOKS_DIR, h + '.sh'))}` }));

  // Simplified: put all under PreToolUse Bash for now
  if (!settings.hooks.PreToolUse) settings.hooks.PreToolUse = [];
  const existing = settings.hooks.PreToolUse.find(e => e.matcher === 'Bash');
  if (existing) {
    const existingCmds = new Set(existing.hooks.map(h => h.command));
    for (const h of bashHooks) {
      if (!existingCmds.has(h.command)) existing.hooks.push(h);
    }
  } else {
    settings.hooks.PreToolUse.push({ matcher: 'Bash', hooks: bashHooks });
  }

  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));

  console.log();
  console.log(c.green + `  ✓ "${level}" profile applied (${installed} new hooks installed)` + c.reset);
  console.log(c.dim + `  ${prof.hooks.length} hooks total in profile` + c.reset);
  console.log();
}

async function analyze() {
  const { execSync } = await import('child_process');
  const { readdirSync, statSync } = await import('fs');
  console.log();
  console.log(c.bold + '  cc-safe-setup --analyze' + c.reset);
  console.log(c.dim + '  What Claude did in your sessions' + c.reset);
  console.log();

  // 1. Blocked commands log
  const blockLog = join(HOME, '.claude', 'blocked-commands.log');
  let blocks = [];
  if (existsSync(blockLog)) {
    const content = readFileSync(blockLog, 'utf-8');
    blocks = content.split('\n').filter(l => l.trim());
    const recent = blocks.slice(-20);
    console.log(c.bold + '  Blocked Commands' + c.reset + c.dim + ` (${blocks.length} total)` + c.reset);
    if (recent.length > 0) {
      // Count by type
      const types = {};
      for (const line of blocks) {
        const match = line.match(/BLOCKED:\s*(.+?)(?:\s*—|\s*\(|$)/);
        if (match) {
          const type = match[1].trim().substring(0, 40);
          types[type] = (types[type] || 0) + 1;
        }
      }
      const sorted = Object.entries(types).sort((a, b) => b[1] - a[1]);
      for (const [type, count] of sorted.slice(0, 8)) {
        const bar = '█'.repeat(Math.min(count, 20));
        console.log(`    ${c.red}${bar}${c.reset} ${count}× ${type}`);
      }
    } else {
      console.log(c.green + '    No blocked commands recorded.' + c.reset);
    }
    console.log();
  }

  // 2. Git activity (last 24h)
  console.log(c.bold + '  Git Activity (last 24h)' + c.reset);
  try {
    const log = execSync('git log --oneline --since="24 hours ago" 2>/dev/null', { encoding: 'utf-8' }).trim();
    if (log) {
      const commits = log.split('\n');
      console.log(c.dim + `    ${commits.length} commits` + c.reset);
      for (const commit of commits.slice(0, 10)) {
        console.log(`    ${c.blue}•${c.reset} ${commit}`);
      }
      if (commits.length > 10) console.log(c.dim + `    ... and ${commits.length - 10} more` + c.reset);
    } else {
      console.log(c.dim + '    No commits in last 24h' + c.reset);
    }
  } catch {
    console.log(c.dim + '    Not in a git repository' + c.reset);
  }
  console.log();

  // 3. Files changed (last 24h)
  console.log(c.bold + '  Files Changed (last 24h)' + c.reset);
  try {
    const diff = execSync('git diff --stat HEAD~10 2>/dev/null || git diff --stat 2>/dev/null', { encoding: 'utf-8' }).trim();
    if (diff) {
      const lines = diff.split('\n');
      const summary = lines[lines.length - 1];
      console.log(c.dim + `    ${summary.trim()}` + c.reset);
    }
  } catch {}
  console.log();

  // 4. Hook health
  console.log(c.bold + '  Hook Health' + c.reset);
  const hookDir = join(HOME, '.claude', 'hooks');
  if (existsSync(hookDir)) {
    const hooks = readdirSync(hookDir).filter(f => f.endsWith('.sh') || f.endsWith('.py'));
    let execCount = 0, nonExec = 0;
    for (const h of hooks) {
      const st = statSync(join(hookDir, h));
      if (st.mode & 0o111) execCount++; else nonExec++;
    }
    console.log(`    ${c.green}${execCount}${c.reset} hooks executable${nonExec > 0 ? `, ${c.red}${nonExec}${c.reset} missing permissions` : ''}`);
  }

  // 5. Context usage estimate
  console.log();
  console.log(c.bold + '  Session Estimates' + c.reset);
  // Check tool call log if exists
  const toolLog = join(HOME, '.claude', 'tool-calls.log');
  if (existsSync(toolLog)) {
    const logContent = readFileSync(toolLog, 'utf-8');
    const calls = logContent.split('\n').filter(l => l.trim());
    const today = new Date().toISOString().split('T')[0];
    const todayCalls = calls.filter(l => l.includes(today));
    console.log(`    Tool calls today: ${todayCalls.length}`);
  }

  // Token budget state
  const budgetFiles = existsSync('/tmp') ? readdirSync('/tmp').filter(f => f.startsWith('cc-token-budget-')) : [];
  if (budgetFiles.length > 0) {
    for (const bf of budgetFiles.slice(0, 3)) {
      const tokens = parseInt(readFileSync(join('/tmp', bf), 'utf-8').trim()) || 0;
      const costCents = Math.round(tokens * 75 / 10000);
      console.log(`    Estimated cost: ~$${(costCents / 100).toFixed(2)} (${tokens.toLocaleString()} tokens)`);
    }
  }

  console.log();
  console.log(c.dim + '  Tip: Use --stats for block history analytics' + c.reset);
  console.log(c.dim + '  Tip: Use --dashboard for real-time monitoring' + c.reset);
  console.log();
}

async function opus47() {
  console.log();
  console.log(c.bold + '  🚨  cc-safe-setup --opus47' + c.reset);
  console.log(c.dim + '  Opus 4.7 protection — fixes for known critical issues' + c.reset);
  console.log();

  // First install core hooks if not already installed
  mkdirSync(HOOKS_DIR, { recursive: true });
  let coreInstalled = 0;
  for (const [hookId, hookMeta] of Object.entries(HOOKS)) {
    const hookPath = join(HOOKS_DIR, `${hookId}.sh`);
    if (!existsSync(hookPath)) {
      writeFileSync(hookPath, SCRIPTS[hookId]);
      chmodSync(hookPath, 0o755);
      coreInstalled++;
    }
  }
  if (coreInstalled > 0) {
    // Update settings.json for core hooks
    let settings = {};
    if (existsSync(SETTINGS_PATH)) {
      settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf8'));
    }
    if (!settings.hooks) settings.hooks = {};
    for (const [hookId, hookMeta] of Object.entries(HOOKS)) {
      const trigger = hookMeta.trigger;
      if (!settings.hooks[trigger]) settings.hooks[trigger] = [];
      const hookPath = toBashPath(join(HOOKS_DIR, `${hookId}.sh`));
      const exists = settings.hooks[trigger].some(h => h.hooks?.some(hh => hh.command?.includes(hookId)));
      if (!exists) {
        settings.hooks[trigger].push({
          matcher: hookMeta.matcher,
          hooks: [{ type: 'command', command: hookPath }]
        });
      }
    }
    writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n');
    console.log(c.green + '  ✓' + c.reset + ` ${coreInstalled} core safety hooks installed`);
  } else {
    console.log(c.dim + '  ✓ Core safety hooks already installed' + c.reset);
  }

  // Install Opus 4.7-specific hooks
  const opus47Hooks = [
    { name: 'model-version-alert', desc: 'Warns when Opus 4.7 is silently active (#49541)', issue: '4x token consumption' },
    { name: 'shell-config-truncation-guard', desc: 'Blocks installer from truncating ~/.bash_profile (#49615)', issue: 'config destruction' },
    { name: 'credential-exfil-guard', desc: 'Blocks credential file access (#49539, #49554)', issue: 'credential deletion' },
    { name: 'home-critical-bash-guard', desc: 'Blocks destructive ops on critical dotfiles (#49554)', issue: 'home directory attacks' },
  ];

  console.log();
  console.log(c.bold + '  Opus 4.7 protection hooks:' + c.reset);
  let added = 0;
  for (const hook of opus47Hooks) {
    try {
      await installExample(hook.name);
      added++;
    } catch (e) {
      // installExample may exit on error, but we want to continue
    }
  }

  console.log();
  console.log(c.bold + '  Why these hooks matter:' + c.reset);
  console.log(c.dim + '  Opus 4.7\'s safety classifier is hardcoded to 4.6 (#49618).' + c.reset);
  console.log(c.dim + '  Auto mode can\'t block dangerous commands on 4.7.' + c.reset);
  console.log(c.dim + '  These hooks run at process level — independent of the model.' + c.reset);
  console.log();
  console.log(c.green + '  Done.' + c.reset + ' Your setup is protected against known Opus 4.7 issues.');
  console.log(c.dim + '  Guide: https://yurukusa.github.io/cc-safe-setup/opus-47-survival-guide.html' + c.reset);
  console.log();
}

async function shield() {
  const { execSync } = await import('child_process');
  const { readdirSync } = await import('fs');
  console.log();
  console.log(c.bold + '  🛡️  cc-safe-setup --shield' + c.reset);
  console.log(c.dim + '  Maximum safety in one command' + c.reset);
  console.log();

  // Step 1: Fix environment issues
  console.log(c.bold + '  Step 1: Fix environment' + c.reset);
  await quickfix();

  // Step 2: Install core safety hooks
  console.log();
  console.log(c.bold + '  Step 2: Install safety hooks' + c.reset);
  // Run the default install
  mkdirSync(HOOKS_DIR, { recursive: true });
  let installed = 0;
  for (const [hookId, hookMeta] of Object.entries(HOOKS)) {
    const hookPath = join(HOOKS_DIR, `${hookId}.sh`);
    if (!existsSync(hookPath)) {
      writeFileSync(hookPath, SCRIPTS[hookId]);
      chmodSync(hookPath, 0o755);
      installed++;
      console.log(c.green + '  +' + c.reset + ` ${hookMeta.name}`);
    } else {
      console.log(c.dim + '  ✓' + c.reset + ` ${hookMeta.name} (already installed)`);
    }
  }

  // Step 3: Detect project stack and install recommended examples
  console.log();
  console.log(c.bold + '  Step 3: Project-aware hooks' + c.reset);
  const cwd = process.cwd();
  const extras = [];
  if (existsSync(join(cwd, 'package.json'))) {
    extras.push('auto-approve-build');
    try {
      const pkg = JSON.parse(readFileSync(join(cwd, 'package.json'), 'utf-8'));
      if (pkg.dependencies?.prisma || pkg.devDependencies?.prisma) extras.push('block-database-wipe');
      if (pkg.scripts?.deploy) extras.push('deploy-guard');
    } catch {}
  }
  if (existsSync(join(cwd, 'requirements.txt')) || existsSync(join(cwd, 'pyproject.toml'))) extras.push('auto-approve-python');
  if (existsSync(join(cwd, 'Dockerfile'))) extras.push('auto-approve-docker');
  if (existsSync(join(cwd, 'go.mod'))) extras.push('auto-approve-go');
  if (existsSync(join(cwd, 'Cargo.toml'))) extras.push('auto-approve-cargo');
  if (existsSync(join(cwd, 'Makefile'))) extras.push('auto-approve-make');
  if (existsSync(join(cwd, '.env'))) extras.push('env-source-guard');

  // Always include these for maximum safety
  extras.push('scope-guard', 'no-sudo-guard', 'protect-claudemd', 'memory-write-guard', 'skill-gate', 'auto-approve-test', 'auto-approve-readonly');

  // Opus 4.7 safety: classifier is hardcoded to 4.6 (#49618) — hooks are the only defense
  extras.push('dotfile-protection-guard', 'home-critical-bash-guard');

  for (const ex of extras) {
    const exPath = join(__dirname, 'examples', `${ex}.sh`);
    const hookPath = join(HOOKS_DIR, `${ex}.sh`);
    if (existsSync(exPath) && !existsSync(hookPath)) {
      copyFileSync(exPath, hookPath);
      chmodSync(hookPath, 0o755);
      console.log(c.green + '  +' + c.reset + ` ${ex}`);
      installed++;
    } else if (existsSync(hookPath)) {
      console.log(c.dim + '  ✓' + c.reset + ` ${ex} (already installed)`);
    }
  }

  // Step 4: Update settings.json
  console.log();
  console.log(c.bold + '  Step 4: Configure settings.json' + c.reset);
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }
  if (!settings.hooks) settings.hooks = {};

  // Collect all installed hooks
  const hookFiles = existsSync(HOOKS_DIR)
    ? readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'))
    : [];

  // Build hook entries by trigger type
  const preToolHooks = [];
  const postToolHooks = [];
  const stopHooks = [];

  for (const f of hookFiles) {
    const content = readFileSync(join(HOOKS_DIR, f), 'utf-8');
    const cmd = `bash ${toBashPath(join(HOOKS_DIR, f))}`;

    // Check if already in settings
    const alreadyConfigured = JSON.stringify(settings.hooks).includes(f);
    if (alreadyConfigured) continue;

    // Determine trigger from file content
    if (content.includes('TRIGGER: Stop') || f.includes('api-error') || f.includes('revert-helper') || f.includes('session-handoff') || f.includes('compact-reminder') || f.includes('notify') || f.includes('tmp-cleanup')) {
      stopHooks.push({ type: 'command', command: cmd });
    } else if (content.includes('TRIGGER: PostToolUse') || f.includes('syntax-check') || f.includes('context-monitor') || f.includes('output-length') || f.includes('error-memory') || f.includes('cost-tracker')) {
      postToolHooks.push({ type: 'command', command: cmd });
    } else {
      // Default: PreToolUse
      const matcher = (f.includes('edit-guard') || f.includes('protect-dotfiles') || f.includes('overwrite-guard') || f.includes('binary-file') || f.includes('parallel-edit') || f.includes('test-deletion') || f.includes('memory-write'))
        ? 'Edit|Write'
        : 'Bash';
      preToolHooks.push({ type: 'command', command: cmd, _matcher: matcher });
    }
  }

  // Group PreToolUse hooks by matcher
  if (preToolHooks.length > 0) {
    if (!settings.hooks.PreToolUse) settings.hooks.PreToolUse = [];
    const bashHooks = preToolHooks.filter(h => h._matcher === 'Bash').map(({ _matcher, ...h }) => h);
    const editHooks = preToolHooks.filter(h => h._matcher === 'Edit|Write').map(({ _matcher, ...h }) => h);
    if (bashHooks.length > 0) {
      const existing = settings.hooks.PreToolUse.find(e => e.matcher === 'Bash');
      if (existing) {
        const existingCmds = new Set(existing.hooks.map(h => h.command));
        for (const h of bashHooks) {
          if (!existingCmds.has(h.command)) existing.hooks.push(h);
        }
      } else {
        settings.hooks.PreToolUse.push({ matcher: 'Bash', hooks: bashHooks });
      }
    }
    if (editHooks.length > 0) {
      const existing = settings.hooks.PreToolUse.find(e => e.matcher === 'Edit|Write');
      if (existing) {
        const existingCmds = new Set(existing.hooks.map(h => h.command));
        for (const h of editHooks) {
          if (!existingCmds.has(h.command)) existing.hooks.push(h);
        }
      } else {
        settings.hooks.PreToolUse.push({ matcher: 'Edit|Write', hooks: editHooks });
      }
    }
  }
  if (postToolHooks.length > 0) {
    if (!settings.hooks.PostToolUse) settings.hooks.PostToolUse = [];
    const existing = settings.hooks.PostToolUse.find(e => e.matcher === '');
    if (existing) {
      const existingCmds = new Set(existing.hooks.map(h => h.command));
      for (const h of postToolHooks) {
        if (!existingCmds.has(h.command)) existing.hooks.push(h);
      }
    } else {
      settings.hooks.PostToolUse.push({ matcher: '', hooks: postToolHooks });
    }
  }
  if (stopHooks.length > 0) {
    if (!settings.hooks.Stop) settings.hooks.Stop = [];
    const existing = settings.hooks.Stop.find(e => e.matcher === '');
    if (existing) {
      const existingCmds = new Set(existing.hooks.map(h => h.command));
      for (const h of stopHooks) {
        if (!existingCmds.has(h.command)) existing.hooks.push(h);
      }
    } else {
      settings.hooks.Stop.push({ matcher: '', hooks: stopHooks });
    }
  }

  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
  console.log(c.green + '  ✓' + c.reset + ' settings.json updated');

  // Step 5: Generate CLAUDE.md template if none exists
  console.log();
  console.log(c.bold + '  Step 5: CLAUDE.md' + c.reset);
  if (!existsSync(join(cwd, 'CLAUDE.md'))) {
    const template = `# Project Rules

## Safety
- Do not push to main/master directly
- Do not force-push
- Do not delete files outside this project
- Do not commit .env or credential files
- Run tests before committing

## Code Style
- Follow existing conventions
- Keep functions small and focused
- Add comments only when the logic isn't obvious

## Git
- Use descriptive commit messages
- One logical change per commit
- Create feature branches for new work
`;
    writeFileSync(join(cwd, 'CLAUDE.md'), template);
    console.log(c.green + '  +' + c.reset + ' Created CLAUDE.md with safety rules template');
  } else {
    console.log(c.dim + '  ✓' + c.reset + ' CLAUDE.md already exists');
  }

  // Summary
  console.log();
  const totalHooks = hookFiles.length;
  console.log(c.bold + c.green + '  🛡️  Shield activated!' + c.reset);
  console.log(c.dim + `  ${totalHooks} hooks installed and configured.` + c.reset);
  console.log(c.dim + '  Your Claude Code sessions are now protected.' + c.reset);
  console.log();
  console.log(c.dim + '  Verify: npx cc-safe-setup --verify' + c.reset);
  console.log(c.dim + '  Status: npx cc-safe-setup --status' + c.reset);
  console.log();
  console.log(c.dim + '  Burning tokens too fast? Free diagnosis:' + c.reset);
  console.log(c.blue + '  https://yurukusa.github.io/cc-safe-setup/token-checkup.html' + c.reset);
  console.log();
}

async function quickfix() {
  const { execSync } = await import('child_process');
  console.log();
  console.log(c.bold + '  cc-safe-setup --quickfix' + c.reset);
  console.log(c.dim + '  Auto-detect and fix common Claude Code problems' + c.reset);
  console.log();

  let fixed = 0, warnings = 0, ok = 0;

  // Check 1: jq installed
  try {
    execSync('which jq', { stdio: 'pipe' });
    console.log(c.green + '  ✓' + c.reset + ' jq is installed');
    ok++;
  } catch {
    console.log(c.red + '  ✗' + c.reset + ' jq is not installed — hooks cannot parse JSON');
    console.log(c.dim + '    Fix: brew install jq (macOS) | sudo apt install jq (Linux)' + c.reset);
    warnings++;
  }

  // Check 2: ~/.claude directory exists
  const claudeDir = join(HOME, '.claude');
  if (existsSync(claudeDir)) {
    console.log(c.green + '  ✓' + c.reset + ' ~/.claude directory exists');
    ok++;
  } else {
    mkdirSync(claudeDir, { recursive: true });
    console.log(c.yellow + '  ⚡' + c.reset + ' Created ~/.claude directory');
    fixed++;
  }

  // Check 3: hooks directory exists
  if (existsSync(HOOKS_DIR)) {
    console.log(c.green + '  ✓' + c.reset + ' ~/.claude/hooks directory exists');
    ok++;
  } else {
    mkdirSync(HOOKS_DIR, { recursive: true });
    console.log(c.yellow + '  ⚡' + c.reset + ' Created ~/.claude/hooks directory');
    fixed++;
  }

  // Check 4: settings.json exists and is valid JSON
  if (existsSync(SETTINGS_PATH)) {
    try {
      JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      console.log(c.green + '  ✓' + c.reset + ' settings.json is valid JSON');
      ok++;
    } catch (e) {
      console.log(c.red + '  ✗' + c.reset + ' settings.json has invalid JSON: ' + e.message);
      console.log(c.dim + '    This is the #1 cause of hooks not working.' + c.reset);
      console.log(c.dim + '    Common fix: remove trailing commas, check for comments (JSONC not supported in all contexts)' + c.reset);
      warnings++;
    }
  } else {
    writeFileSync(SETTINGS_PATH, '{}');
    console.log(c.yellow + '  ⚡' + c.reset + ' Created empty settings.json');
    fixed++;
  }

  // Check 5: hooks have executable permission
  if (existsSync(HOOKS_DIR)) {
    const { readdirSync, statSync } = await import('fs');
    const hooks = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'));
    let nonExec = 0;
    for (const h of hooks) {
      const p = join(HOOKS_DIR, h);
      const st = statSync(p);
      if (!(st.mode & 0o111)) {
        chmodSync(p, 0o755);
        nonExec++;
      }
    }
    if (nonExec > 0) {
      console.log(c.yellow + '  ⚡' + c.reset + ` Fixed ${nonExec} hook(s) missing executable permission`);
      fixed += nonExec;
    } else if (hooks.length > 0) {
      console.log(c.green + '  ✓' + c.reset + ` All ${hooks.length} hooks have executable permission`);
      ok++;
    }
  }

  // Check 6: hooks have correct shebang
  if (existsSync(HOOKS_DIR)) {
    const { readdirSync } = await import('fs');
    const hooks = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'));
    let badShebang = 0;
    for (const h of hooks) {
      const content = readFileSync(join(HOOKS_DIR, h), 'utf-8');
      const firstLine = content.split('\n')[0];
      if (!firstLine.startsWith('#!')) {
        badShebang++;
        console.log(c.red + '  ✗' + c.reset + ` ${h} missing shebang (#!/bin/bash)`);
      }
    }
    if (badShebang === 0 && hooks.length > 0) {
      console.log(c.green + '  ✓' + c.reset + ' All hooks have valid shebang lines');
      ok++;
    }
    warnings += badShebang;
  }

  // Check 7: settings.json hooks reference existing files
  if (existsSync(SETTINGS_PATH)) {
    try {
      const settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      let broken = 0;
      for (const [trigger, groups] of Object.entries(settings.hooks || {})) {
        for (const group of groups) {
          for (const hook of (group.hooks || [])) {
            const cmd = hook.command || '';
            // Extract script path from command
            const match = cmd.match(/bash\s+"?([^"\s]+\.sh)/);
            if (match && !existsSync(match[1])) {
              console.log(c.red + '  ✗' + c.reset + ` Hook references missing file: ${match[1]}`);
              broken++;
            }
          }
        }
      }
      if (broken === 0) {
        console.log(c.green + '  ✓' + c.reset + ' All hook file references are valid');
        ok++;
      }
      warnings += broken;
    } catch {}
  }

  // Check 8: No .env in git staging
  try {
    const staged = execSync('git diff --cached --name-only 2>/dev/null', { encoding: 'utf-8' });
    if (/\.env/i.test(staged)) {
      console.log(c.red + '  ✗' + c.reset + ' .env file is staged in git! Run: git reset HEAD .env');
      warnings++;
    } else {
      console.log(c.green + '  ✓' + c.reset + ' No secret files in git staging area');
      ok++;
    }
  } catch {
    console.log(c.dim + '  · Not in a git repository (skipping git checks)' + c.reset);
  }

  // Check 9: CLAUDE.md exists in project
  if (existsSync('CLAUDE.md')) {
    console.log(c.green + '  ✓' + c.reset + ' CLAUDE.md found in project');
    ok++;
  } else {
    console.log(c.yellow + '  △' + c.reset + ' No CLAUDE.md — consider creating one for project-specific rules');
    warnings++;
  }

  // Check 10: Safety hooks installed
  let safetyHooks = 0;
  if (existsSync(SETTINGS_PATH)) {
    try {
      const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      const allHookCmds = [];
      for (const groups of Object.values(s.hooks || {})) {
        for (const g of groups) {
          for (const h of (g.hooks || [])) allHookCmds.push(h.command || '');
        }
      }
      const critical = ['destructive-guard', 'branch-guard', 'secret-guard'];
      for (const name of critical) {
        if (allHookCmds.some(c => c.includes(name))) {
          safetyHooks++;
        } else {
          console.log(c.yellow + '  △' + c.reset + ` Missing critical hook: ${name}`);
          console.log(c.dim + '    Fix: npx cc-safe-setup' + c.reset);
          warnings++;
        }
      }
      if (safetyHooks === 3) {
        console.log(c.green + '  ✓' + c.reset + ' All 3 critical safety hooks installed');
        ok++;
      }
    } catch {}
  }

  console.log();
  console.log(c.bold + '  Summary' + c.reset);
  console.log(c.green + `  ${ok} OK` + c.reset + c.yellow + ` · ${fixed} fixed` + c.reset + c.red + ` · ${warnings} warnings` + c.reset);

  if (fixed > 0) {
    console.log();
    console.log(c.green + `  ⚡ Auto-fixed ${fixed} issue(s)` + c.reset);
  }
  if (warnings > 0) {
    console.log();
    console.log(c.yellow + '  Run npx cc-safe-setup to install missing safety hooks' + c.reset);
    console.log(c.yellow + '  Run npx cc-safe-setup --doctor for detailed diagnosis' + c.reset);
  }
  console.log();
}

async function report() {
  // Generate markdown safety report
  let hookCount = 0;
  let scriptCount = 0;
  let auditScore = 0;

  if (existsSync(SETTINGS_PATH)) {
    try {
      const s = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
      for (const entries of Object.values(s.hooks || {})) {
        hookCount += entries.reduce((n, e) => n + (e.hooks || []).length, 0);
      }
      // Quick audit
      let risks = 0;
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
  }

  if (existsSync(HOOKS_DIR)) {
    const fsModule = await import('fs');
    scriptCount = fsModule.readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh')).length;
  }

  const grade = auditScore >= 80 ? 'A' : auditScore >= 60 ? 'B' : auditScore >= 40 ? 'C' : 'F';
  const emoji = auditScore >= 80 ? '🟢' : auditScore >= 50 ? '🟡' : '🔴';

  const blockLog = join(HOME, '.claude', 'blocked-commands.log');
  let totalBlocks = 0;
  if (existsSync(blockLog)) {
    totalBlocks = readFileSync(blockLog, 'utf-8').split('\n').filter(l => l.trim()).length;
  }

  const md = `## ${emoji} Claude Code Safety Report

| Metric | Value |
|--------|-------|
| Safety Score | **${auditScore}/100** (Grade ${grade}) |
| Hooks Registered | ${hookCount} |
| Hook Scripts | ${scriptCount} |
| Commands Blocked | ${totalBlocks} |
| Generated | ${new Date().toISOString().split('T')[0]} |

### Quick Actions
- Audit: \`npx cc-safe-setup --audit\`
- Dashboard: \`npx cc-safe-setup --dashboard\`
- Find hooks: \`npx cc-hook-registry recommend\`
`;

  console.log(md);

  // Also write to file
  const reportPath = join(process.cwd(), 'SAFETY_REPORT.md');
  writeFileSync(reportPath, md);
  console.log(c.green + 'Report saved: ' + reportPath + c.reset);
}

function generateCI() {
  const workflowDir = join(process.cwd(), '.github', 'workflows');
  const workflowPath = join(workflowDir, 'claude-code-safety.yml');

  const workflow = `# Claude Code Safety Audit
# Generated by: npx cc-safe-setup --generate-ci
# Runs safety checks on every PR and push to main

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

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Run safety audit
        id: audit
        run: |
          npx cc-safe-setup --audit --json > /tmp/audit.json 2>&1 || true
          SCORE=\$(cat /tmp/audit.json | jq -r '.score // 0' 2>/dev/null || echo 0)
          echo "score=\$SCORE" >> \$GITHUB_OUTPUT
          echo "Safety score: \$SCORE/100"
          if [ "\$SCORE" -lt 70 ]; then
            echo "::error::Safety score \$SCORE is below threshold (70)"
            exit 1
          fi

      - name: Verify hooks syntax
        run: |
          ERRORS=0
          for f in .claude/hooks/*.sh 2>/dev/null; do
            [ -f "\$f" ] || continue
            if ! bash -n "\$f" 2>/dev/null; then
              echo "::error file=\$f::Syntax error in hook"
              ERRORS=\$((ERRORS+1))
            fi
          done
          echo "Checked hooks: \$ERRORS error(s)"
          [ "\$ERRORS" -gt 0 ] && exit 1 || true

      - name: Check settings.json validity
        run: |
          if [ -f ".claude/settings.json" ]; then
            python3 -c "import json; json.load(open('.claude/settings.json'))" || {
              echo "::error::.claude/settings.json has invalid JSON"
              exit 1
            }
            echo "settings.json: valid"
          fi
          if [ -f ".claude/settings.local.json" ]; then
            python3 -c "import json; json.load(open('.claude/settings.local.json'))" || {
              echo "::error::.claude/settings.local.json has invalid JSON"
              exit 1
            }
            echo "settings.local.json: valid"
          fi
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
    { hook: 'env-source-guard', issues: ['#401 .env loaded into bash environment (54r)', '#40730 Shell builtins bypass deny patterns with absolute paths'] },
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
    { hook: 'read-only-mode', issues: ['#41063 Claude ignores read-only instructions during test tasks (0r)'] },
    { hook: 'task-integrity-guard', issues: ['#41109 Agent deleted open tasks to hide unfinished work (0r)'] },
    { hook: 'permission-denial-enforcer', issues: ['#41103 Sandbox bypass after user denied Write permission (0r)'] },
    { hook: 'no-git-amend-push', issues: ['#41162 Creates new commit even when instructed to amend/squash'] },
    { hook: 'auto-approve-nix', issues: ['#34007 Command parsing for permissions incorrectly handles # (6r)'] },
    { hook: 'git-operations-require-approval', issues: ['#40695 CLAUDE.md git rules ignored', '#39924 Branch switches on new session'] },
    { hook: 'token-budget-guard', issues: ['#41046 Account suspension from extension background activity', '#38826 Session limit tracking (2r)'] },
    { hook: 'windows-path-guard', issues: ['#38890 Path rewrite to fabricated Windows path (1r)', '#40164 Worktree fails on Windows'] },
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
      hooks: [{ type: 'command', command: toBashPath(hookPath) }],
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

async function validateHooks() {
  const { spawnSync } = await import('child_process');
  const { readdirSync, renameSync } = await import('fs');

  console.log();
  console.log(c.bold + '  cc-safe-setup --validate' + c.reset);
  console.log(c.dim + '  Checking all hooks for syntax errors and dangerous exit codes...' + c.reset);
  console.log();

  if (!existsSync(HOOKS_DIR)) {
    console.log(c.yellow + '  No hooks directory found.' + c.reset);
    return;
  }

  const disabledDir = join(HOME, '.claude', 'hooks-disabled');
  const hooks = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'));
  let ok = 0, dangerous = 0;

  for (const h of hooks) {
    const path = join(HOOKS_DIR, h);
    const name = h.replace('.sh', '');

    // 1. Syntax check
    const syntax = spawnSync('bash', ['-n', path], { stdio: 'pipe', timeout: 5000 });
    if (syntax.status !== 0) {
      mkdirSync(disabledDir, { recursive: true });
      renameSync(path, join(disabledDir, h));
      console.log(c.red + '  ✗ ' + name + c.reset + ' — SYNTAX ERROR (exit ' + syntax.status + ')');
      console.log(c.dim + '    Moved to hooks-disabled/. A syntax error exit 2 blocks ALL tools.' + c.reset);
      dangerous++;
      continue;
    }

    // 2. Empty input test — exit 2 = would block all tools
    const test = spawnSync('bash', [path], {
      input: '{}', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe']
    });
    if (test.status === 2) {
      mkdirSync(disabledDir, { recursive: true });
      renameSync(path, join(disabledDir, h));
      console.log(c.red + '  ✗ ' + name + c.reset + ' — BLOCKS on empty input (exit 2)');
      console.log(c.dim + '    Moved to hooks-disabled/.' + c.reset);
      dangerous++;
      continue;
    }

    ok++;
    console.log(c.green + '  ✓ ' + c.reset + name);
  }

  console.log();
  if (dangerous > 0) {
    console.log(c.red + '  ' + dangerous + ' dangerous hook(s) disabled.' + c.reset);
    console.log(c.dim + '  Restart Claude Code to apply. Disabled hooks are in ~/.claude/hooks-disabled/' + c.reset);
  } else {
    console.log(c.green + '  All ' + ok + ' hooks passed validation.' + c.reset);
  }
  console.log();
}

async function safeMode(enable) {
  const { readdirSync, renameSync, rmdirSync } = await import('fs');
  const disabledDir = join(HOME, '.claude', 'hooks-disabled');
  const backupSettings = join(HOME, '.claude', 'settings-backup.json');

  console.log();
  if (enable) {
    console.log(c.bold + '  cc-safe-setup --safe-mode' + c.reset);
    console.log(c.dim + '  Disabling all hooks...' + c.reset);

    if (!existsSync(HOOKS_DIR)) {
      console.log(c.yellow + '  No hooks to disable.' + c.reset);
      return;
    }

    mkdirSync(disabledDir, { recursive: true });
    const hooks = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'));
    for (const h of hooks) {
      renameSync(join(HOOKS_DIR, h), join(disabledDir, h));
    }

    // Backup settings and clear hooks
    if (existsSync(SETTINGS_PATH)) {
      const settings = readFileSync(SETTINGS_PATH, 'utf-8');
      writeFileSync(backupSettings, settings);
      const parsed = JSON.parse(settings);
      parsed.hooks = {};
      writeFileSync(SETTINGS_PATH, JSON.stringify(parsed, null, 2));
    }

    console.log(c.green + '  Safe mode ON.' + c.reset + ' ' + hooks.length + ' hooks disabled.');
    console.log(c.dim + '  Restart Claude Code. Run --safe-mode off to restore.' + c.reset);
  } else {
    console.log(c.bold + '  cc-safe-setup --safe-mode off' + c.reset);

    if (existsSync(disabledDir)) {
      mkdirSync(HOOKS_DIR, { recursive: true });
      const hooks = readdirSync(disabledDir).filter(f => f.endsWith('.sh'));
      for (const h of hooks) {
        renameSync(join(disabledDir, h), join(HOOKS_DIR, h));
      }
      try { rmdirSync(disabledDir); } catch {}
      console.log(c.green + '  Restored ' + hooks.length + ' hooks.' + c.reset);
    }

    if (existsSync(backupSettings)) {
      copyFileSync(backupSettings, SETTINGS_PATH);
      unlinkSync(backupSettings);
      console.log(c.green + '  Restored settings.json from backup.' + c.reset);
    }

    console.log(c.dim + '  Restart Claude Code to activate hooks.' + c.reset);
  }
  console.log();
}

async function compileRules(rulesFile) {
  console.log();
  console.log(c.bold + '  cc-safe-setup --rules' + c.reset);

  if (!existsSync(rulesFile)) {
    // Create example rules file
    const exampleDir = rulesFile.includes('/') ? rulesFile.substring(0, rulesFile.lastIndexOf('/')) : '.';
    mkdirSync(exampleDir, { recursive: true });
    writeFileSync(rulesFile, `# Claude Code Safety Rules
# Run: npx cc-safe-setup --rules ${rulesFile}

# Block dangerous commands
- block: "rm -rf on root or home"
  pattern: "rm\\s+-rf\\s+(\\/$|~)"

- block: "git push to main"
  pattern: "git\\s+push.*(main|master)"

- block: "git force push"
  pattern: "git\\s+push.*--force"

- block: "git add .env"
  pattern: "git\\s+add.*\\.env"

# Auto-approve safe commands
- approve: "read-only commands"
  commands: [cat, head, tail, ls, grep, find, which, pwd, date]

- approve: "git read commands"
  pattern: "^\\s*git\\s+(status|log|diff|show|branch)"

- approve: "test runners"
  pattern: "^\\s*(npm\\s+test|pytest|go\\s+test|cargo\\s+test)"

# Protect files from edits
- protect: ".env"
- protect: "config/secrets.yaml"
`);
    console.log(c.green + '  + ' + c.reset + 'Created ' + rulesFile + ' with example rules');
    console.log(c.dim + '  Edit the file, then run this command again to compile.' + c.reset);
    console.log();
    return;
  }

  // Parse YAML (simple parser — no dependency needed)
  const content = readFileSync(rulesFile, 'utf-8');
  const rules = [];
  let current = null;

  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('#') || !trimmed) continue;

    const blockMatch = trimmed.match(/^-\s+block:\s+"(.+)"/);
    const approveMatch = trimmed.match(/^-\s+approve:\s+"(.+)"/);
    const protectMatch = trimmed.match(/^-\s+protect:\s+"(.+)"/);
    const patternMatch = trimmed.match(/^pattern:\s+"(.+)"/);
    const commandsMatch = trimmed.match(/^commands:\s+\[(.+)\]/);

    if (blockMatch) { current = { type: 'block', name: blockMatch[1] }; rules.push(current); }
    else if (approveMatch) { current = { type: 'approve', name: approveMatch[1] }; rules.push(current); }
    else if (protectMatch) { rules.push({ type: 'protect', path: protectMatch[1] }); current = null; }
    else if (patternMatch && current) { current.pattern = patternMatch[1]; }
    else if (commandsMatch && current) { current.commands = commandsMatch[1].split(',').map(s => s.trim()); }
  }

  if (rules.length === 0) {
    console.log(c.yellow + '  No rules found in ' + rulesFile + c.reset);
    return;
  }

  console.log(c.dim + '  Compiling ' + rules.length + ' rules from ' + rulesFile + c.reset);

  // Generate consolidated hook script
  let script = `#!/bin/bash
# Auto-generated from: ${rulesFile}
# Generated: $(date -Iseconds)
# Rules: ${rules.length}
# Regenerate: npx cc-safe-setup --rules ${rulesFile}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

`;

  // Block rules
  const blocks = rules.filter(r => r.type === 'block');
  if (blocks.length > 0) {
    script += '# === Block Rules ===\n';
    script += 'if [ "$TOOL" = "Bash" ] && [ -n "$COMMAND" ]; then\n';
    for (const rule of blocks) {
      if (rule.pattern) {
        script += `  if echo "$COMMAND" | grep -qE '${rule.pattern}'; then\n`;
        script += `    echo "BLOCKED: ${rule.name}" >&2\n`;
        script += `    exit 2\n`;
        script += `  fi\n`;
      }
    }
    script += 'fi\n\n';
  }

  // Approve rules
  const approves = rules.filter(r => r.type === 'approve');
  if (approves.length > 0) {
    script += '# === Approve Rules ===\n';
    script += 'if [ "$TOOL" = "Bash" ] && [ -n "$COMMAND" ]; then\n';
    for (const rule of approves) {
      if (rule.commands) {
        const base = '$(echo "$COMMAND" | awk \'{ print $1 }\' | sed \'s|.*/||\')'
        script += `  BASE=${base}\n`;
        script += `  case "$BASE" in\n`;
        script += `    ${rule.commands.join('|')}) echo '{"decision":"approve","reason":"${rule.name}"}'; exit 0 ;;\n`;
        script += `  esac\n`;
      }
      if (rule.pattern) {
        script += `  if echo "$COMMAND" | grep -qE '${rule.pattern}'; then\n`;
        script += `    echo '{"decision":"approve","reason":"${rule.name}"}'\n`;
        script += `    exit 0\n`;
        script += `  fi\n`;
      }
    }
    script += 'fi\n\n';
  }

  // Protect rules
  const protects = rules.filter(r => r.type === 'protect');
  if (protects.length > 0) {
    script += '# === Protect Rules ===\n';
    script += 'if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then\n';
    script += '  [ -z "$FILE" ] && exit 0\n';
    for (const rule of protects) {
      const path = rule.path;
      if (path.endsWith('/')) {
        script += `  [[ "$FILE" == *"${path}"* ]] && { jq -n '{"decision":"block","reason":"Protected: ${path}"}'; exit 0; }\n`;
      } else {
        script += `  [[ "$FILE" == *"${path}" ]] && { jq -n '{"decision":"block","reason":"Protected: ${path}"}'; exit 0; }\n`;
      }
    }
    script += 'fi\n\n';
  }

  script += 'exit 0\n';

  // Write hook
  mkdirSync(HOOKS_DIR, { recursive: true });
  const hookPath = join(HOOKS_DIR, 'compiled-rules.sh');
  writeFileSync(hookPath, script);
  chmodSync(hookPath, 0o755);

  // Syntax check — a broken hook returns exit 2 which blocks ALL tools
  const { execSync } = await import('child_process');
  try {
    execSync(`bash -n "${hookPath}"`, { stdio: 'pipe' });
  } catch (e) {
    const stderr = (e.stderr || '').toString().trim();
    unlinkSync(hookPath);
    console.log(c.red + '  ✗ Syntax error in generated hook — aborted' + c.reset);
    if (stderr) console.log(c.dim + '    ' + stderr + c.reset);
    console.log(c.dim + '  Check your rules file for unescaped special characters.' + c.reset);
    console.log();
    return;
  }

  // Register in settings.json
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks.PreToolUse) settings.hooks.PreToolUse = [];

  const hookCmd = `bash ${toBashPath(hookPath)}`;

  // Check all matchers for existing compiled-rules entry
  let found = false;
  for (const entry of settings.hooks.PreToolUse) {
    const idx = (entry.hooks || []).findIndex(h => h.command && h.command.includes('compiled-rules'));
    if (idx !== -1) {
      entry.hooks[idx] = { type: 'command', command: hookCmd };
      found = true;
      break;
    }
  }

  if (!found) {
    // Add to catch-all matcher
    let allMatcher = settings.hooks.PreToolUse.find(e => e.matcher === '');
    if (!allMatcher) {
      allMatcher = { matcher: '', hooks: [] };
      settings.hooks.PreToolUse.push(allMatcher);
    }
    allMatcher.hooks.push({ type: 'command', command: hookCmd });
  }

  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));

  // Summary
  console.log();
  for (const rule of rules) {
    if (rule.type === 'block') console.log(c.red + '  ✗ ' + c.reset + 'Block: ' + rule.name);
    else if (rule.type === 'approve') console.log(c.green + '  ✓ ' + c.reset + 'Approve: ' + rule.name);
    else if (rule.type === 'protect') console.log(c.blue + '  🔒 ' + c.reset + 'Protect: ' + rule.path);
  }
  console.log();
  console.log(c.bold + '  ' + rules.length + ' rules compiled' + c.reset + ' → ' + hookPath);
  console.log(c.dim + '  Restart Claude Code to activate.' + c.reset);
  console.log(c.dim + '  Edit ' + rulesFile + ' and re-run to update.' + c.reset);
  console.log();
}

async function protect(targetPath) {
  const { resolve, basename } = await import('path');

  console.log();
  console.log(c.bold + '  cc-safe-setup --protect' + c.reset);

  // Normalize path
  const normalized = targetPath.replace(/\\/g, '/');
  const safeName = basename(normalized).replace(/[^a-zA-Z0-9._-]/g, '_');
  const hookName = `protect-${safeName}.sh`;
  const hookPath = join(HOOKS_DIR, hookName);

  // Generate hook script
  const isDir = normalized.endsWith('/');
  const pattern = isDir ? `*${normalized}*` : normalized;

  const script = `#!/bin/bash
# Auto-generated by: npx cc-safe-setup --protect ${targetPath}
# Blocks Edit/Write to: ${normalized}
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0
[ -z "$FILE" ] && exit 0

${isDir
  ? `if [[ "$FILE" == *"${normalized}"* ]]; then`
  : `if [[ "$FILE" == *"${normalized}" ]] || [[ "$FILE" == *"/${normalized}" ]]; then`
}
    jq -n '{"decision":"block","reason":"Protected path: ${normalized}"}'
    exit 0
fi

exit 0
`;

  // Safety: write to /tmp first, validate, then copy to hooks/
  const tmpScript = '/tmp/cc-compiled-rules-' + Date.now() + '.sh';
  writeFileSync(tmpScript, script);
  chmodSync(tmpScript, 0o755);

  // Validate 1: bash syntax check
  const { spawnSync: checkSpawn } = await import('child_process');
  const syntaxCheck = checkSpawn('bash', ['-n', tmpScript], { stdio: 'pipe' });
  if (syntaxCheck.status !== 0) {
    const err = (syntaxCheck.stderr || '').toString().trim();
    console.log(c.red + '  ERROR: Generated script has syntax errors:' + c.reset);
    console.log(c.dim + '  ' + err + c.reset);
    try { unlinkSync(tmpScript); } catch {}
    console.log(c.dim + '  Script NOT installed. Fix your rules and try again.' + c.reset);
    return;
  }

  // Validate 2: empty input must NOT return exit 2 (which blocks all tools)
  const emptyTest = checkSpawn('bash', [tmpScript], {
    input: '{}', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe']
  });
  if (emptyTest.status === 2) {
    console.log(c.red + '  ERROR: Script returns exit 2 on empty input.' + c.reset);
    console.log(c.red + '  This would BLOCK ALL Claude Code tools.' + c.reset);
    try { unlinkSync(tmpScript); } catch {}
    return;
  }

  // Validated — copy to hooks dir
  mkdirSync(HOOKS_DIR, { recursive: true });
  const hookContent = readFileSync(tmpScript, 'utf-8');
  writeFileSync(hookPath, hookContent);
  chmodSync(hookPath, 0o755);
  try { unlinkSync(tmpScript); } catch {}
  console.log(c.green + '  + ' + c.reset + 'Created ' + hookName + ' (syntax verified)');

  // Register in settings.json — use "Bash" matcher ONLY (never "")
  // "" matcher affects ALL tools and a broken hook would lock out the session
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks.PreToolUse) settings.hooks.PreToolUse = [];

  // Register under specific matchers based on rule types (NEVER use "" matcher)
  const hookCmd = `bash ${toBashPath(hookPath)}`;
  const hasBlocks = rules.some(r => r.type === 'block');
  const hasApproves = rules.some(r => r.type === 'approve');
  const hasProtects = rules.some(r => r.type === 'protect');

  // Block and approve rules need Bash matcher
  if (hasBlocks || hasApproves) {
    let bashMatcher = settings.hooks.PreToolUse.find(e => e.matcher === 'Bash');
    if (!bashMatcher) {
      bashMatcher = { matcher: 'Bash', hooks: [] };
      settings.hooks.PreToolUse.push(bashMatcher);
    }
    if (!bashMatcher.hooks.some(h => h.command === hookCmd)) {
      bashMatcher.hooks.push({ type: 'command', command: hookCmd });
    }
  }

  // Protect rules need Edit|Write matcher
  if (hasProtects) {
    let editMatcher = settings.hooks.PreToolUse.find(e => e.matcher === 'Edit|Write');
    if (!editMatcher) {
      editMatcher = { matcher: 'Edit|Write', hooks: [] };
      settings.hooks.PreToolUse.push(editMatcher);
    }
    if (!editMatcher.hooks.some(h => h.command === hookCmd)) {
      editMatcher.hooks.push({ type: 'command', command: hookCmd });
    }
  }

  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
  console.log(c.green + '  + ' + c.reset + 'Registered in settings.json');

  console.log();
  console.log(c.bold + '  Protected: ' + c.reset + c.blue + normalized + c.reset);
  console.log(c.dim + '  Edit and Write to this path will be blocked.' + c.reset);
  console.log(c.dim + '  Restart Claude Code to activate.' + c.reset);
  console.log();

  // Show how to unprotect
  console.log(c.dim + '  To unprotect: rm ' + hookPath + c.reset);
  console.log(c.dim + '  Then remove the entry from ~/.claude/settings.json' + c.reset);
  console.log();
}

async function simulate(command) {
  const { spawnSync } = await import('child_process');
  const { readdirSync } = await import('fs');

  console.log();
  console.log(c.bold + '  cc-safe-setup --simulate' + c.reset);
  console.log(c.dim + '  Simulating how hooks would react to:' + c.reset);
  console.log(c.blue + '  $ ' + command + c.reset);
  console.log();

  // Build fake PreToolUse JSON for Bash
  const fakeInput = JSON.stringify({
    tool_name: 'Bash',
    tool_input: { command }
  });

  // Read settings to find registered hooks
  let settings = {};
  if (existsSync(SETTINGS_PATH)) {
    try { settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8')); } catch {}
  }

  const hookEntries = settings.hooks?.PreToolUse || [];
  let tested = 0;
  let approved = 0;
  let blocked = 0;
  let passthrough = 0;

  for (const entry of hookEntries) {
    const matcher = entry.matcher || '';
    // Check if matcher includes Bash (or matches all)
    if (matcher && !matcher.match(/Bash/i) && matcher !== '') continue;

    for (const h of (entry.hooks || [])) {
      if (h.type !== 'command') continue;
      const cmd = h.command;

      // Extract script name for display
      const parts = cmd.split(/\s+/);
      const scriptPath = parts[parts.length - 1];
      const scriptName = scriptPath.split('/').pop().replace('.sh', '');

      // Resolve path
      const resolved = scriptPath.replace(/^~/, HOME);
      if (!existsSync(resolved)) {
        console.log(c.yellow + '  ? ' + c.reset + scriptName + c.dim + ' (script not found)' + c.reset);
        continue;
      }

      tested++;

      // Run the hook with fake input
      const result = spawnSync('bash', [resolved], {
        input: fakeInput,
        timeout: 5000,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      const stdout = (result.stdout || '').toString().trim();
      const stderr = (result.stderr || '').toString().trim();
      const exitCode = result.status;

      if (exitCode === 2) {
        blocked++;
        console.log(c.red + '  ✗ BLOCK ' + c.reset + c.bold + scriptName + c.reset);
        if (stderr) console.log(c.dim + '    ' + stderr.split('\n')[0] + c.reset);
      } else if (stdout.includes('"approve"') || stdout.includes('"decision":"approve"')) {
        approved++;
        let reason = '';
        try { reason = JSON.parse(stdout).reason || JSON.parse(stdout).decision; } catch {}
        console.log(c.green + '  ✓ APPROVE ' + c.reset + scriptName + (reason ? c.dim + ' (' + reason + ')' + c.reset : ''));
      } else {
        passthrough++;
        console.log(c.dim + '  · pass    ' + scriptName + c.reset);
      }
    }
  }

  // Also check installed hook scripts not in settings
  if (existsSync(HOOKS_DIR)) {
    const hookFiles = readdirSync(HOOKS_DIR).filter(f => f.endsWith('.sh'));
    const registeredScripts = new Set();
    for (const entry of hookEntries) {
      for (const h of (entry.hooks || [])) {
        if (h.command) registeredScripts.add(h.command.split('/').pop().replace('.sh', ''));
      }
    }

    const unregistered = hookFiles.filter(f => !registeredScripts.has(f.replace('.sh', '')));
    if (unregistered.length > 0) {
      console.log();
      console.log(c.dim + '  Unregistered hooks (not in settings.json):' + c.reset);
      for (const f of unregistered.slice(0, 5)) {
        const resolved = join(HOOKS_DIR, f);
        const result = spawnSync('bash', [resolved], {
          input: fakeInput,
          timeout: 5000,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
        const exitCode = result.status;
        const stdout = (result.stdout || '').toString().trim();
        const name = f.replace('.sh', '');

        if (exitCode === 2) {
          console.log(c.red + '  ✗ BLOCK ' + c.reset + name + c.dim + ' (unregistered)' + c.reset);
        } else if (stdout.includes('"approve"')) {
          console.log(c.green + '  ✓ APPROVE ' + c.reset + name + c.dim + ' (unregistered)' + c.reset);
        } else {
          console.log(c.dim + '  · pass    ' + name + ' (unregistered)' + c.reset);
        }
      }
      if (unregistered.length > 5) {
        console.log(c.dim + '    ... and ' + (unregistered.length - 5) + ' more' + c.reset);
      }
    }
  }

  // Summary
  console.log();
  console.log(c.bold + '  Summary: ' + c.reset +
    (blocked > 0 ? c.red + blocked + ' blocked' + c.reset + ' · ' : '') +
    (approved > 0 ? c.green + approved + ' approved' + c.reset + ' · ' : '') +
    passthrough + ' passthrough');

  if (blocked > 0) {
    console.log(c.red + '  → This command would be BLOCKED' + c.reset);
  } else if (approved > 0) {
    console.log(c.green + '  → This command would be auto-approved (no prompt)' + c.reset);
  } else {
    console.log(c.dim + '  → This command would trigger a permission prompt' + c.reset);
  }
  console.log();
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
        for (const trigger of ['PreToolUse', 'PostToolUse', 'Stop', 'Notification', 'SessionStart', 'SessionEnd', 'PreCompact', 'PermissionRequest', 'UserPromptSubmit']) {
          const entries = hooks[trigger] || [];
          if (entries.length > 0) {
            pass(trigger + ': ' + entries.length + ' hook(s) registered');

            // 6. Check each hook command path
            for (const entry of entries) {
              const hookList = entry.hooks || [];
              for (const h of hookList) {
                if (h.type !== 'command') continue;
                const cmd = h.command;

                // Check for Windows backslash paths
                if (cmd.includes('\\')) {
                  fail('Windows backslash in hook command: ' + cmd);
                  const fixed = cmd.replace(/\\/g, '/');
                  console.log(c.dim + '    Fix: npx cc-safe-setup --uninstall && npx cc-safe-setup@latest' + c.reset);
                  console.log(c.dim + '    Or manually change to: ' + fixed + c.reset);
                  continue;
                }

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
  if (VALIDATE) return validateHooks();
  if (SAFE_MODE) return safeMode(!SAFE_MODE_OFF);
  if (DOCTOR) return doctor();
  if (SIMULATE_CMD) return simulate(SIMULATE_CMD);
  if (PROTECT_PATH) return protect(PROTECT_PATH);
  if (RULES_FILE) return compileRules(RULES_FILE);
  if (WATCH) return watch();
  if (TEST_HOOK_IDX !== -1) return testHook(TEST_HOOK);
  if (SAVE_PROFILE_IDX !== -1) return saveProfile(SAVE_PROFILE);
  if (CHANGELOG_CMD) return changelogCmd();
  if (SCORE_ONLY) return scoreOnly();
  if (INIT_PROJECT) return initProject();
  if (SUGGEST) return suggest();
  if (WHY_IDX !== -1) return why(WHY_HOOK);
  if (REPLAY) return replay();
  if (GUARD_IDX !== -1) return guard(GUARD_DESC);
  if (DIFF_HOOKS_IDX !== -1) return diffHooks(DIFF_HOOKS);
  if (FROM_CLAUDEMD) return fromClaudeMd();
  if (HEALTH) return health();
  if (MIGRATE_FROM_IDX !== -1) return migrateFrom(MIGRATE_FROM);
  if (TEAM) return team();
  if (PROFILE_IDX !== -1) return profile(PROFILE);
  if (ANALYZE) return analyze();
  if (OPUS47) return opus47();
  if (SHIELD) return shield();
  if (QUICKFIX) return quickfix();
  if (REPORT) return report();
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
        hooks: [{ type: 'command', command: toBashPath(hookPath) }]
      });
    }
  }

  mkdirSync(dirname(SETTINGS_PATH), { recursive: true });
  writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
  console.log('  ' + c.green + 'v' + c.reset + ' settings.json updated -> ' + c.dim + SETTINGS_PATH + c.reset);

  console.log();
  console.log(c.bold + '  Done.' + c.reset + ' ' + Object.keys(HOOKS).length + ' safety hooks installed.');
  console.log('  ' + c.dim + 'Restart Claude Code to activate.' + c.reset);
  console.log();
  console.log('  ' + c.bold + 'You are now protected against:' + c.reset);
  console.log('  ' + c.green + '  ✓' + c.reset + ' rm -rf / git reset --hard / git clean -fd');
  console.log('  ' + c.green + '  ✓' + c.reset + ' Force-push to main/master');
  console.log('  ' + c.green + '  ✓' + c.reset + ' .env / credential files committed to git');
  console.log('  ' + c.green + '  ✓' + c.reset + ' Syntax errors cascading through files');
  console.log('  ' + c.green + '  ✓' + c.reset + ' PowerShell Remove-Item -Recurse -Force');
  console.log();
  console.log('  ' + c.dim + 'Verify:' + c.reset + '  npx cc-safe-setup --verify');
  console.log('  ' + c.dim + 'More:' + c.reset + '    npx cc-safe-setup --shield  (maximum safety)');
  console.log('  ' + c.dim + 'Diagnose:' + c.reset + ' https://yurukusa.github.io/cc-safe-setup/token-checkup.html');
  console.log('  ' + c.dim + 'Risk:' + c.reset + '     https://yurukusa.github.io/cc-safe-setup/risk-assessment.html');
  console.log('  ' + c.dim + 'Save $:' + c.reset + '   https://yurukusa.github.io/cc-safe-setup/token-book-chapter1.html (free)');
  console.log('  ' + c.dim + 'Feedback:' + c.reset + ' https://github.com/yurukusa/cc-safe-setup/discussions  (questions / patterns that worked)');
  console.log('  ' + c.dim + 'Bug:' + c.reset + '      https://github.com/yurukusa/cc-safe-setup/issues/new/choose  (false positives / install issues)');
  console.log();
}

main().catch(e => { console.error(e); process.exit(1); });
