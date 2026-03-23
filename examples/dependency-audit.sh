#!/bin/bash
# ================================================================
# dependency-audit.sh — Warn before installing unknown packages
# ================================================================
# PURPOSE:
#   Claude Code may install packages you've never heard of.
#   This hook warns when npm/pip/cargo installs a new dependency,
#   giving you a chance to review before it executes.
#
#   Doesn't block devDependencies or packages already in
#   package.json/requirements.txt.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHAT IT WARNS ON:
#   - npm install <pkg> (not in package.json)
#   - pip install <pkg> (not in requirements.txt)
#   - cargo add <pkg> (not in Cargo.toml)
#
# WHAT IT ALLOWS:
#   - npm install (no args = install from package.json)
#   - pip install -r requirements.txt
#   - Packages already in manifest files
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# npm install <package>
if echo "$COMMAND" | grep -qE '^\s*npm\s+install\s+\S'; then
    # Skip if no specific package (just `npm install`)
    PKG=$(echo "$COMMAND" | grep -oP 'npm\s+install\s+(-[DSg]\s+)*\K[^-\s]\S*' | head -1)
    if [[ -n "$PKG" ]] && [[ -f "package.json" ]]; then
        if ! grep -q "\"$PKG\"" package.json 2>/dev/null; then
            echo "NOTE: Installing new npm package: $PKG" >&2
            echo "Not found in package.json. Review before proceeding." >&2
        fi
    fi
fi

# pip install <package>
if echo "$COMMAND" | grep -qE '^\s*(pip3?|python3?\s+-m\s+pip)\s+install\s+\S'; then
    # Skip -r requirements.txt
    if ! echo "$COMMAND" | grep -qE '\-r\s+'; then
        PKG=$(echo "$COMMAND" | grep -oP '(pip3?|python3?\s+-m\s+pip)\s+install\s+(-[^\s]+\s+)*\K[^-\s]\S*' | head -1)
        if [[ -n "$PKG" ]] && [[ -f "requirements.txt" ]]; then
            if ! grep -qi "$PKG" requirements.txt 2>/dev/null; then
                echo "NOTE: Installing new pip package: $PKG" >&2
                echo "Not found in requirements.txt." >&2
            fi
        fi
    fi
fi

# cargo add <package>
if echo "$COMMAND" | grep -qE '^\s*cargo\s+add\s+\S'; then
    PKG=$(echo "$COMMAND" | grep -oP 'cargo\s+add\s+\K\S+' | head -1)
    if [[ -n "$PKG" ]] && [[ -f "Cargo.toml" ]]; then
        if ! grep -q "$PKG" Cargo.toml 2>/dev/null; then
            echo "NOTE: Adding new cargo dependency: $PKG" >&2
        fi
    fi
fi

exit 0
