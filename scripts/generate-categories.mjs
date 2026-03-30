#!/usr/bin/env node
/**
 * generate-categories.mjs
 *
 * Scans examples/*.sh to generate the CATEGORIES object for index.mjs --examples.
 *
 * Why: The manual CATEGORIES list falls behind (147 of 629 hooks registered).
 * This script auto-generates from the actual files so --examples always shows all hooks.
 *
 * Usage:
 *   node scripts/generate-categories.mjs          # preview JSON
 *   node scripts/generate-categories.mjs --apply   # update index.mjs in-place
 */

import { readdirSync, readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const EXAMPLES_DIR = join(ROOT, 'examples');
const INDEX_PATH = join(ROOT, 'index.mjs');

// ─── Category rules ───
// Order matters: first match wins. Patterns are tested against the filename (without .sh).
const CATEGORY_RULES = [
  // Auto-Approve / Permissions (must be first — specific prefixes)
  { pattern: /^auto-approve-/, category: 'Auto-Approve' },
  { pattern: /^allow-/, category: 'Auto-Approve' },
  { pattern: /^permission-/, category: 'Auto-Approve' },
  { pattern: /^edit-always-allow|^classifier-fallback-allow|^webfetch-domain-allow/, category: 'Auto-Approve' },

  // Recovery / Session State
  { pattern: /checkpoint|snapshot|backup|restore|recover|rollback|revert|stash-before|session-handoff|recycle-bin|session-state-saver|session-resume|session-summary|pre-compact-knowledge|pre-compact-transcript|file-change-undo|context-compact-advisor/, category: 'Recovery' },

  // Monitoring / Observability
  { pattern: /tracker|counter|monitor|logger|log$|budget-alert|health-monitor|watchdog|quota|usage-cache|token-counter|token-usage|cost-tracker|daily-usage|session-end-logger|session-error-rate|cross-session-error|tool-file-logger|file-change-monitor|file-change-tracker|read-audit|tool-call-rate-limiter|mcp-tool-audit/, category: 'Monitoring' },

  // Quality / Linting / Code Standards
  { pattern: /^enforce-|^require-|lint-on-edit|^branch-name|^commit-message|^commit-quality|^commit-scope|^pr-description|^no-console|^no-eval|^no-wildcard|^no-todo-ship|^test-coverage|^ci-skip|^debug-leftover|^typescript-strict|^sensitive-regex|^git-author|^git-blame|^import-cycle|^env-drift|^package-script|^lockfile|^git-lfs|^python-ruff|^typescript-lint|^fact-check|^conflict-marker|^test-deletion|^license-check|^changelog-reminder|^branch-naming|^verify-before-commit|^prefer-const|^prefer-optional|^prefer-builtin|^prefer-dedicated|^max-function-length|^max-import-count|^dockerfile-lint|^dotenv-example|^dotenv-validate|^dotenv-watch|^env-naming|^readme-update|^write-test-ratio|^edit-counter-test|^test-after-edit|^test-before-commit|^test-before-push|^push-requires-test|^git-message-length|^console-log-count|^go-vet|^java-compile|^swift-build|^dotnet-build|^rust-clippy|^edit-old-string-validator/, category: 'Quality' },

  // UX / Developer Experience
  { pattern: /^prompt-length|^prompt-injection-detect|^auto-answer|^notify-|^tmp-cleanup|^hook-debug|^loop-detector|^diff-size|^dependency-audit|^binary-file|^stale-branch|^read-before-edit|^compact-reminder|^context-snapshot|^post-compact-restore|^reinject-claudemd|^output-length|^error-memory|^parallel-edit|^large-read|^max-session|^dangling-process|^encoding-guard|^disk-space|^rate-limit-guard|^stale-env|^node-version|^max-file-count|^file-size-limit|^token-budget|^long-session|^cwd-reminder|^virtual-cwd|^hook-stdout|^fish-shell|^system-message|^plan-mode|^plan-repo|^skill-gate|^git-show-flag|^consecutive-error|^consecutive-failure|^session-time-limit|^temp-file-cleanup|^plugin-process|^context-threshold|^five-hundred|^session-budget/, category: 'UX' },

  // Subagent / MCP Controls
  { pattern: /^subagent-|^mcp-|^max-concurrent-agents|^max-subagent/, category: 'Agent Controls' },

  // Safety Guards (broad catch — must be last among specifics)
  { pattern: /guard|block|protect|^no-|^strip-|^scope-|^allowlist|^strict-allowlist|^secret|^staged-secret|^output-credential|^output-secret|^network|^path-traversal|^timeout|^session-drift|^post-compact-safety|^read-budget|^hook-permission|^response-budget|^deploy|^env-var-check|^env-source|^overwrite|^write-overwrite|^memory-write|^worktree|^docker-prune|^pip-venv|^variable-expansion|^bash-trace|^work-hours|^case-sensitive|^compound-command|^uncommitted|^rm-safety|^absolute-rule|^claudemd-enforcer|^read-all-files|^concurrent-edit|^git-operations-require|^core-file-protect|^api-overload|^api-rate-limit|^api-retry|^npm-script-injection|^dependency-version|^package-lock-frozen|^migration-safety|^git-merge-conflict|^git-index-lock|^bash-domain-allowlist|^claude-cache-gc|^deployment-verify|^max-file-delete/, category: 'Safety Guards' },
];

// ─── Description extraction ───
function extractDescription(filepath, filename) {
  const content = readFileSync(filepath, 'utf8');
  const lines = content.split('\n');

  // Strategy 1: "# filename — description" on line 2 or nearby
  for (let i = 1; i < Math.min(lines.length, 8); i++) {
    const m = lines[i].match(/^#\s*\S+\.sh\s*[—–-]+\s*(.+)/);
    if (m) return m[1].trim();
  }

  // Strategy 2: "# ===...=== \n # filename — description"
  for (let i = 1; i < Math.min(lines.length, 10); i++) {
    const m = lines[i].match(/^#\s*\S+\.sh\s*[—–-]+\s*(.+)/);
    if (m) return m[1].trim();
  }

  // Strategy 3: First non-empty, non-shebang, non-separator comment line
  for (let i = 1; i < Math.min(lines.length, 15); i++) {
    const line = lines[i];
    if (!line.startsWith('#')) continue;
    const text = line.replace(/^#\s*/, '').trim();
    if (!text) continue;
    if (/^=+$/.test(text)) continue;  // separator line
    if (/^TRIGGER:/i.test(text)) continue;
    if (/^MATCHER:/i.test(text)) continue;
    if (/^Usage:/i.test(text)) continue;
    if (/^\{/.test(text)) continue; // JSON
    if (/^"hooks"/.test(text)) continue;
    // If it looks like "PURPOSE:" grab what follows
    const purposeMatch = text.match(/^PURPOSE:\s*(.+)/i);
    if (purposeMatch) return purposeMatch[1].trim();
    // Skip the filename echo
    if (text.startsWith(filename)) continue;
    // Use this line
    return text;
  }

  // Fallback: derive from filename
  const base = filename.replace('.sh', '');
  return base.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

// ─── Categorize ───
function categorize(filename) {
  const base = filename.replace('.sh', '');
  for (const rule of CATEGORY_RULES) {
    if (rule.pattern.test(base)) return rule.category;
  }
  // Fallback heuristics
  if (base.includes('warn') || base.includes('check') || base.includes('detect') || base.includes('verify')) return 'Quality';
  if (base.includes('auto-') || base.includes('approve')) return 'Auto-Approve';
  // Default
  return 'Other';
}

// ─── Main ───
const files = readdirSync(EXAMPLES_DIR)
  .filter(f => f.endsWith('.sh'))
  .sort();

const categories = {};

for (const file of files) {
  const cat = categorize(file);
  const desc = extractDescription(join(EXAMPLES_DIR, file), file);
  if (!categories[cat]) categories[cat] = {};
  categories[cat][file] = desc;
}

// Desired category order
const ORDER = ['Safety Guards', 'Auto-Approve', 'Quality', 'Monitoring', 'Recovery', 'UX', 'Agent Controls', 'Other'];
const ordered = {};
for (const cat of ORDER) {
  if (categories[cat] && Object.keys(categories[cat]).length > 0) {
    ordered[cat] = categories[cat];
  }
}
// Add any categories not in ORDER
for (const cat of Object.keys(categories)) {
  if (!ordered[cat]) ordered[cat] = categories[cat];
}

// ─── Generate code ───
function generateCode(cats) {
  let code = '  const CATEGORIES = {\n';
  const catEntries = Object.entries(cats);
  for (let ci = 0; ci < catEntries.length; ci++) {
    const [cat, hooks] = catEntries[ci];
    code += `    '${cat}': {\n`;
    const hookEntries = Object.entries(hooks);
    for (let hi = 0; hi < hookEntries.length; hi++) {
      const [file, desc] = hookEntries[hi];
      // Escape single quotes in description
      const safeDesc = desc.replace(/'/g, "\\'");
      code += `      '${file}': '${safeDesc}',\n`;
    }
    code += '    },\n';
  }
  code += '  };';
  return code;
}

const newCode = generateCode(ordered);

// Stats
const totalHooks = Object.values(ordered).reduce((s, c) => s + Object.keys(c).length, 0);
console.log(`Categories: ${Object.keys(ordered).length}`);
for (const [cat, hooks] of Object.entries(ordered)) {
  console.log(`  ${cat}: ${Object.keys(hooks).length} hooks`);
}
console.log(`Total: ${totalHooks} hooks from ${files.length} .sh files`);

if (process.argv.includes('--apply')) {
  const src = readFileSync(INDEX_PATH, 'utf8');

  // Match the CATEGORIES block: "  const CATEGORIES = {" ... "  };"
  const startMarker = '  const CATEGORIES = {';
  const startIdx = src.indexOf(startMarker);
  if (startIdx === -1) {
    console.error('ERROR: Could not find "const CATEGORIES = {" in index.mjs');
    process.exit(1);
  }

  // Find the closing "};" that matches - it's "  };" at the same indentation
  let endIdx = -1;
  let depth = 0;
  for (let i = startIdx + startMarker.length; i < src.length; i++) {
    if (src[i] === '{') depth++;
    if (src[i] === '}') {
      if (depth === 0) {
        // Check this is "  };"
        endIdx = i;
        // Include the semicolon
        if (src[i + 1] === ';') endIdx = i + 1;
        break;
      }
      depth--;
    }
  }

  if (endIdx === -1) {
    console.error('ERROR: Could not find closing of CATEGORIES block');
    process.exit(1);
  }

  const before = src.substring(0, startIdx);
  const after = src.substring(endIdx + 1);
  const updated = before + newCode + after;

  writeFileSync(INDEX_PATH, updated, 'utf8');
  console.log(`\nUpdated index.mjs: ${totalHooks} hooks in CATEGORIES`);
} else {
  console.log('\nRun with --apply to update index.mjs');
}
