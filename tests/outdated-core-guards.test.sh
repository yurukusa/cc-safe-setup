#!/bin/bash
# --outdated was structurally blind to the guards it installs by default.
#
# Why this exists. `--install` writes the core guards from `scripts.json`.
# `--outdated` compared the hooks directory against `examples/` only. The core
# guards are not files under `examples/` — they are strings inside
# `scripts.json` — so every one of them fell into the "not shipped by this
# project — not checked" bucket. A user whose `destructive-guard.sh` was months
# behind was told, in those words, that it was none of this project's business.
#
# Measured on one real machine on 2026-08-12, before this fix:
#
#   destructive-guard.sh   installed  8,307 B (2026-05-27)   shipped 32,857 B
#   branch-guard.sh        installed  2,607 B (2026-05-27)   shipped  4,436 B
#   secret-guard.sh        installed  2,957 B (2026-05-27)   shipped  4,786 B
#
# Feeding the same input to both copies, six dangerous shapes were blocked by
# the shipped body and passed by the installed one, including `cd /tmp &&
# git push --force origin main` and `cd /tmp && git add .env`. The controls —
# the same commands on their own — were blocked by both, which is what makes it
# a gap in coverage rather than a mistake in how the probe was fed.
#
# The tool whose entire job was to notice this could not see the files.
#
# The second half of this test pins `--show-core`. `--outdated` can now name a
# stale core guard, but `--install-example` cannot fetch one, so naming it
# without a way to read the shipped body would report a problem the reader
# cannot act on.

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

contains() { # name haystack needle
  case "$2" in
    *"$3"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "        output did not contain: $3" ;;
  esac
}

not_contains() { # name haystack needle
  case "$2" in
    *"$3"*) FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "        output unexpectedly contained: $3" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT
mkdir -p "$TESTHOME/.claude/hooks"

run_outdated() {
  OUT=$(CLAUDE_PROJECT_DIR="$TESTHOME" node "$REPO/index.mjs" --outdated 2>&1)
  RC=$?
}

# The core guard used throughout. Read straight out of scripts.json so this test
# does not carry its own copy of the body that could itself go stale.
CORE_ID="branch-guard"
CORE_FILE="$CORE_ID.sh"
node -e '
  const fs = require("fs");
  const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  fs.writeFileSync(process.argv[2], s[process.argv[3]]);
' "$REPO/scripts.json" "$TESTHOME/.claude/hooks/$CORE_FILE" "$CORE_ID"

# --- 1. an untouched core guard reports as matching, not as "not checked" -----
run_outdated
check "untouched core guard exits 0" "0" "$RC"
not_contains "untouched core guard is not dismissed as foreign" "$OUT" "not shipped by this project"

# --- 2. a stale core guard is reported, and named as a core guard -------------
# The control matters: the edit below is the same shape as the real 2026-08-12
# defect — an outer gate anchored to the start of the line.
printf '\n# stale copy\n' >> "$TESTHOME/.claude/hooks/$CORE_FILE"
run_outdated
check "stale core guard exits 1" "1" "$RC"
contains "stale core guard is named" "$OUT" "$CORE_FILE"
contains "stale core guard is marked as core" "$OUT" "core guard"
not_contains "stale core guard is not dismissed as foreign" "$OUT" "not shipped by this project"

# --- 3. it still reports nothing about hooks this project does not ship -------
printf '#!/bin/bash\nexit 0\n' > "$TESTHOME/.claude/hooks/somebody-elses-hook.sh"
run_outdated
contains "a genuinely foreign hook is still reported as unchecked" "$OUT" "not shipped by this project"

# --- 4. it must not write anything -------------------------------------------
# A command whose whole job is "tell me if my safety net is stale" must not
# itself modify the safety net.
BEFORE=$(cd "$TESTHOME/.claude/hooks" && for f in *; do printf '%s %s\n' "$f" "$(wc -c < "$f")"; done)
run_outdated
AFTER=$(cd "$TESTHOME/.claude/hooks" && for f in *; do printf '%s %s\n' "$f" "$(wc -c < "$f")"; done)
check "--outdated writes nothing" "$BEFORE" "$AFTER"

# --- 5. --show-core prints the shipped body, and only that -------------------
SHOWN=$(node "$REPO/index.mjs" --show-core "$CORE_ID" 2>/dev/null)
SHOW_RC=$?
check "--show-core exits 0 for a real core guard" "0" "$SHOW_RC"
EXPECTED=$(node -e '
  const fs = require("fs");
  process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1], "utf8"))[process.argv[2]]);
' "$REPO/scripts.json" "$CORE_ID")
check "--show-core output is the shipped body verbatim" "$EXPECTED" "$SHOWN"

# The `.sh` suffix is what --outdated prints, so it has to be accepted.
node "$REPO/index.mjs" --show-core "$CORE_FILE" >/dev/null 2>&1
check "--show-core accepts the .sh form printed by --outdated" "0" "$?"

# --- 6. --show-core refuses an unknown name instead of printing nothing -------
BADOUT=$(node "$REPO/index.mjs" --show-core no-such-guard 2>&1)
BAD_RC=$?
check "--show-core exits 1 on an unknown name" "1" "$BAD_RC"
contains "--show-core lists what is available" "$BADOUT" "Available:"

# --- 7. --show-core must not write either ------------------------------------
BEFORE=$(cd "$TESTHOME/.claude/hooks" && for f in *; do printf '%s %s\n' "$f" "$(wc -c < "$f")"; done)
CLAUDE_PROJECT_DIR="$TESTHOME" node "$REPO/index.mjs" --show-core "$CORE_ID" >/dev/null 2>&1
AFTER=$(cd "$TESTHOME/.claude/hooks" && for f in *; do printf '%s %s\n' "$f" "$(wc -c < "$f")"; done)
check "--show-core writes nothing" "$BEFORE" "$AFTER"

echo "outdated-core-guards: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
