#!/usr/bin/env -S npx tsx
/**
 * destructive-guard.ts — Claude Code PreToolUse hook in TypeScript
 *
 * Blocks rm -rf /, git reset --hard, git clean -fd, and similar
 * destructive commands. Exit code 2 = block, 0 = allow.
 *
 * Run with: npx tsx destructive-guard.ts
 * Or compile: npx tsc destructive-guard.ts && node destructive-guard.js
 */

interface HookInput {
  tool_input: {
    command?: string;
  };
}

const DANGEROUS_PATTERNS: RegExp[] = [
  /\brm\s+.*-rf\s+(\/|~\/?\s*$|\.\.\/)/,
  /\bgit\s+reset\s+--hard/,
  /\bgit\s+clean\s+-[a-zA-Z]*f/,
  /\bgit\s+checkout\s+--force/,
  /\bchmod\s+(-R\s+)?777\s+\//,
  /\bfind\s+\/\s+-delete/,
  /Remove-Item.*-Recurse.*-Force/,
  /--no-preserve-root/,
  /\bsudo\s+mkfs\b/,
];

async function main(): Promise<void> {
  let data = '';
  for await (const chunk of process.stdin) {
    data += chunk;
  }

  let input: HookInput;
  try {
    input = JSON.parse(data);
  } catch {
    process.exit(0); // Don't block on parse error
  }

  const cmd = input.tool_input?.command;
  if (!cmd) {
    process.exit(0);
  }

  // Skip echo/printf context
  const trimmed = cmd.trimStart().toLowerCase();
  if (trimmed.startsWith('echo ') || trimmed.startsWith('printf ')) {
    process.exit(0);
  }

  for (const pattern of DANGEROUS_PATTERNS) {
    if (pattern.test(cmd)) {
      process.stderr.write(`BLOCKED: Dangerous command detected\nCommand: ${cmd}\n`);
      process.exit(2);
    }
  }

  process.exit(0);
}

main();
