#!/bin/bash
# boundary-selftest.sh - prove that boundary.sh actually distinguishes a guard
# with a hole from a guard without one.
#
# A detector that reports "holes: 0" is worthless until you have watched it
# report a hole it was supposed to find. This builds two guards in a throwaway
# directory - one anchored so tightly that backups walk through, one widened -
# and checks that boundary.sh separates them in both directions.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
check() {  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS + 1))
  else echo "  FAIL: $1 (expected $2, got $3)"; FAIL=$((FAIL + 1)); fi
}

# A guard that refuses the exact name and nothing near it.
cat > "$T/narrow.sh" <<'SH'
#!/bin/bash
F=$(cat | grep -o '"file_path":"[^"]*"' | sed 's/.*:"//; s/"$//')
[ -z "$F" ] && exit 0
echo "$F" | grep -qE 'id_rsa$' && { echo "BLOCKED" >&2; exit 2; }
exit 0
SH

# The same guard, widened to cover backups, and still letting .pub through.
# The -i is not decoration: the first draft of this fixture omitted it and
# boundary.sh correctly reported ID_RSA as a hole. Case folding is one of the
# neighbours, so a fixture that means to be clean has to fold case too.
cat > "$T/wide.sh" <<'SH'
#!/bin/bash
F=$(cat | grep -o '"file_path":"[^"]*"' | sed 's/.*:"//; s/"$//')
[ -z "$F" ] && exit 0
echo "$F" | grep -qiE '\.pub[[:space:]]*$' && exit 0
echo "$F" | grep -qiE 'id_rsa(([._-](bak|old|orig|save|copy|backup|[0-9]+))|~){0,3}[[:space:]]*$' \
  && { echo "BLOCKED" >&2; exit 2; }
exit 0
SH

# A guard that refuses everything. Safe-looking and unusable; the "allow" rows
# exist to catch exactly this, so the detector must call it overreach.
cat > "$T/paranoid.sh" <<'SH'
#!/bin/bash
cat >/dev/null
echo "BLOCKED" >&2
exit 2
SH
chmod +x "$T"/*.sh

echo "=== control 1: a narrow guard must be reported as having holes ==="
out=$(bash "$HERE/boundary.sh" "$T/narrow.sh" Read file_path /home/me/.ssh/id_rsa 2>&1); rc=$?
printf '%s\n' "$out" | grep -E '^holes|^overreach'
holes=$(printf '%s\n' "$out" | sed -n 's/^holes *: *\([0-9]*\).*/\1/p')
over=$(printf '%s\n' "$out" | sed -n 's/^overreach *: *\([0-9]*\).*/\1/p')
check "narrow guard reports at least one hole" "yes" "$([ "${holes:-0}" -ge 1 ] && echo yes || echo no)"
check "narrow guard reports no overreach"      "0"   "${over:-x}"
check "narrow guard exits non-zero"            "yes" "$([ "$rc" -ne 0 ] && echo yes || echo no)"

echo "=== control 2: the widened guard must come back clean ==="
out=$(bash "$HERE/boundary.sh" "$T/wide.sh" Read file_path /home/me/.ssh/id_rsa 2>&1); rc=$?
printf '%s\n' "$out" | grep -E '^holes|^overreach'
holes=$(printf '%s\n' "$out" | sed -n 's/^holes *: *\([0-9]*\).*/\1/p')
over=$(printf '%s\n' "$out" | sed -n 's/^overreach *: *\([0-9]*\).*/\1/p')
check "widened guard reports no holes"     "0"   "${holes:-x}"
check "widened guard reports no overreach" "0"   "${over:-x}"
check "widened guard exits zero"           "0"   "$rc"

echo "=== control 3: a guard that refuses everything must be reported as overreach ==="
out=$(bash "$HERE/boundary.sh" "$T/paranoid.sh" Read file_path /home/me/.ssh/id_rsa 2>&1)
over=$(printf '%s\n' "$out" | sed -n 's/^overreach *: *\([0-9]*\).*/\1/p')
holes=$(printf '%s\n' "$out" | sed -n 's/^holes *: *\([0-9]*\).*/\1/p')
check "refuse-everything guard reports overreach" "yes" "$([ "${over:-0}" -ge 1 ] && echo yes || echo no)"
check "refuse-everything guard reports no holes"  "0"   "${holes:-x}"

echo "=== control 4: the target itself is fired, not just its neighbours ==="
out=$(bash "$HERE/boundary.sh" "$T/wide.sh" Read file_path /home/me/.ssh/id_rsa 2>&1)
check "the thing itself appears as a row" "yes" \
  "$(printf '%s\n' "$out" | grep -qE 'the thing itself .*refused' && echo yes || echo no)"

echo
echo "=========================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
