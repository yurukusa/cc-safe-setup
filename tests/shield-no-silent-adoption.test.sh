#!/bin/bash
# --shield must not register hooks the operator did not ask for.
#
# Until 2026-07-27, Step 4 walked every .sh in ~/.claude/hooks/ and registered
# whatever it found, guessing the trigger from the filename. Two consequences,
# both seen in the field:
#
#   - a hook another tool had dropped in that directory got registered here
#   - a hook the operator had deliberately UNREGISTERED came back on the next run
#
# The second one caused three real rollbacks (2026-06-10, and twice on
# 2026-07-27) where a cleaned-up hook configuration was silently restored.
# Removing a registration is a decision; silently reversing a decision is the
# exact failure class this project exists to prevent.
#
# The fix keys off disk state rather than provenance: only hooks this run newly
# wrote are registered. A file already on disk has been seen by the operator,
# so its registration is theirs to decide. --adopt-existing restores the old
# sweep, and a first-time setup (no config file yet) still adopts everything so
# a half-finished earlier run can be picked up.
#
# The body of this suite is Python because it needs JSON round-tripping; this
# wrapper exists so CI (which globs tests/*.sh) actually runs it. A test that
# never runs is worth nothing — see the 234 suites wired into CI on 2026-07-27.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  SKIP: python3 not available"
  exit 0
fi

output=$(python3 "$ROOT/tests/shield-no-silent-adoption.test.py" 2>&1)
status=$?
printf '%s\n' "$output"

if [ "$status" -ne 0 ]; then
  exit 1
fi
if printf '%s' "$output" | grep -q '不合格'; then
  exit 1
fi
if ! printf '%s' "$output" | grep -q '全ケース合格'; then
  echo "  FAIL: suite did not report a verdict"
  exit 1
fi
exit 0
