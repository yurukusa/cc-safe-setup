#!/bin/bash
# --blindspots must compare two layers, and must not mistake an allow test for a gate.
#
# Why this exists. Every other diagnostic in this tool reads one layer: the
# scripts on disk (--status), the settings file (--lint), the block log
# (--stats), the shipped bodies (--outdated). A guard can be present,
# executable, registered and current in all four and still never fire, because
# the shape of the commands actually run on that machine never reaches it.
# `--blindspots` is the only check that reads the session transcripts next to
# the guards, so it is the only one that can see that gap.
#
# The trap this test pins is in the instrument, not in the user's setup. Hook
# scripts contain start-anchored patterns for two opposite purposes:
#
#   gate     if printf '%s' "$CMD" | grep -qE '^\s*git\s+add'; then ... exit 2
#   subject  if ! printf '%s' "$CMD" | grep -qE '^\s*git\s+push'; then exit 0; fi
#   exempt   if printf '%s' "$CMD" | grep -qE '^\s*(cat|ls)'; then exit 0; fi
#
# The first two decide what the hook reaches. The third decides what it lets
# through on purpose. Counting the third as an unguarded gap fills the report
# with alarms about read-only commands the author deliberately waved past — a
# tool that warns about the very defect it contains. So this test asserts both
# directions: the gate and the subject are reported, and the exempt pattern is
# not.
#
# Numbers are fixed by construction: 25 calls invoke `git push`, 5 of them at
# the start of the string, 20 after a `cd ... &&`. Blind = 20/25 = 80.0%.

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
    echo "    expected: $2"
    echo "    actual:   $3"
  fi
}

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; find "$TMP" -mindepth 1 -delete 2>/dev/null; rmdir "$TMP" 2>/dev/null' EXIT

mkdir -p "$TMP/.claude/hooks" "$TMP/.claude/projects/-tmp-probe"

# A gate: the anchor is the blocking condition.
cat > "$TMP/.claude/hooks/probe-add-guard.sh" <<'HOOK'
#!/bin/bash
CMD=$(cat)
if printf '%s' "$CMD" | grep -qE '^\s*git\s+add'; then
  echo "blocked" >&2
  exit 2
fi
exit 0
HOOK

# A subject filter: anything not matching the anchor is never examined at all.
cat > "$TMP/.claude/hooks/probe-push-guard.sh" <<'HOOK'
#!/bin/bash
CMD=$(cat)
if ! printf '%s' "$CMD" | grep -qE '^\s*git\s+push'; then
  exit 0
fi
echo "blocked" >&2
exit 2
HOOK

# An allow test: these are waved through deliberately and are not a gap.
cat > "$TMP/.claude/hooks/probe-readonly-allow.sh" <<'HOOK'
#!/bin/bash
CMD=$(cat)
if printf '%s' "$CMD" | grep -qE '^\s*(cat|ls|head)'; then
  exit 0
fi
exit 0
HOOK

chmod +x "$TMP/.claude/hooks/"*.sh

# One registration points at a script that is not there. Settings say it is
# installed; the filesystem says otherwise. Neither layer alone shows this.
cat > "$TMP/.claude/settings.json" <<SETTINGS
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \$HOME/.claude/hooks/probe-push-guard.sh" },
          { "type": "command", "command": "bash \$HOME/.claude/hooks/probe-removed-guard.sh" }
        ]
      }
    ]
  }
}
SETTINGS

# 25 invocations of `git push`: 5 at the start, 20 behind a `cd ... &&`.
# Plus 30 `cat` calls, which the allow test covers on purpose.
TRANSCRIPT="$TMP/.claude/projects/-tmp-probe/session.jsonl"
: > "$TRANSCRIPT"
emit() { # command
  printf '{"type":"assistant","timestamp":"2026-09-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" >> "$TRANSCRIPT"
}
for i in $(seq 1 5);  do emit "git push origin main"; done
for i in $(seq 1 20); do emit "cd /tmp/work && git push origin main"; done
for i in $(seq 1 30); do emit "cat /tmp/work/notes.md"; done

OUT="$(HOME="$TMP" node "$REPO/index.mjs" --blindspots 2>&1)"
PLAIN="$(printf '%s' "$OUT" | sed 's/\x1b\[[0-9;]*m//g')"

# Layer 4 was actually read.
check "counts the Bash calls in the transcript" \
  "yes" "$(printf '%s' "$PLAIN" | grep -qE '\b55 Bash calls' && echo yes || echo no)"

# The subject filter is reported, with the blind rate fixed by construction.
check "reports the start-anchored push guard" \
  "yes" "$(printf '%s' "$PLAIN" | grep -q 'probe-push-guard.sh' && echo yes || echo no)"
check "blind rate is 20 of 25" \
  "yes" "$(printf '%s' "$PLAIN" | grep -qE 'git push .*probe-push-guard\.sh +25 +5 +80\.0%' && echo yes || echo no)"
check "labels a subject filter as never examined" \
  "yes" "$(printf '%s' "$PLAIN" | grep -qE 'probe-push-guard\.sh.*never examined' && echo yes || echo no)"

# The allow test must not be listed. This is the instrument's own failure mode.
check "does not report the allow test as a gap" \
  "yes" "$(printf '%s' "$PLAIN" | grep -q 'probe-readonly-allow.sh' && echo no || echo yes)"

# The registration with no file behind it.
check "names the registration whose file is missing" \
  "yes" "$(printf '%s' "$PLAIN" | grep -q 'probe-removed-guard.sh' && echo yes || echo no)"
check "does not flag the registration that does exist" \
  "yes" "$(printf '%s' "$PLAIN" | grep -qE '^\s+·.*probe-push-guard\.sh' && echo no || echo yes)"

# Nothing is written back. This command reads; it must never touch settings.
BEFORE="$(md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)"
HOME="$TMP" node "$REPO/index.mjs" --blindspots >/dev/null 2>&1
AFTER="$(md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)"
check "leaves settings.json untouched" "$BEFORE" "$AFTER"

echo "  blindspots-cross-layer: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
