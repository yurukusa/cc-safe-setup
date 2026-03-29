#!/bin/bash
# bashrc-safety-check.sh — Warn about .bashrc lines that hang in non-interactive shells
#
# Solves: Agent-spawned bash shells source user .bashrc/.bash_profile,
#         causing hangs or process cascades when completion scripts or
#         slow init commands run in non-interactive shells (#40354).
#
# How it works: SessionStart hook scans .bashrc for known-dangerous patterns
#   (completion scripts, nvm, conda, pyenv) and warns the user to add an
#   interactive-shell guard.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/bashrc-safety-check.sh" }]
#     }]
#   }
# }

BASHRC="$HOME/.bashrc"
[ ! -f "$BASHRC" ] && exit 0

# Check if .bashrc already has a non-interactive guard at the top
if head -10 "$BASHRC" | grep -qE 'case \$- in|\[\[ \$- ==.*i'; then
    # Already guarded — skip check
    exit 0
fi

# Patterns known to hang/crash in non-interactive agent shells
DANGEROUS_PATTERNS=(
    'source.*<.*completion'     # Angular CLI, kubectl, etc.
    'eval.*\$.*completion'      # Completion eval patterns
    'nvm\.sh'                   # nvm can be slow on init
    'conda.*activate'           # conda activation in non-interactive
    'pyenv.*init'               # pyenv init sometimes hangs
    'rbenv.*init'               # rbenv init
    'rvm.*scripts'              # rvm scripts
)

WARNINGS=""
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    MATCH=$(grep -n "$pattern" "$BASHRC" 2>/dev/null | head -3)
    if [ -n "$MATCH" ]; then
        WARNINGS="${WARNINGS}\n  Line: $MATCH"
    fi
done

if [ -n "$WARNINGS" ]; then
    echo "⚠ WARNING: .bashrc contains commands that may hang in agent subshells:" >&2
    echo -e "$WARNINGS" >&2
    echo "" >&2
    echo "Add this as the FIRST line of .bashrc to fix:" >&2
    echo '  case $- in *i*) ;; *) return;; esac' >&2
fi
exit 0
