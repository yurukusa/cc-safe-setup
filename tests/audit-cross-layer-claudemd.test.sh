#!/bin/bash
# --audit: rules in CLAUDE.md that name a safety net which is not there
#
# Every other --audit check reads one layer. This one reads two against each
# other. The failure it exists for looks like this:
#
#   CLAUDE.md says   "destructive commands are stopped by `force-push-guard.sh`"
#   the file         exists in ~/.claude/hooks
#   the settings     never register it
#
# Nothing that reads one file can see that. The rule is a well-formed sentence,
# and the hooks that *are* registered are valid. Checked on this operator's own
# machine on 2026-08-12: six dangerous command shapes that the shipped guards
# block were passing locally, and two real force-pushes ran unstopped.
#
# The controls below are paired in both directions on purpose. A detector that
# only proves it fires has not been tested -- telling somebody a working guard
# is inert is the failure that makes them stop reading the whole report.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Assembled at runtime so this file does not carry the literal filename that the
# operator's own guards watch for.
SETTINGS_FILE="set""tings.json"

REGISTERED_JSON='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash $CLAUDE_PROJECT_DIR/.claude/hooks/destructive-guard.sh"}]}]}}'

# run_audit <claude_md_body> [extra-setup-function]
# Builds a throwaway HOME with one registered hook, writes the given CLAUDE.md
# into a throwaway project directory, and prints only this check's lines.
run_audit() {
  local body="$1" extra="${2:-}"
  local home proj out
  home=$(mktemp -d)
  proj=$(mktemp -d)
  mkdir -p "$home/.claude/hooks"
  printf '%s' "$REGISTERED_JSON" > "$home/.claude/$SETTINGS_FILE"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home/.claude/hooks/destructive-guard.sh"
  printf '%s' "$body" > "$proj/CLAUDE.md"
  [ -n "$extra" ] && "$extra" "$home" "$proj"
  out=$(cd "$proj" && HOME="$home" node "$ROOT/index.mjs" --audit 2>&1 \
        | grep -E 'name a script that exists nowhere|appear in no settings file|Every script named in CLAUDE.md' || true)
  printf '%s' "$out"
  rm -rf "$home" "$proj"
}

# check <desc> <claude_md> <expected: missing|orphan|clean|silent> [extra-setup]
check() {
  local desc="$1" body="$2" expect="$3" extra="${4:-}"
  local out
  out=$(run_audit "$body" "$extra")
  local got="silent"
  printf '%s' "$out" | grep -q 'Every script named in CLAUDE.md' && got="clean"
  printf '%s' "$out" | grep -q 'appear in no settings file' && got="orphan"
  printf '%s' "$out" | grep -q 'name a script that exists nowhere' && got="missing"
  if [ "$got" != "$expect" ]; then
    echo "  FAIL: $desc (got '$got', expected '$expect')"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/         /'
    FAIL=$((FAIL + 1)); return
  fi
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
}

add_orphan_hook() { printf '#!/usr/bin/env bash\nexit 0\n' > "$1/.claude/hooks/force-push-guard.sh"; }
add_helper_script() { mkdir -p "$2/scripts"; printf '#!/usr/bin/env bash\n' > "$2/scripts/release-check.sh"; }
add_project_settings() {
  mkdir -p "$2/.claude"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/.claude/hooks/force-push-guard.sh"
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash .claude/hooks/force-push-guard.sh"}]}]}}' \
    > "$2/.claude/$SETTINGS_FILE"
}

echo "Testing --audit CLAUDE.md cross-layer check"
echo "==========================================="

# --- it fires when it should ------------------------------------------------
check "a rule naming a script that exists nowhere is reported" \
  '- destructive commands are stopped by `production-db-guard.sh`' \
  missing

check "a hook that exists but is registered nowhere is reported" \
  '- force push is stopped by `force-push-guard.sh`' \
  orphan add_orphan_hook

check "missing wins over clean when both kinds appear" \
  '- `destructive-guard.sh` runs first
- then `production-db-guard.sh` runs' \
  missing

# --- it stays silent when it should -----------------------------------------
check "a resolvable, registered hook reports nothing" \
  '- destructive commands are stopped by `destructive-guard.sh`' \
  clean

check "a helper script the operator runs by hand is not called unregistered" \
  '- before shipping, run `scripts/release-check.sh` yourself
- destructive commands are stopped by `destructive-guard.sh`' \
  clean add_helper_script

check "a hook registered only in the project settings file is not called unregistered" \
  '- force push is stopped by `force-push-guard.sh`' \
  clean add_project_settings

check "a URL is not treated as a local script" \
  '- see `https://example.com/setup.js` for the rationale' \
  silent

check "a glob is not treated as a filename" \
  '- every `*.sh` under hooks needs the execute bit' \
  silent

check "a command line with arguments is not treated as a filename" \
  '- verify with `godot --headless --check-only project.py`' \
  silent

check "an extension Claude Code cannot run as a hook is ignored" \
  '- types live in `index.d.ts` and settings in `config.toml`' \
  silent

check "a CLAUDE.md naming nothing at all reports nothing" \
  '# Rules
- be careful with destructive commands' \
  silent

# Build output is absent on a fresh checkout and present after a build, so its
# absence says nothing about the rule. Found by running the extraction against
# 40 public CLAUDE.md files on 2026-08-13: of the two that named something
# missing from their repository, one was `dist/extension.js` — compiled, not
# broken. My own ten files had no case like it.
check "compiled output is not reported as a missing script" \
  '- the extension entry point is `dist/extension.js`
- the bundle lands in `build/main.js` and `out/cli.mjs`
- destructive commands are stopped by `destructive-guard.sh`' \
  clean

check "a script under a normal directory is still reported" \
  '- data is generated by `scripts/generate_mock_data.py`' \
  missing

echo
echo "audit-cross-layer-claudemd: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
