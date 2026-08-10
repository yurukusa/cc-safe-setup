#!/bin/bash
# --install-example registered "not a hook" tools as hooks.
#
# Three examples declare in their own header that they are not Claude Code
# hooks — they are things you run by hand:
#
#     mcp-stdio-compatibility-test   "# Event: standalone CLI, not a Claude Code hook."
#     cost-incident-self-audit       "# This is NOT a hook — it is a one-shot diagnostic"
#     cch-sentinel-precommit-guard   "# Event: git pre-commit (NOT a Claude Code hook)"
#
# None of them carries a TRIGGER line, and installExample() falls back to
# PreToolUse/Bash when it cannot find one. So installing any of them wired it
# in front of every Bash call.
#
# For two of the three that is merely wrong. For the third it is severe:
# mcp-stdio-compatibility-test exits 2 when settings.json is unreadable or is
# not valid JSON, and exit 2 on PreToolUse *denies the call*. Installing a
# "test harness" therefore turned every Bash call into a hard denial, and the
# only clue was a line about a settings file the user never asked it to read.
#
# The fix refuses to register a file that says it is not a hook. The file is
# still copied — the user asked for it — and the output says how to run it.
#
# The controls are what keep this from becoming "refuse anything that mentions
# hooks": a real hook must still install, and it must still land on the trigger
# and matcher its header declares. Measured over all 910 examples, the pattern
# matches exactly the 3 above and none of the 716 that declare a TRIGGER.
# (cli-config-pinning-detector was a near miss during development: its prose
# mentions "the standalone Anthropic CLI", which is why the check is anchored
# to comment lines and to the words "not a ... hook" rather than "standalone".)

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    echo "        expected: $2"
    echo "        actual:   $3"
  fi
}

TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT

registered_count() {
  node -e '
    const fs = require("fs");
    const p = process.argv[1] + "/.claude/settings.json";
    if (!fs.existsSync(p)) { console.log("0"); process.exit(0); }
    const s = JSON.parse(fs.readFileSync(p, "utf8"));
    let n = 0;
    for (const gs of Object.values(s.hooks || {})) for (const g of gs) n += (g.hooks || []).length;
    console.log(String(n));
  ' "$TESTHOME"
}

registered_names() {
  node -e '
    const fs = require("fs");
    const p = process.argv[1] + "/.claude/settings.json";
    if (!fs.existsSync(p)) { console.log(""); process.exit(0); }
    const s = JSON.parse(fs.readFileSync(p, "utf8"));
    const out = [];
    for (const [ev, gs] of Object.entries(s.hooks || {}))
      for (const g of gs) for (const h of (g.hooks || []))
        out.push(ev + "|" + (g.matcher ?? "") + "|" + (h.command || "").split("/").pop());
    console.log(out.join(" "));
  ' "$TESTHOME"
}

# --- the three standalone tools must not be registered -----------------------

for tool in mcp-stdio-compatibility-test cost-incident-self-audit cch-sentinel-precommit-guard; do
  out="$(cd "$REPO" && HOME="$TESTHOME" node index.mjs --install-example "$tool" 2>&1)"
  said_no="no"
  case "$out" in *"NOT registered as a hook"*) said_no="yes" ;; esac
  check "$tool says it will not be registered" "yes" "$said_no"

  copied="no"
  [ -f "$TESTHOME/.claude/hooks/$tool.sh" ] && copied="yes"
  check "$tool is still copied to hooks dir" "yes" "$copied"
done

check "no standalone tool reached settings.json" "0" "$(registered_count)"

# --- control: a real hook must still install exactly as before ---------------

for hook in checkpoint-tamper-guard dependency-install-guard; do
  (cd "$REPO" && HOME="$TESTHOME" node index.mjs --install-example "$hook" >/dev/null 2>&1)
done

names="$(registered_names)"

for hook in checkpoint-tamper-guard dependency-install-guard; do
  found="no"
  case "$names" in *"PreToolUse|Bash|$hook.sh"*) found="yes" ;; esac
  check "control: $hook still lands on PreToolUse/Bash" "yes" "$found"
done

leaked="no"
case "$names" in
  *mcp-stdio*|*cost-incident*|*cch-sentinel*) leaked="yes" ;;
esac
check "no standalone tool leaked in alongside real hooks" "no" "$leaked"

# --- the detection itself, measured over the whole example set ---------------
# A regression here would show up as a real hook silently refusing to install,
# which is harder to notice than the bug this test is about.

counts="$(node -e '
  const fs = require("fs"), path = require("path");
  const dir = path.join(process.argv[1], "examples");
  const RE = /^#.*\bnot a (?:claude code )?hook\b/im;
  let standalone = 0, withTrigger = 0, conflict = 0;
  for (const f of fs.readdirSync(dir).filter(x => x.endsWith(".sh"))) {
    const head = fs.readFileSync(path.join(dir, f), "utf8").split("\n").slice(0, 25).join("\n");
    const isStandalone = RE.test(head);
    const hasTrigger = /^#\s*trigger:/im.test(head);
    if (isStandalone) standalone++;
    if (hasTrigger) withTrigger++;
    if (isStandalone && hasTrigger) conflict++;
  }
  console.log(standalone + " " + conflict + " " + (withTrigger > 0 ? "1" : "0"));
' "$REPO")"

set -- $counts
check "exactly 3 examples declare themselves not-a-hook" "3" "$1"
check "no example both declares a TRIGGER and refuses to be a hook" "0" "$2"
check "the TRIGGER-declaring population is non-empty (control)" "1" "$3"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
