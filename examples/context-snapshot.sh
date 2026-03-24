#!/bin/bash
# ================================================================
# context-snapshot.sh — Save session state before context loss
# ================================================================
# PURPOSE:
#   After /compact or when context is low, Claude loses track of
#   what files were being edited, which branch it's on, and what
#   the current task was. This hook saves a snapshot of the session
#   state after every Stop event, so the next message can recover.
#
# TRIGGER: Stop  MATCHER: ""
#
# Creates: .claude/session-snapshot.md (overwritten each time)
# ================================================================

SNAPSHOT=".claude/session-snapshot.md"
mkdir -p .claude 2>/dev/null

{
  echo "# Session Snapshot (auto-generated)"
  echo "Updated: $(date -Iseconds)"
  echo ""

  # Git state
  BRANCH=$(git branch --show-current 2>/dev/null)
  if [ -n "$BRANCH" ]; then
    echo "## Git"
    echo "- Branch: \`$BRANCH\`"
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    echo "- Uncommitted changes: $DIRTY file(s)"
    if [ "$DIRTY" -gt 0 ]; then
      echo '```'
      git status --short 2>/dev/null | head -15
      echo '```'
    fi
    echo "- Last commit: $(git log --oneline -1 2>/dev/null)"
    echo ""
  fi

  # Recently modified files
  echo "## Recent Files"
  echo '```'
  find . -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' \
    -o -name '*.java' -o -name '*.sh' -o -name '*.md' 2>/dev/null \
    | xargs ls -lt 2>/dev/null | head -10 | awk '{print $NF}'
  echo '```'
  echo ""

  # Active TODO/FIXME
  TODOS=$(grep -rl 'TODO\|FIXME' --include='*.js' --include='*.ts' --include='*.py' . 2>/dev/null | wc -l)
  if [ "$TODOS" -gt 0 ]; then
    echo "## Active TODOs: $TODOS file(s)"
    echo ""
  fi

} > "$SNAPSHOT" 2>/dev/null

exit 0
