#!/bin/bash
# Tests for dotenv-anthropic-key-billing-guard.sh

# 絶対パスにする。テスト20はcd後にhookを実行するため、相対パスだと解決できずfalse negativeになる
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/dotenv-anthropic-key-billing-guard.sh"
PASS=0 FAIL=0

# Use a unique tmpdir per test run
TMPROOT="$(mktemp -d -t cc-dotenv-ak-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

run_test() {
  local desc="$1" expected_exit="$2" envfile="$3" content="$4" extra_env="$5"
  local dir="$TMPROOT/$RANDOM-$RANDOM"
  mkdir -p "$dir"
  if [ -n "$envfile" ]; then
    printf '%s' "$content" > "$dir/$envfile"
  fi
  local logfile="$dir/log"
  local actual_exit
  if [ -n "$extra_env" ]; then
    env CLAUDE_PROJECT_DIR="$dir" CC_DOTENV_AK_LOG="$logfile" $extra_env bash "$HOOK" >/dev/null 2>/dev/null
  else
    env CLAUDE_PROJECT_DIR="$dir" CC_DOTENV_AK_LOG="$logfile" bash "$HOOK" >/dev/null 2>/dev/null
  fi
  actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing dotenv-anthropic-key-billing-guard.sh"
echo "=============================================="

# 1. No .env file at all — should pass silently
run_test "no .env files passes silently" 0 "" ""

# 2. .env without ANTHROPIC_API_KEY — pass
run_test ".env without ANTHROPIC_API_KEY passes" 0 ".env" "FOO=bar
DATABASE_URL=postgres://x"

# 3. .env with ANTHROPIC_API_KEY assigned a value — warn (exit 0 default)
run_test ".env with key (default warn) exits 0" 0 ".env" "ANTHROPIC_API_KEY=sk-ant-real-key"

# 4. .env with ANTHROPIC_API_KEY in block mode — exit 2
run_test ".env with key in block mode exits 2" 2 ".env" "ANTHROPIC_API_KEY=sk-ant-real-key" "CC_DOTENV_AK_ACTION=block"

# 5. .env with key inside quotes
run_test '.env with quoted key triggers warn' 0 ".env" 'ANTHROPIC_API_KEY="sk-ant-quoted"'

# 6. .env with key inside single-quotes
run_test ".env with single-quoted key triggers warn" 0 ".env" "ANTHROPIC_API_KEY='sk-ant-singlequoted'"

# 7. .env with export prefix
run_test ".env with export prefix triggers warn" 0 ".env" "export ANTHROPIC_API_KEY=sk-ant-exported"

# 8. .env with leading whitespace
run_test ".env with leading whitespace triggers warn" 0 ".env" "   ANTHROPIC_API_KEY=sk-ant-indented"

# 9. .env with commented-out key — should NOT trigger
run_test ".env with commented key passes silently" 0 ".env" "# ANTHROPIC_API_KEY=sk-ant-commented
FOO=bar"

# 10. .env with empty value (intentional override) — should NOT trigger
run_test ".env with empty key value passes" 0 ".env" "ANTHROPIC_API_KEY="

# 11. .env with empty quoted value — should NOT trigger
run_test '.env with empty quoted value passes' 0 ".env" 'ANTHROPIC_API_KEY=""'

# 12. .env.local with key — triggers
run_test ".env.local with key triggers warn" 0 ".env.local" "ANTHROPIC_API_KEY=sk-ant-local"

# 13. .env.production with key — triggers
run_test ".env.production with key triggers warn" 0 ".env.production" "ANTHROPIC_API_KEY=sk-ant-prod"

# 14. .env.development with key — triggers
run_test ".env.development with key triggers warn" 0 ".env.development" "ANTHROPIC_API_KEY=sk-ant-dev"

# 15. Unsupported file (.env.staging) ignored by default
run_test ".env.staging ignored by default" 0 ".env.staging" "ANTHROPIC_API_KEY=sk-ant-staging"

# 16. Custom CC_DOTENV_AK_FILES picks up .env.staging
run_test "custom file list picks up .env.staging" 0 ".env.staging" "ANTHROPIC_API_KEY=sk-ant-staging" "CC_DOTENV_AK_FILES=.env.staging"

# 17. Warn message goes to stderr
DIR="$TMPROOT/output-test"
mkdir -p "$DIR"
echo "ANTHROPIC_API_KEY=sk-ant-real" > "$DIR/.env"
OUTPUT=$(env CLAUDE_PROJECT_DIR="$DIR" bash "$HOOK" 2>&1 >/dev/null)
if echo "$OUTPUT" | grep -q "ANTHROPIC_API_KEY detected"; then
  echo "  PASS: warn message printed to stderr"
  PASS=$((PASS+1))
else
  echo "  FAIL: warn message missing from stderr"
  FAIL=$((FAIL+1))
fi

# 18. Stdout stays empty (so SessionStart payload is not corrupted)
DIR="$TMPROOT/stdout-test"
mkdir -p "$DIR"
echo "ANTHROPIC_API_KEY=sk-ant-real" > "$DIR/.env"
STDOUT=$(env CLAUDE_PROJECT_DIR="$DIR" bash "$HOOK" 2>/dev/null)
if [ -z "$STDOUT" ]; then
  echo "  PASS: stdout is empty"
  PASS=$((PASS+1))
else
  echo "  FAIL: stdout is non-empty: $STDOUT"
  FAIL=$((FAIL+1))
fi

# 19. Log file is created and contains the path
DIR="$TMPROOT/log-test"
mkdir -p "$DIR"
echo "ANTHROPIC_API_KEY=sk-ant-real" > "$DIR/.env"
LOG="$TMPROOT/test.log"
env CLAUDE_PROJECT_DIR="$DIR" CC_DOTENV_AK_LOG="$LOG" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$LOG" ] && grep -q "$DIR/.env" "$LOG"; then
  echo "  PASS: log file written"
  PASS=$((PASS+1))
else
  echo "  FAIL: log file missing or empty"
  FAIL=$((FAIL+1))
fi

# 20. Falls back to PWD when CLAUDE_PROJECT_DIR unset
DIR="$TMPROOT/pwd-test"
mkdir -p "$DIR"
echo "ANTHROPIC_API_KEY=sk-ant-real" > "$DIR/.env"
LOG="$DIR/log"
( cd "$DIR" && env -u CLAUDE_PROJECT_DIR CC_DOTENV_AK_LOG="$LOG" bash "$HOOK" >/dev/null 2>/dev/null )
if [ -f "$LOG" ] && grep -q "$DIR/.env" "$LOG"; then
  echo "  PASS: PWD fallback works when CLAUDE_PROJECT_DIR unset"
  PASS=$((PASS+1))
else
  echo "  FAIL: PWD fallback did not detect"
  FAIL=$((FAIL+1))
fi

# 21. Multiple .env files all detected (log has both lines)
DIR="$TMPROOT/multi-test"
mkdir -p "$DIR"
echo "ANTHROPIC_API_KEY=sk-ant-1" > "$DIR/.env"
echo "ANTHROPIC_API_KEY=sk-ant-2" > "$DIR/.env.local"
LOG="$DIR/log"
env CLAUDE_PROJECT_DIR="$DIR" CC_DOTENV_AK_LOG="$LOG" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$LOG" ] && [ "$(grep -c 'ANTHROPIC_API_KEY' "$LOG")" -eq 2 ]; then
  echo "  PASS: multiple .env files all logged"
  PASS=$((PASS+1))
else
  echo "  FAIL: multiple .env files not all logged (got $(wc -l < "$LOG" 2>/dev/null) lines)"
  FAIL=$((FAIL+1))
fi

echo "=============================================="
echo "Result: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
