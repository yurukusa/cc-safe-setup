#!/bin/bash
# dependency-install-guard.sh — PreToolUse hook
# Trigger: PreToolUse
# Matcher: Bash
#
# Blocks unintended dependency installations (npm install, pip install,
# gem install, cargo add, go get). Prevents:
# - Supply chain attacks from unknown packages
# - Dependency bloat from unnecessary installations
# - Breaking lockfiles with unplanned additions
#
# Allowed:
# - npm install (no args) — installs from existing lockfile
# - npm ci — clean install from lockfile
# - pip install -r requirements.txt — from requirements file
# - Packages in ALLOWLIST (customize below)
#
# Usage: Add to settings.json as a PreToolUse hook on "Bash"
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Normalize: collapse whitespace, extract first logical command
CMD=$(echo "$COMMAND" | tr '\n' ' ' | sed 's/  */ /g')

# --- Allowlist: packages you trust ---
# Customize this list for your project
ALLOWLIST="typescript|eslint|prettier|jest|vitest|@types/"

# npm install <package> — block unless allowlisted
if echo "$CMD" | grep -qiE 'npm\s+(install|i|add)\s+[a-z@]'; then
    PKG=$(echo "$CMD" | grep -oiE 'npm\s+(install|i|add)\s+\S+' | awk '{print $NF}')
    if echo "$PKG" | grep -qiE "^($ALLOWLIST)"; then
        exit 0
    fi
    echo "🚫 Blocked: npm install $PKG (not in allowlist)" >&2
    echo "Add to ALLOWLIST in dependency-install-guard.sh if intended." >&2
    exit 2
fi

# npm install (no args) / npm ci — allowed (uses lockfile)
if echo "$CMD" | grep -qiE 'npm\s+(install|i|ci)\s*($|[&|;])'; then
    exit 0
fi

# pip install <package> — block unless from requirements
if echo "$CMD" | grep -qiE 'pip3?\s+install\s+'; then
    # Allow: pip install -r requirements.txt
    if echo "$CMD" | grep -qiE 'pip3?\s+install\s+(-r|--requirement)\s+'; then
        exit 0
    fi
    # Allow: pip install -e . (editable install)
    if echo "$CMD" | grep -qiE 'pip3?\s+install\s+(-e|--editable)\s+'; then
        exit 0
    fi
    PKG=$(echo "$CMD" | grep -oiE 'pip3?\s+install\s+\S+' | awk '{print $NF}')
    echo "🚫 Blocked: pip install $PKG" >&2
    echo "Use 'pip install -r requirements.txt' or add to allowlist." >&2
    exit 2
fi

# gem install — block
if echo "$CMD" | grep -qiE 'gem\s+install\s+[a-z]'; then
    PKG=$(echo "$CMD" | grep -oiE 'gem\s+install\s+\S+' | awk '{print $NF}')
    echo "🚫 Blocked: gem install $PKG" >&2
    exit 2
fi

# cargo add — block
if echo "$CMD" | grep -qiE 'cargo\s+add\s+[a-z]'; then
    PKG=$(echo "$CMD" | grep -oiE 'cargo\s+add\s+\S+' | awk '{print $NF}')
    echo "🚫 Blocked: cargo add $PKG" >&2
    exit 2
fi

# go get — block
if echo "$CMD" | grep -qiE 'go\s+get\s+[a-z]'; then
    PKG=$(echo "$CMD" | grep -oiE 'go\s+get\s+\S+' | awk '{print $NF}')
    echo "🚫 Blocked: go get $PKG" >&2
    exit 2
fi

exit 0
