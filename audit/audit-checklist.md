# Claude Code Safety Audit Checklist

**50-point assessment for Claude Code environments.**
Complete this checklist to identify gaps in your safety configuration.
Score: each ✅ = 1 point. Target: 40+ for production use, 45+ for autonomous operation.

---

## Hooks (15 points)

Your first line of defense. Hooks intercept dangerous operations before they execute.

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | **Destructive command guard** — `rm -rf`, `git reset --hard`, `git clean -fd` are blocked | ☐ | |
| 2 | **Force push guard** — `git push --force` (and `--force-with-lease` on shared branches) is blocked | ☐ | |
| 3 | **Main branch push guard** — direct `git push` to main/master is blocked | ☐ | |
| 4 | **Sensitive file write guard** — writes to `.env`, credentials, key files are blocked | ☐ | |
| 5 | **Sensitive file edit guard** — edits to `.env`, credentials, key files are blocked (separate from Write) | ☐ | |
| 6 | **Package publish guard** — `npm publish`, `docker push`, etc. require human execution | ☐ | |
| 7 | **External API write guard** — outbound POST/PUT/DELETE requests are blocked or flagged | ☐ | |
| 8 | **SQL destruction guard** — `DROP TABLE`, `TRUNCATE`, unscoped `DELETE` are blocked | ☐ | |
| 9 | **Sudo guard** — `sudo` commands are blocked | ☐ | |
| 10 | **Permission change guard** — `chmod 777`, recursive `chmod`/`chown` are blocked | ☐ | |
| 11 | **Infrastructure file warning** — edits to Dockerfile, CI config, package.json trigger a warning | ☐ | |
| 12 | **Long command warning** — commands over 500 characters are flagged for review | ☐ | |
| 13 | **Hooks are tested** — you have verified each hook actually blocks by triggering it intentionally | ☐ | |
| 14 | **Hooks survive updates** — hooks are in version control or backed up outside `~/.claude/` | ☐ | |
| 15 | **Hook failure mode is safe** — if a hook script crashes, the command is blocked (exit 2), not allowed | ☐ | |

## Git Protection (10 points)

Git is both your safety net and your biggest risk vector.

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 16 | **Work happens on feature branches** — CLAUDE.md explicitly requires branching | ☐ | |
| 17 | **Commits have meaningful messages** — convention is documented (conventional commits, etc.) | ☐ | |
| 18 | **Pre-commit tests** — tests run before or immediately after each commit | ☐ | |
| 19 | **Backup branch before risky changes** — documented procedure for `git checkout -b backup/...` | ☐ | |
| 20 | **No orphaned branches** — process exists to clean up merged/stale branches | ☐ | |
| 21 | **`.gitignore` covers sensitive files** — `.env`, `*.pem`, `*.key`, `credentials.*` are listed | ☐ | |
| 22 | **`.gitignore` covers generated files** — `node_modules/`, `__pycache__/`, `dist/`, build artifacts are listed | ☐ | |
| 23 | **Git hooks complement Claude hooks** — pre-commit and pre-push hooks exist at the repository level | ☐ | |
| 24 | **Rebase/merge strategy is documented** — team knows whether to rebase or merge | ☐ | |
| 25 | **Force push is disabled server-side** — branch protection rules on GitHub/GitLab block force push to main | ☐ | |

## Credentials & Secrets (8 points)

One leaked secret can cost more than your entire project.

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 26 | **No hardcoded secrets in source** — grep your codebase for API keys, passwords, tokens | ☐ | |
| 27 | **Environment variables for all secrets** — documented in `.env.example` (without values) | ☐ | |
| 28 | **`.env` is gitignored** — confirmed in `.gitignore`, verified with `git status` | ☐ | |
| 29 | **Secret scanning is active** — GitHub secret scanning, `gitleaks`, or equivalent is enabled | ☐ | |
| 30 | **API tokens have minimum scope** — each token has only the permissions it needs | ☐ | |
| 31 | **Token expiration is set** — tokens expire and have a documented renewal process | ☐ | |
| 32 | **Service account keys are secured** — GCP/AWS/Azure keys are not in the project directory | ☐ | |
| 33 | **Git history is clean** — no secrets were ever committed (check with `git log -p -S "password"`) | ☐ | |

## Token & Cost Management (7 points)

Uncontrolled token usage can drain your budget overnight.

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 34 | **CLAUDE.md is under 500 lines** — bloated instructions waste tokens on every message | ☐ | |
| 35 | **No redundant context** — instructions are not duplicated across CLAUDE.md, settings, and hooks | ☐ | |
| 36 | **Large file reads are targeted** — `Read` calls use `offset` and `limit` for files over 200 lines | ☐ | |
| 37 | **Subagents are used for exploration** — research tasks are offloaded, not done in the main context | ☐ | |
| 38 | **Session cost is monitored** — you check `/cost` or equivalent regularly | ☐ | |
| 39 | **Spending limits are configured** — Anthropic Console or API usage limits are set | ☐ | |
| 40 | **Compact triggers are understood** — you know when context compaction happens and what it loses | ☐ | |

## Autonomous Operation (5 points)

Running Claude Code unattended requires extra safeguards.

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 41 | **All external writes are blocked** — `curl POST`, `gh issue create`, API calls are hook-blocked | ☐ | |
| 42 | **Configuration files are protected** — CLAUDE.md and settings.json cannot be self-modified | ☐ | |
| 43 | **Remote access is blocked** — `ssh`, `scp`, `rsync` to remote hosts are hook-blocked | ☐ | |
| 44 | **Service management is blocked** — `systemctl`, `service` commands are hook-blocked | ☐ | |
| 45 | **Error escalation path exists** — after N failures, the agent logs the issue and moves on (not infinite retry) | ☐ | |

## Team & Multi-Agent (5 points)

When multiple people or agents share a codebase, coordination failures become the primary risk.

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 46 | **Shared hooks in version control** — `.claude/settings.json` is committed and reviewed via PR | ☐ | |
| 47 | **CLAUDE.md changes require review** — project instructions are not unilaterally changed | ☐ | |
| 48 | **File lock awareness** — multi-agent setups have a mechanism to detect concurrent edits | ☐ | |
| 49 | **PR review is mandatory** — branch protection rules enforce at least one approving review | ☐ | |
| 50 | **Personal overrides don't weaken safety** — `.claude/settings.local.json` cannot disable project-level hooks | ☐ | |

---

## Scoring Guide

| Score | Rating | Recommendation |
|-------|--------|----------------|
| **45–50** | Excellent | Ready for autonomous and team use |
| **40–44** | Good | Safe for supervised use. Address gaps before going autonomous |
| **30–39** | Fair | Significant gaps. Do not run unattended |
| **20–29** | Poor | High risk of data loss or secret exposure. Fix immediately |
| **< 20** | Critical | Stop using Claude Code on this project until remediated |

## How to Use This Checklist

1. **Initial audit:** Go through all 50 items. Mark each ✅ or ❌
2. **Prioritize fixes:** Credentials & Hooks failures are highest priority
3. **Re-audit monthly:** New dependencies, team members, and workflows introduce new risks
4. **After incidents:** Re-run the relevant section to find the root cause

## Quick Verification Commands

```bash
# Check if .env is gitignored
git check-ignore .env; echo "exit $?"   # 0 = ignored (pass), 1 = NOT ignored (fail)

# Search for hardcoded secrets in source
# One --include per extension: a braced list is passed to grep literally and
# matches nothing, so the command returns a reassuring zero. Verified 2026-08-27.
grep -rn "password\|api_key\|secret\|token" \
  --include="*.js" --include="*.ts" --include="*.py" --include="*.go" --include="*.rb" . \
  | grep -v node_modules | grep -v test

# Verify hooks are loaded
# `claude --print-settings` is not a flag the CLI has (checked 2026-08-27 against
# 2.1.246; it exits 1 and prints usage). Read the three settings files instead:
for f in ~/.claude/settings.json .claude/settings.json .claude/settings.local.json; do
  [ -f "$f" ] && echo "$f: $(jq '[.hooks[]?[]?] | length' "$f")"
done

# Check for secrets in git history
# A git pathspec does not brace-expand either. List the globs. Verified 2026-08-27.
git log -p --all -S "API_KEY" --diff-filter=A -- "*.js" "*.ts" "*.py" "*.go" "*.rb"

# Verify branch protection (GitHub)
# Run inside the repository; gh fills in {owner}/{repo} from the remote.
# "Branch not protected" is a failing check 25/49, not an error.
gh api repos/{owner}/{repo}/branches/main/protection | jq '.required_pull_request_reviews'
```

---

*Part of [Claude Code Safety Mastery](https://yurukusa.gumroad.com/l/pcctdn). Use this checklist to protect your projects, your secrets, and your budget.*
