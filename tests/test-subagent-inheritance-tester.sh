#!/bin/bash
# Tests for subagent-inheritance-tester.sh — verifies that subagent
# frontmatter gaps (missing tools:, memory: misuse, missing name:,
# no frontmatter) are surfaced, and that parent Deny rules escalate
# the warning text for missing tool bindings.

HOOK="examples/subagent-inheritance-tester.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

TMPDIR=$(mktemp -d)
PROJ_DIR="$TMPDIR/project"
HOME_AGENTS="$TMPDIR/home/.claude/agents"
PROJ_AGENTS="$PROJ_DIR/.claude/agents"
mkdir -p "$HOME_AGENTS" "$PROJ_AGENTS"

# Run the hook with isolated $HOME and a synthetic project cwd.
run_hook() {
    local cwd="$1"
    local input
    input=$(jq -n --arg c "$cwd" '{cwd: $c}')
    printf '%s' "$input" | HOME="$TMPDIR/home" bash "$HOOK" 2>&1
}

# ---- Test 1: empty input + no agents → exit 0 silently ----
rm -rf "$TMPDIR/home/.claude/agents"
OUT=$(echo '{}' | HOME="$TMPDIR/home" bash "$HOOK" 2>&1)
RC=$?
assert_exit "no agents dir exits 0" "$RC" 0
assert_not_contains "no agents dir no output" "$OUT" "subagent-inheritance"
mkdir -p "$HOME_AGENTS"

# ---- Test 2: well-formed agent with tools: → no warning ----
cat > "$HOME_AGENTS/good.md" <<'EOF'
---
name: good-agent
description: Tightly scoped helper
tools: Read, Grep
model: sonnet
---
You are a focused helper.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "well-formed agent exits 0" "$RC" 0
assert_not_contains "well-formed agent no warning" "$OUT" "subagent-inheritance"

# ---- Test 3: agent without frontmatter → warning ----
cat > "$HOME_AGENTS/no-frontmatter.md" <<'EOF'
You are an agent without YAML frontmatter.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "no-frontmatter exits 0 (warn-only)" "$RC" 0
assert_contains "no-frontmatter warned" "$OUT" "no YAML frontmatter"

# ---- Test 4: agent missing tools: → warning ----
rm -f "$HOME_AGENTS/no-frontmatter.md"
cat > "$HOME_AGENTS/missing-tools.md" <<'EOF'
---
name: missing-tools
description: Agent with no explicit tools list
model: sonnet
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "missing-tools exits 0" "$RC" 0
assert_contains "missing-tools warned about default tool set" "$OUT" "no explicit 'tools:' list"

# ---- Test 5: agent with memory: field → warned about #57507 ----
cat > "$HOME_AGENTS/memory-only.md" <<'EOF'
---
name: memory-only
description: Author thought memory: would scope this agent
memory: scoped
tools: Read
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "memory-only exits 0" "$RC" 0
assert_contains "memory-only flagged" "$OUT" "57507"
assert_contains "memory-only mentions silently ignored" "$OUT" "silently ignored"
rm -f "$HOME_AGENTS/memory-only.md"

# ---- Test 6: agent missing name: → warning ----
cat > "$HOME_AGENTS/no-name.md" <<'EOF'
---
description: Missing required name key
tools: Read
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "no-name exits 0" "$RC" 0
assert_contains "no-name warned" "$OUT" "missing required 'name:'"
rm -f "$HOME_AGENTS/no-name.md"

# ---- Test 7: parent Deny rules escalate missing-tools warning ----
mkdir -p "$TMPDIR/home/.claude"
cat > "$TMPDIR/home/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "deny": ["Read(./.env)", "Read(./.env.*)"]
  }
}
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "deny-rules + missing tools exits 0" "$RC" 0
assert_contains "deny-rules escalation cites #57068" "$OUT" "57068"
assert_contains "deny-rules listed in output" "$OUT" "Read(./.env)"

# ---- Test 8: BLOCK=1 with issues → exit 2 ----
OUT=$(CC_SUBAGENT_INHERITANCE_BLOCK=1 run_hook "$PROJ_DIR")
RC=$?
assert_exit "block mode with issues exits 2" "$RC" 2
assert_contains "block mode still emits warning text" "$OUT" "subagent-inheritance"

# ---- Test 9: BLOCK=1 with no issues → exit 0 ----
rm -f "$HOME_AGENTS/missing-tools.md"
OUT=$(CC_SUBAGENT_INHERITANCE_BLOCK=1 run_hook "$PROJ_DIR")
RC=$?
assert_exit "block mode without issues exits 0" "$RC" 0
assert_not_contains "block mode no issues no warning" "$OUT" "subagent-inheritance"

# ---- Test 10: project-level .claude/agents/ scanned via cwd ----
cat > "$PROJ_AGENTS/proj-agent.md" <<'EOF'
---
name: proj-agent
description: Project agent with no tools
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "project agent dir exits 0" "$RC" 0
assert_contains "project agent dir scanned" "$OUT" "proj-agent.md"
rm -f "$PROJ_AGENTS/proj-agent.md"

# ---- Test 11: backup files (.bak) skipped ----
cat > "$HOME_AGENTS/old.md.bak" <<'EOF'
broken file
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "backup file skipped exits 0" "$RC" 0
assert_not_contains "backup file not warned" "$OUT" "old.md.bak"
rm -f "$HOME_AGENTS/old.md.bak"

# ---- Test 12: extra paths via env var ----
mkdir -p "$TMPDIR/extra"
cat > "$TMPDIR/extra/extra-agent.md" <<'EOF'
---
description: extra path agent missing name and tools
---
Body.
EOF
OUT=$(CC_SUBAGENT_INHERITANCE_PATHS="$TMPDIR/extra" run_hook "$PROJ_DIR")
RC=$?
assert_exit "extra path agent exits 0" "$RC" 0
assert_contains "extra path agent scanned" "$OUT" "extra-agent.md"

# ---- Test 13: real-world #57068 repro — Deny .env + agent w/o tools ----
cat > "$HOME_AGENTS/57068-repro.md" <<'EOF'
---
name: helpful
description: General helper
---
You may help with anything.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "#57068 repro exits 0" "$RC" 0
assert_contains "#57068 repro escalates with deny" "$OUT" "57068"
assert_contains "#57068 repro names the file" "$OUT" "57068-repro.md"
rm -f "$HOME_AGENTS/57068-repro.md"

# ---- Test 14: real-world #57507 repro — memory: present ----
cat > "$HOME_AGENTS/57507-repro.md" <<'EOF'
---
name: scoped
description: Author tried to bind via memory:
memory:
  scope: subagent-only
tools: Read
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "#57507 repro exits 0" "$RC" 0
assert_contains "#57507 repro flags memory:" "$OUT" "57507"
rm -f "$HOME_AGENTS/57507-repro.md"

# ---- Test 15: empty frontmatter block ----
printf -- '---\n---\nbody only\n' > "$HOME_AGENTS/empty-fm.md"
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "empty frontmatter exits 0" "$RC" 0
assert_contains "empty frontmatter warned" "$OUT" "empty-fm.md"
rm -f "$HOME_AGENTS/empty-fm.md"

# ---- Test 16: settings without deny → no escalation text ----
cat > "$TMPDIR/home/.claude/settings.json" <<'EOF'
{}
EOF
cat > "$HOME_AGENTS/missing-tools-2.md" <<'EOF'
---
name: ok-name
description: missing tools
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "no-deny + missing tools exits 0" "$RC" 0
assert_contains "no-deny still warns about default tool set" "$OUT" "Pin to least-privilege"
# Per-line warning should not escalate (no #57068 inline). Reference list
# at the bottom always cites both issues, so check only the issue line.
ISSUE_LINE=$(echo "$OUT" | grep "missing-tools-2.md" || true)
assert_not_contains "no-deny issue line does not cite #57068" "$ISSUE_LINE" "57068"
rm -f "$HOME_AGENTS/missing-tools-2.md"

# ---- Test 17: malformed JSON input → still scans HOME via $CLAUDE_PROJECT_DIR fallback ----
cat > "$HOME_AGENTS/needs-tools.md" <<'EOF'
---
name: needs-tools
description: missing tools
---
Body.
EOF
OUT=$(printf 'not-json' | HOME="$TMPDIR/home" bash "$HOOK" 2>&1)
RC=$?
assert_exit "non-json input exits 0" "$RC" 0
assert_contains "non-json input still scans home agents" "$OUT" "needs-tools.md"

# ---- Test 18: well-formed + tools list → no warning even with deny ----
rm -f "$HOME_AGENTS/needs-tools.md"
cat > "$TMPDIR/home/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "deny": ["Read(./.env)"]
  }
}
EOF
cat > "$HOME_AGENTS/scoped.md" <<'EOF'
---
name: scoped
description: properly scoped
tools: Read, Grep, Bash
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "scoped+deny exits 0" "$RC" 0
assert_not_contains "scoped+deny no warning" "$OUT" "subagent-inheritance"
rm -f "$HOME_AGENTS/scoped.md"
rm -f "$TMPDIR/home/.claude/settings.json"

# ---- Test 19: many agents, mixed states → each issue named ----
cat > "$HOME_AGENTS/good-1.md" <<'EOF'
---
name: g1
tools: Read
---
Body.
EOF
cat > "$HOME_AGENTS/bad-1.md" <<'EOF'
---
name: b1
description: missing tools
---
Body.
EOF
cat > "$HOME_AGENTS/bad-2.md" <<'EOF'
---
name: b2
memory: legacy
tools: Read
---
Body.
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "mixed agents exits 0" "$RC" 0
assert_contains "mixed agents flag bad-1" "$OUT" "bad-1.md"
assert_contains "mixed agents flag bad-2" "$OUT" "bad-2.md"
assert_not_contains "mixed agents skip good-1" "$OUT" "good-1.md"
rm -f "$HOME_AGENTS/good-1.md" "$HOME_AGENTS/bad-1.md" "$HOME_AGENTS/bad-2.md"

# ---- Test 20: Japanese description with English frontmatter keys ----
cat > "$HOME_AGENTS/jp.md" <<'EOF'
---
name: jp-agent
description: 日本語の説明 — tools 列が無い
---
本文
EOF
OUT=$(run_hook "$PROJ_DIR")
RC=$?
assert_exit "jp agent exits 0" "$RC" 0
assert_contains "jp agent flagged" "$OUT" "jp.md"

# Cleanup
rm -rf "$TMPDIR"

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && echo "OK" || exit 1
