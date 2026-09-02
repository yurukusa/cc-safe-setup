#!/bin/bash
# A hook's declared trigger must match the envelope it emits.
#
# `prefer-builtin-tools.sh` — the hook recommended at the top of Discussion #59,
# which was the second most-read page in this repository over the 14 days ending
# 2026-09-03 (25 views, 23 unique, ahead of every code file) — declared
#
#   # TRIGGER: PermissionRequest  MATCHER: ""
#
# while its body emitted `"hookEventName":"PreToolUse"`. The installer reads the
# header to decide where to register, so as shipped it landed on
# PermissionRequest with an empty matcher.
#
# Measured in an isolated HOME on 2026-09-03, instrumented so the hook writes a
# line whenever it is entered:
#
#   registration                        entered   denials
#   PermissionRequest / ""              0         0
#   PreToolUse        / "Bash"          1         1
#
# Three runs on the shipped registration (default ×2, acceptEdits ×1) all
# entered it zero times. The instrument was proved first by piping a tool-call
# JSON into the same modified hook by hand: it wrote its line and printed the
# deny. So the zero means the hook was never consulted, not that the probe was
# broken.
#
# After the header was corrected, the model's own reply reported the mechanism
# working: "`cat ./probe.txt` itself did not run — a hook rejected it with 'Do
# not use `cat`. Use the Read tool to read files'".
#
# The body was right the whole time. The header was wrong, and nothing compared
# the two. This test compares them.

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

# --- the general rule: declared trigger vs emitted envelope, every example ----
MISMATCH="$(cd "$REPO" && python3 - <<'PY'
import pathlib, re
rows = []
for f in sorted(pathlib.Path("examples").glob("*.sh")):
    s = f.read_text(errors="ignore")
    m = re.search(r"^#\s*TRIGGER:\s*(\S+)", s, re.M)
    if not m:
        continue
    declared = m.group(1)
    emitted = sorted(set(re.findall(r'"hookEventName"\s*:\s*"([A-Za-z]+)"', s)))
    # A hook that decides with exit codes alone emits no envelope; nothing to compare.
    if not emitted:
        continue
    if declared not in emitted:
        rows.append(f"{f.name}: declares {declared}, emits {emitted}")
print("\n".join(rows))
PY
)"
check "no example declares one event and emits another" "" "$MISMATCH"

# The rule has to be able to fail, or it is decoration.
PROBE_DIR="$(mktemp -d)"
mkdir -p "$PROBE_DIR/examples"
cat > "$PROBE_DIR/examples/planted.sh" <<'HOOK'
#!/bin/bash
# TRIGGER: PermissionRequest  MATCHER: ""
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'
HOOK
PLANTED="$(cd "$PROBE_DIR" && python3 - <<'PY'
import pathlib, re
rows = []
for f in sorted(pathlib.Path("examples").glob("*.sh")):
    s = f.read_text(errors="ignore")
    m = re.search(r"^#\s*TRIGGER:\s*(\S+)", s, re.M)
    if not m: continue
    emitted = sorted(set(re.findall(r'"hookEventName"\s*:\s*"([A-Za-z]+)"', s)))
    if emitted and m.group(1) not in emitted:
        rows.append(f.name)
print(",".join(rows))
PY
)"
check "the comparison catches a planted mismatch" "planted.sh" "$PLANTED"
rm -rf "$PROBE_DIR"

# --- the specific hook, pinned ------------------------------------------------
HDR="$(grep -m1 '^# TRIGGER:' "$REPO/examples/prefer-builtin-tools.sh")"
check "prefer-builtin-tools declares PreToolUse on Bash" \
  "yes" "$(printf '%s' "$HDR" | grep -q 'TRIGGER: PreToolUse' && printf '%s' "$HDR" | grep -q 'MATCHER: "Bash"' && echo yes || echo no)"

# Where the installer actually puts it. The header is only a claim until this runs.
INSTALL_HOME="$(mktemp -d)"
mkdir -p "$INSTALL_HOME/.claude"
HOME="$INSTALL_HOME" node "$REPO/index.mjs" --install-example prefer-builtin-tools >/dev/null 2>&1
WHERE="$(python3 - "$INSTALL_HOME/.claude/settings.json" <<'PY'
import json, sys, pathlib
try:
    d = json.loads(pathlib.Path(sys.argv[1]).read_text())
except Exception:
    print("no-settings"); raise SystemExit
for ev, entries in (d.get("hooks") or {}).items():
    for e in entries:
        for h in (e.get("hooks") or []):
            if "prefer-builtin" in str(h.get("command", "")):
                print(f"{ev}/{e.get('matcher')}")
                raise SystemExit
print("not-registered")
PY
)"
check "the installer registers it where the header says" "PreToolUse/Bash" "$WHERE"

# And it still denies when fed the shape it is meant to catch.
OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat ./secret.txt"}}' \
  | bash "$INSTALL_HOME/.claude/hooks/prefer-builtin-tools.sh" 2>/dev/null)"
check "it denies a bare cat" \
  "yes" "$(printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"' && echo yes || echo no)"
check "and denies it after a separator too" \
  "yes" "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && cat ./secret.txt"}}' \
    | bash "$INSTALL_HOME/.claude/hooks/prefer-builtin-tools.sh" 2>/dev/null \
    | grep -q '"permissionDecision":"deny"' && echo yes || echo no)"

echo "  hook-trigger-matches-envelope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
