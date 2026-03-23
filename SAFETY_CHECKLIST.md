# Claude Code Safety Checklist

Use this checklist before running Claude Code autonomously. Copy to your project or CLAUDE.md.

## Before First Session

- [ ] Install safety hooks: `npx cc-safe-setup`
- [ ] Run safety audit: `npx cc-safe-setup --audit` (target: score ≥ 80)
- [ ] Create CLAUDE.md with project-specific rules
- [ ] Verify .env files are in .gitignore
- [ ] Ensure git remote is set (so work can be recovered)

## Before Autonomous Mode

- [ ] Create backup branch: `git checkout -b backup/before-autonomous-$(date +%Y%m%d)`
- [ ] Commit all current work
- [ ] Verify destructive-guard is blocking: `npx cc-safe-setup --verify`
- [ ] Check branch-guard protects main/master
- [ ] If using database: install `block-database-wipe`
- [ ] If sensitive configs: install `protect-dotfiles`

## During Session

- [ ] Monitor context usage (context-monitor hook warns at 40%)
- [ ] Check blocked-commands.log periodically
- [ ] Verify commits have meaningful messages

## After Session

- [ ] Review git log for unexpected changes
- [ ] Run test suite to catch regressions
- [ ] Check if any .env files were modified
- [ ] Review blocked-commands.log for patterns: `npx cc-safe-setup --learn`

## Team Setup

- [ ] Add GitHub Action to CI: `uses: yurukusa/cc-safe-setup@main`
- [ ] Set threshold ≥ 70 for CI safety gate
- [ ] Share `.safety-net.json` or hooks config across team
- [ ] Document which hooks are required vs optional

## Quick Reference

| Risk | Prevention | Install |
|------|-----------|---------|
| `rm -rf /` | destructive-guard | `npx cc-safe-setup` |
| Push to main | branch-guard | `npx cc-safe-setup` |
| .env committed | secret-guard | `npx cc-safe-setup` |
| Database wiped | block-database-wipe | `--install-example block-database-wipe` |
| Dotfiles modified | protect-dotfiles | `--install-example protect-dotfiles` |
| Deploy without commit | deploy-guard | `--install-example deploy-guard` |
| Commit without tests | verify-before-commit | `--install-example verify-before-commit` |
| Session crash data loss | session-checkpoint | `--install-example session-checkpoint` |
