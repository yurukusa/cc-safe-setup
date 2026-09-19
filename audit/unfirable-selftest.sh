#!/bin/bash
# unfirable-selftest.sh - prove that find-unfirable-rules.sh really detects a
# rule that cannot match, and does not report rules that can.
#
# A detector that finds nothing proves nothing until you have seen it find
# something. This builds a throwaway setup with four rules: two that cannot
# match (one of each mechanism), and two correct spellings of the same
# patterns. Both directions are checked, because a detector that flags
# everything is as useless as one that flags nothing.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
mkdir -p "$T/.claude/hooks"

cat > "$T/.claude/hooks/broken.sh" <<'SH'
#!/bin/bash
# eaten as options: the pattern starts with a dash
if grep -qE '--no-verify|SKIP_CI' "$1"; then echo "skip detected" >&2; fi
# lookaround in an engine that has none
if grep -qE '(?!origin\b)' "$1"; then echo "non-origin remote" >&2; fi
SH

cat > "$T/.claude/hooks/correct.sh" <<'SH'
#!/bin/bash
# the same two rules, spelled so they can actually match
if grep -qE -- '--no-verify|SKIP_CI' "$1"; then echo "skip detected" >&2; fi
if grep -qP '(?!origin\b)' "$1"; then echo "non-origin remote" >&2; fi
SH
chmod +x "$T/.claude/hooks/broken.sh" "$T/.claude/hooks/correct.sh"

cat > "$T/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/broken.sh"},
  {"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/correct.sh"},
  {"type":"command","command":"if echo \"$X\" | grep -qE \"--force-with-lease\"; then exit 2; fi"},
  {"type":"command","command":"if echo \"$X\" | grep -qE -- \"--force-with-lease\"; then exit 2; fi"}
]}]}}
JSON

echo "=== control: two rules that cannot match, two that can, plus the same pair inline ==="
out=$(cd "$T" && CLAUDE_PROJECT_DIR="$T" HOME="$T" bash "$HERE/find-unfirable-rules.sh" 2>&1)
printf '%s\n' "$out"
echo

fails=0
expect_present() {
  if printf '%s' "$out" | grep -q -- "$1"; then
    echo "result: PASS - $2"
  else
    echo "result: FAIL - $2"; fails=$((fails + 1))
  fi
}
expect_absent() {
  if printf '%s' "$out" | grep -q -- "$1"; then
    echo "result: FAIL - $2"; fails=$((fails + 1))
  else
    echo "result: PASS - $2"
  fi
}

expect_present "broken.sh"        "the script with two unfirable rules was reported"
expect_present "reads it as options" "the option-eating mechanism was named"
expect_present "lookaround"       "the lookaround mechanism was named"
expect_present "(inline)"         "the inline rule written into settings.json was reported"
expect_absent  "correct.sh"       "the correctly spelled script was not reported"

# The correct inline spelling uses -- ; it must not appear as a finding. The
# broken one does, so count the inline blocks rather than the substring.
inline_hits=$(printf '%s' "$out" | grep -c -- "(inline)" || true)
if [ "$inline_hits" -eq 1 ]; then
  echo "result: PASS - exactly one of the two inline rules was reported"
else
  echo "result: FAIL - expected 1 inline finding, got $inline_hits"; fails=$((fails + 1))
fi

for f in "$T/.claude/settings.json" "$T/.claude/hooks/broken.sh" "$T/.claude/hooks/correct.sh"; do
  [ -f "$f" ] && unlink "$f"
done
rmdir "$T/.claude/hooks" "$T/.claude" "$T" 2>/dev/null
echo "(cleaned up the throwaway directory)"
[ "$fails" -eq 0 ]
