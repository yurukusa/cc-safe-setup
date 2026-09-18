#!/usr/bin/env bash
# test-trigger-header-parsing.sh
#
# The installer decides which event a hook is registered on by reading the
# "# TRIGGER:" line of the example. Before 2026-09-18 it captured only the first
# whitespace-delimited token and checked it against a list that was missing four
# real events, so ten headers fell through to the default PreToolUse/Bash
# without a word. Two of those can exit 2, and an exit 2 on PreToolUse refuses
# the Bash call — so a hook written to refuse a *Stop* was refusing ordinary
# shell commands instead.
#
# This test pins the parsing rules against the real examples/ directory. It does
# not install anything and does not touch the user's settings.
#
# Usage: bash tests/test-trigger-header-parsing.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

pass=0; fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"
  fi
}

# Resolve a trigger the same way index.mjs does, so the test fails when the
# installer's rules drift from the headers that ship beside it.
resolve() { # resolve <file> -> event name, or NOT-REGISTERED
  node -e '
    const fs = require("fs");
    const EVENTS = ["PreToolUse","PostToolUse","PermissionRequest","Notification",
      "Stop","SubagentStop","SubagentStart","UserPromptSubmit","PreCompact",
      "PostCompact","SessionStart","SessionEnd","CwdChanged","FileChanged","DirectoryAdded"];
    const c = fs.readFileSync(process.argv[1], "utf8");
    const m = c.match(/^#\s*[Tt][Rr][Ii][Gg][Gg][Ee][Rr]:\s*(.+)$/m);
    if (!m) {
      if (/^#.*PermissionRequest hook/m.test(c)) return console.log("PermissionRequest");
      if (/^#.*UserPromptSubmit hook/m.test(c)) return console.log("UserPromptSubmit");
      return console.log("PreToolUse");
    }
    const decl = m[1].split(/[Mm][Aa][Tt][Cc][Hh][Ee][Rr]\s*:/)[0].replace(/\([^)]*\)/g, " ");
    if (/^\s*none\b/i.test(decl)) return console.log("NOT-REGISTERED");
    const names = (decl.match(/[A-Za-z]+/g) || []).filter((w) => EVENTS.includes(w));
    if (!names.length) return console.log("PreToolUse");
    console.log(names.includes("PreToolUse") ? "PreToolUse" : names[0]);
  ' "$1"
}

echo "== the four headers the old parser could not read =="

# "TRIGGER: Stop, UserPromptSubmit" — the trailing comma made the old capture
# "Stop," which matched nothing. This hook exits 2 in strict mode.
check "Stop, UserPromptSubmit -> Stop" \
  "Stop" "$(resolve examples/commitment-carry-forward-arrest.sh)"

# SubagentStop is a real Claude Code event that the registration list omitted
# while KNOWN_EVENTS in the same file already had it. Also exits 2.
check "SubagentStop -> SubagentStop" \
  "SubagentStop" "$(resolve examples/subagent-forged-system-reminder-guard.sh)"

# "TRIGGER: none" marks a wrapper that another hook calls. Wiring it to
# PreToolUse runs it before every tool call.
check "none -> not registered (debug wrapper)" \
  "NOT-REGISTERED" "$(resolve examples/hook-debug-wrapper.sh)"
check "none -> not registered (stdout sanitizer)" \
  "NOT-REGISTERED" "$(resolve examples/hook-stdout-sanitizer.sh)"

echo "== the cases a naive fix breaks (regression pins) =="

# Two-phase guards declare "PostToolUse+PreToolUse" and do their blocking with
# exit 2. Taking the literally-first name moves them to PostToolUse, where the
# tool has already run and exit 2 blocks nothing.
check "PostToolUse+PreToolUse keeps PreToolUse (deny-bypass)" \
  "PreToolUse" "$(resolve examples/deny-bypass-detector.sh)"
check "PostToolUse+PreToolUse keeps PreToolUse (denial-enforcer)" \
  "PreToolUse" "$(resolve examples/permission-denial-enforcer.sh)"

# A parenthetical aside is commentary, not a declaration.
check "SessionStart (also safe as PreToolUse) -> SessionStart" \
  "SessionStart" "$(resolve examples/multi-vendor-concurrent-warner.sh)"

# The inline "TRIGGER: X  MATCHER: "Edit|Write"" form must not leak the
# matcher's tool names into the event scan.
check "inline MATCHER does not leak into the event scan" \
  "PreToolUse" "$(resolve examples/settings-json-model-guard.sh)"

echo "== the whole shelf still resolves to a real event =="
bad=0
for f in examples/*.sh; do
  t="$(resolve "$f")"
  case "$t" in
    PreToolUse|PostToolUse|PermissionRequest|Notification|Stop|SubagentStop|SubagentStart|\
UserPromptSubmit|PreCompact|PostCompact|SessionStart|SessionEnd|CwdChanged|FileChanged|\
DirectoryAdded|NOT-REGISTERED) ;;
    *) bad=$((bad + 1)); printf 'FAIL  %s resolved to %s\n' "$f" "$t" ;;
  esac
done
check "every example resolves to a known event" "0" "$bad"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
