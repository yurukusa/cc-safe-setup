#!/bin/bash
# pre-bash-sed-line-ending-windows.sh — Block sed -i on Windows/Git Bash
#
# Solves: sed -i silently converts CRLF→LF on Windows (#63715).
#         The conversion is invisible in file content but breaks
#         tools expecting CRLF (XML manifests, .NET configs, batch
#         files). Reporter lost 4 hours debugging an XML parser
#         that failed silently after sed edited it.
#
# How it works: PreToolUse hook on Bash tool that detects sed -i
#   patterns on Windows/Git Bash environments and blocks the call
#   with a structured suggestion (Edit tool, PowerShell Set-Content,
#   or manual dos2unix/unix2dos preservation).
#
# Linux/macOS environments are skipped — sed -i is safe there.
#
# Override: Set CC_ALLOW_SED_LINE_ENDING_CHANGE=1 to bypass when
#   the LF conversion is intentional (e.g., converting a Windows
#   file to Unix line endings on purpose).
#
# TRIGGER: PreToolUse
# MATCHER: Bash

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$CMD" ] && exit 0

# Detect Windows/Git Bash environment. uname -s returns MINGW*/MSYS*/CYGWIN*
# on Git Bash, MSYS2, and Cygwin respectively. Linux/macOS are skipped because
# sed -i preserves the original LF line endings there.
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        ;;
    *)
        exit 0
        ;;
esac

# Match `sed -i`, `sed -i ''`, `sed --in-place`. Pattern allows leading flags
# like `sed -E -i` and ensures -i is a complete flag (not part of -inplace=...).
if echo "$CMD" | grep -qE '\bsed\b[^|;&]*[[:space:]]-(i\b|-in-place)'; then
    # Honor explicit opt-in for intentional LF conversion.
    if [ "${CC_ALLOW_SED_LINE_ENDING_CHANGE:-}" = "1" ]; then
        echo "[INFO] sed -i allowed via CC_ALLOW_SED_LINE_ENDING_CHANGE=1" >&2
        exit 0
    fi

    cat >&2 <<'EOF'
BLOCKED: sed -i on Windows/Git Bash silently converts CRLF to LF line endings.

This breaks files that expect CRLF (XML manifests, .NET configs, batch files,
.csproj, .vbproj, .sln, .reg files, etc.) without any warning or error. The
content looks identical in every visual inspection. Documented at
anthropics/claude-code#63715 with a 4-hour XML manifest debugging incident.

Use one of these instead:

1. The Edit tool — preserves the file's existing line endings.

2. PowerShell:
     (Get-Content file) -replace 'pattern','replacement' | Set-Content file
   Or with -NoNewline to avoid adding a trailing newline.

3. Manual line-ending preservation:
     dos2unix file && sed -i 's/old/new/g' file && unix2dos file

If you intentionally want to convert this file to LF, bypass with:
     CC_ALLOW_SED_LINE_ENDING_CHANGE=1 sed -i ...
EOF
    exit 2
fi

exit 0
