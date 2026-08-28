#!/bin/bash
# selftest.sh - prove that find-dead-hooks.sh really detects a registration
# whose script is missing.
#
# A detector that finds nothing proves nothing until you have seen it find
# something. This builds a deliberately broken settings file in a throwaway
# directory, with one registration pointing at a script that does not exist and
# one pointing at a script that does, and checks both directions.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
mkdir -p "$T/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$T/.claude/hooks/real.sh"
chmod +x "$T/.claude/hooks/real.sh"

cat > "$T/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/ghost.sh"},
  {"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/real.sh"}
]}]}}
JSON

echo "=== control: one registration points at a missing script, one at a real one ==="
out=$(cd "$T" && CLAUDE_PROJECT_DIR="$T" HOME="$T" bash "$HERE/find-dead-hooks.sh" 2>&1)
printf '%s\n' "$out"
echo

if printf '%s' "$out" | grep -q "ghost.sh"; then
  echo "result: PASS - the missing registration was reported"
else
  echo "result: FAIL - the missing registration was NOT reported"
fi
if printf '%s' "$out" | grep -q "real.sh"; then
  echo "result: FAIL - the real registration was reported too"
else
  echo "result: PASS - the real registration was not reported"
fi

# clean up: remove only what we created, one path at a time
for f in "$T/.claude/settings.json" "$T/.claude/hooks/real.sh"; do [ -f "$f" ] && unlink "$f"; done
rmdir "$T/.claude/hooks" "$T/.claude" "$T" 2>/dev/null
echo "(cleaned up the throwaway directory)"
