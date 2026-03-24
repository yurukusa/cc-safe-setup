#!/usr/bin/env python3
"""Secret Leak Prevention — Python version.

Blocks git add .env, credential files, and git add . with .env present.

Usage in settings.json:
{
    "hooks": {
        "PreToolUse": [{
            "matcher": "Bash",
            "hooks": [{"type": "command", "command": "python3 /path/to/secret_guard.py"}]
        }]
    }
}
"""

import json
import os
import re
import sys

def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    command = data.get("tool_input", {}).get("command", "")
    if not command or not re.search(r'^\s*git\s+add', command):
        sys.exit(0)

    # Direct .env staging
    if re.search(r'git\s+add\s+.*\.env(\s|$|\.)', command, re.IGNORECASE):
        block(".env file staging — add to .gitignore instead")

    # Credential files
    patterns = [r'credentials', r'\.pem$', r'\.key$', r'\.p12$', r'id_rsa', r'id_ed25519']
    for p in patterns:
        if re.search(rf'git\s+add\s+.*{p}', command, re.IGNORECASE):
            block("Credential/key file — never commit these")

    # git add . with .env present
    if re.search(r'git\s+add\s+(-A|--all|\.)\s*$', command):
        if os.path.exists(".env") or os.path.exists(".env.local"):
            block("git add . with .env present — stage specific files instead")

    sys.exit(0)

def block(reason):
    print(f"BLOCKED: {reason}", file=sys.stderr)
    sys.exit(2)

if __name__ == "__main__":
    main()
