#!/bin/bash
# Tests for the four plugins distributed through the Claude Code plugin marketplace
# (plugins/*/.claude-plugin/plugin.json).
#
# Why this file exists: the 900+ example hooks have thousands of assertions, but the
# hooks we ship *inside the marketplace plugins* had none. That gap let a real defect
# ride in production - every hook parsed its stdin with `jq`, and when `jq` was absent
# the extracted value was empty, the next line read that as "nothing to inspect", and
# the hook exited 0. Install succeeded, no error was printed, and every block silently
# disappeared. A safety net that fails open in silence is worse than no net, because
# the user believes they are protected.
#
# What is asserted here:
#   1. Every block still blocks when jq is available.
#   2. Every block still blocks when jq is missing but python3 or node is available.
#   3. When none of jq/python3/node exists, the hook does NOT block (that would brick
#      every tool call) but it MUST say so on stderr instead of failing silently.
#   4. The documented safe alternatives are not blocked (--force-with-lease, .env.example).

PLUGIN_DIR="$(cd "$(dirname "$0")/../plugins" && pwd)"
PASS=0
FAIL=0
TOTAL=0

TMPDIR=$(mktemp -d)
trap 'rm -f /tmp/cc-noparser-warned-* /tmp/cc-read-budget-*; rm -rf "$TMPDIR"' EXIT

# Build PATHs that expose only a chosen subset of the three JSON readers.
build_bin() {
  local name="$1"; shift
  local dir="$TMPDIR/bin-$name"
  mkdir -p "$dir"
  for tool in cat grep echo sed env bash sh stat wc basename tr; do
    src=$(command -v "$tool" 2>/dev/null) && [ -n "$src" ] && ln -sf "$src" "$dir/$tool"
  done
  for tool in "$@"; do
    src=$(command -v "$tool" 2>/dev/null) && [ -n "$src" ] && ln -sf "$src" "$dir/$tool"
  done
  echo "$dir"
}

BIN_PY=$(build_bin py python3)
BIN_NODE=$(build_bin node node)
BIN_NONE=$(build_bin none)

# Pull one hook command out of a plugin manifest by event and 1-based index.
hook_cmd() {
  local plugin="$1" event="$2" idx="$3"
  python3 - "$PLUGIN_DIR/$plugin/.claude-plugin/plugin.json" "$event" "$idx" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1]))
entry = spec["hooks"][sys.argv[2]][int(sys.argv[3]) - 1]
print(entry["hooks"][0]["command"])
PY
}

# run_case <plugin> <event> <index> <payload> <expected-exit> <description>
run_case() {
  local plugin="$1" event="$2" idx="$3" payload="$4" want="$5" desc="$6"
  local cmd; cmd=$(hook_cmd "$plugin" "$event" "$idx")
  local label out code RUNPATH

  for label in normal py node none; do
    rm -f /tmp/cc-noparser-warned-* /tmp/cc-read-budget-* 2>/dev/null
    case "$label" in
      normal) RUNPATH="$PATH" ;;
      py)     RUNPATH="$BIN_PY" ;;
      node)   RUNPATH="$BIN_NODE" ;;
      none)   RUNPATH="$BIN_NONE" ;;
    esac
    out=$(printf '%s' "$payload" | env PATH="$RUNPATH" ${EXTRA_ENV:+$EXTRA_ENV} bash -c "$cmd" 2>&1)
    code=$?
    TOTAL=$((TOTAL + 1))

    if [ "$label" = "none" ]; then
      # No JSON reader at all: must not block, but must not be silent either
      # when it was supposed to be guarding something.
      if [ "$want" -eq 2 ]; then
        if [ "$code" -eq 0 ] && [ -n "$out" ]; then
          echo "  PASS: $desc [no reader: warns instead of silent]"; PASS=$((PASS + 1))
        else
          echo "  FAIL: $desc [no reader: exit=$code out='$out' - expected exit 0 with a warning]"; FAIL=$((FAIL + 1))
        fi
      else
        if [ "$code" -eq 0 ]; then
          echo "  PASS: $desc [no reader: allowed]"; PASS=$((PASS + 1))
        else
          echo "  FAIL: $desc [no reader: exit=$code]"; FAIL=$((FAIL + 1))
        fi
      fi
      continue
    fi

    if [ "$code" -eq "$want" ]; then
      echo "  PASS: $desc [$label]"; PASS=$((PASS + 1))
    else
      echo "  FAIL: $desc [$label: exit=$code want=$want out='$out']"; FAIL=$((FAIL + 1))
    fi
  done
}

echo "=== marketplace plugins: blocks hold in every environment ==="

run_case safety-essentials PreToolUse 1 '{"tool_input":{"command":"rm -rf /tmp/x"}}' 2 "safety-essentials blocks recursive delete"
run_case safety-essentials PreToolUse 1 '{"tool_input":{"command":"rm notes.txt"}}' 0 "safety-essentials allows single file delete"
run_case safety-essentials PreToolUse 2 '{"tool_input":{"command":"git push -f origin topic"}}' 2 "safety-essentials blocks force push"
run_case safety-essentials PreToolUse 3 '{"tool_input":{"command":"git reset --hard HEAD~1"}}' 2 "safety-essentials blocks hard reset"
run_case safety-essentials PreToolUse 4 '{"tool_input":{"file_path":"/p/.env"}}' 2 "safety-essentials blocks .env write"
run_case safety-essentials PreToolUse 5 '{"tool_input":{"command":"npm publish"}}' 2 "safety-essentials blocks package publish"
run_case safety-essentials PreToolUse 5 '{"tool_input":{"command":"npm install"}}' 0 "safety-essentials allows npm install"

run_case git-protection PreToolUse 1 '{"tool_input":{"command":"git push --force origin topic"}}' 2 "git-protection blocks force push"
run_case git-protection PreToolUse 2 '{"tool_input":{"command":"git push origin main"}}' 2 "git-protection blocks push to main"
run_case git-protection PreToolUse 3 '{"tool_input":{"command":"git reset --hard HEAD~1"}}' 2 "git-protection blocks hard reset"
run_case git-protection PreToolUse 4 '{"tool_input":{"command":"git clean -fd"}}' 2 "git-protection blocks git clean -fd"
run_case git-protection PreToolUse 5 '{"tool_input":{"command":"git branch -D topic"}}' 2 "git-protection blocks force branch delete"
run_case git-protection PreToolUse 5 '{"tool_input":{"command":"git branch -d topic"}}' 0 "git-protection allows safe branch delete"

run_case credential-guard PreToolUse 1 '{"tool_input":{"file_path":"/p/.env"}}' 2 "credential-guard blocks .env write"
run_case credential-guard PreToolUse 2 '{"tool_input":{"file_path":"/p/credentials.yml"}}' 2 "credential-guard blocks credentials edit"
run_case credential-guard PreToolUse 4 '{"tool_input":{"file_path":"/p/key.json"}}' 2 "credential-guard blocks service account key"
run_case credential-guard PreToolUse 4 '{"tool_input":{"file_path":"/p/package.json"}}' 0 "credential-guard allows package.json"

echo
echo "=== the documented safe alternative must not be blocked ==="
# The block message tells the user to use --force-with-lease. Blocking that too
# would make the hook's own advice impossible to follow.
run_case safety-essentials PreToolUse 2 '{"tool_input":{"command":"git push --force-with-lease origin topic"}}' 0 "safety-essentials allows --force-with-lease"
run_case git-protection PreToolUse 1 '{"tool_input":{"command":"git push --force-with-lease origin topic"}}' 0 "git-protection allows --force-with-lease"
run_case git-protection PreToolUse 1 '{"tool_input":{"command":"git push origin topic"}}' 0 "git-protection allows normal push"

echo
echo "=== env templates are meant to be committed, so writing them is allowed ==="
run_case safety-essentials PreToolUse 4 '{"tool_input":{"file_path":"/p/.env.example"}}' 0 "safety-essentials allows .env.example"
run_case credential-guard PreToolUse 1 '{"tool_input":{"file_path":"/p/.env.sample"}}' 0 "credential-guard allows .env.sample"
run_case credential-guard PreToolUse 2 '{"tool_input":{"file_path":"/p/.env.template"}}' 0 "credential-guard allows .env.template"
run_case safety-essentials PreToolUse 4 '{"tool_input":{"file_path":"/p/.env.local"}}' 2 "safety-essentials still blocks .env.local"

echo
echo "=== manifest integrity ==="
# A version that disagrees with the marketplace entry makes readers install a
# different build than the one documented.
MISMATCH=$(python3 - "$PLUGIN_DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
mkt = json.loads((root.parent / ".claude-plugin" / "marketplace.json").read_text())
bad = []
for p in mkt["plugins"]:
    spec = json.loads((root / p["name"] / ".claude-plugin" / "plugin.json").read_text())
    if spec["version"] != p["version"]:
        bad.append(f"{p['name']}: marketplace={p['version']} plugin={spec['version']}")
    if spec["name"] != p["name"]:
        bad.append(f"{p['name']}: name mismatch {spec['name']}")
print("\n".join(bad))
PY
)
TOTAL=$((TOTAL + 1))
if [ -z "$MISMATCH" ]; then
  echo "  PASS: marketplace.json and each plugin.json agree on name and version"
  PASS=$((PASS + 1))
else
  echo "  FAIL: $MISMATCH"
  FAIL=$((FAIL + 1))
fi

# Every hook that reads stdin must have a fallback. Catching this structurally
# stops a new hook from reintroducing the silent-failure shape.
TOTAL=$((TOTAL + 1))
UNGUARDED=$(python3 - "$PLUGIN_DIR" <<'PY'
import json, pathlib, sys
bad = []
for pj in sorted(pathlib.Path(sys.argv[1]).glob("*/.claude-plugin/plugin.json")):
    spec = json.loads(pj.read_text())
    for ev, entries in spec.get("hooks", {}).items():
        for i, e in enumerate(entries, 1):
            for h in e.get("hooks", []):
                c = h.get("command", "")
                if "jq " in c and "command -v jq" not in c:
                    bad.append(f"{spec['name']} {ev}#{i} uses jq with no availability check")
print("\n".join(bad))
PY
)
if [ -z "$UNGUARDED" ]; then
  echo "  PASS: no hook calls jq without checking that it exists"
  PASS=$((PASS + 1))
else
  echo "  FAIL: $UNGUARDED"
  FAIL=$((FAIL + 1))
fi

echo
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
