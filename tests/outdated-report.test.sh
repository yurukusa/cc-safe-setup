#!/bin/bash
# --outdated: which installed hooks no longer match what ships today.
#
# Why this exists. Installing a hook copies the file. Nothing ever copies it
# back. So a hook installed in March keeps running its March logic forever,
# including bugs fixed here months later, and until now nothing in the CLI
# could tell you that. Measured on a real four-month-old install: 27 of the 31
# hooks that came from this project no longer matched the shipped version, and
# three of those were missing the `jq` guard that was added after they were
# installed — the difference between blocking a dangerous command and silently
# approving it.
#
# The command only reports. The most important control here is the last one:
# it must not write anything. A command whose whole job is "tell me if my
# safety net is stale" must not itself modify the safety net.
#
# The second control is that "differs" is not claimed to mean "outdated".
# A user who edited their own copy on purpose must not be told they are behind,
# so the wording offers both readings and the test pins that wording.

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

# Sets OUT and RC. Deliberately not called through $( ) — command substitution
# runs in a subshell, so the exit code would never reach the caller.
run_outdated() {
  OUT=$(CLAUDE_PROJECT_DIR="$TESTHOME" node "$REPO/index.mjs" --outdated 2>&1)
  RC=$?
}

# --- 1. no hooks directory at all --------------------------------------------
run_outdated
check "no hooks dir exits 0" "0" "$RC"
contains "no hooks dir is explained" "$OUT" "No hooks directory"

# --- 2. an untouched copy of a shipped hook reports as matching ---------------
mkdir -p "$TESTHOME/.claude/hooks"
cp "$REPO/examples/protect-claudemd.sh" "$TESTHOME/.claude/hooks/protect-claudemd.sh"
run_outdated
check "identical copy exits 0" "0" "$RC"
contains "identical copy reported as matching" "$OUT" "match the shipped version"
not_contains "identical copy is not called differing" "$OUT" "differ from what ships today"

# --- 3. a modified copy is reported, and the exit code is non-zero -----------
echo "# a local change" >> "$TESTHOME/.claude/hooks/protect-claudemd.sh"
run_outdated
check "modified copy exits 1" "1" "$RC"
contains "modified copy is named" "$OUT" "protect-claudemd.sh"
contains "modified copy is counted" "$OUT" "differ from what ships today"

# --- 4. "differs" must not be claimed to mean "outdated" ---------------------
# The user may have edited the file on purpose. Both readings must be offered.
contains "both readings are offered (fixed here)" "$OUT" "was fixed after you installed it"
contains "both readings are offered (your edit)" "$OUT" "you edited your copy on purpose"
contains "a way to look before replacing" "$OUT" "diff "

# --- 5. the concrete harm: installed copy parses with jq but has no jq guard --
# Build exactly that situation from a shipped hook that does have the guard.
JQ_HOOK=""
for f in "$REPO"/examples/*.sh; do
  if grep -q 'command -v jq\|which jq' "$f" && grep -q '\bjq\b' "$f"; then
    JQ_HOOK="$f"; break
  fi
done
if [ -n "$JQ_HOOK" ]; then
  NAME="$(basename "$JQ_HOOK")"
  rm -f "$TESTHOME/.claude/hooks/protect-claudemd.sh"
  grep -v 'command -v jq' "$JQ_HOOK" | grep -v 'which jq' > "$TESTHOME/.claude/hooks/$NAME"
  run_outdated
  check "jq-guardless copy exits 1" "1" "$RC"
  contains "jq-guardless copy is flagged as such" "$OUT" "no jq guard"
else
  echo "  SKIP: no shipped hook both uses jq and guards for it"
fi

# --- 6. a hook this project does not ship is not judged ----------------------
rm -f "$TESTHOME/.claude/hooks"/*.sh
cat > "$TESTHOME/.claude/hooks/my-own-thing.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
run_outdated
check "foreign-only install exits 0" "0" "$RC"
contains "foreign hook counted separately" "$OUT" "not shipped by this project"
not_contains "foreign hook is not named as differing" "$OUT" "my-own-thing.sh differ"

# --- 7. the control that matters: --outdated must not write anything ---------
cp "$REPO/examples/protect-claudemd.sh" "$TESTHOME/.claude/hooks/protect-claudemd.sh"
echo "# local edit" >> "$TESTHOME/.claude/hooks/protect-claudemd.sh"
printf '{"hooks":{}}' > "$TESTHOME/.claude/settings.json"
BEFORE_HOOKS=$(cd "$TESTHOME/.claude/hooks" && for f in *; do printf '%s:%s\n' "$f" "$(cksum < "$f")"; done | sort)
BEFORE_SETTINGS=$(cksum < "$TESTHOME/.claude/settings.json")
run_outdated
AFTER_HOOKS=$(cd "$TESTHOME/.claude/hooks" && for f in *; do printf '%s:%s\n' "$f" "$(cksum < "$f")"; done | sort)
AFTER_SETTINGS=$(cksum < "$TESTHOME/.claude/settings.json")
check "hooks are untouched by --outdated" "$BEFORE_HOOKS" "$AFTER_HOOKS"
check "settings.json is untouched by --outdated" "$BEFORE_SETTINGS" "$AFTER_SETTINGS"

echo
echo "outdated-report: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
