#!/usr/bin/env python3
"""Destructive Command Guard — Python version.

Blocks rm -rf on sensitive paths, git reset --hard, git clean -fd,
PowerShell Remove-Item, and sudo with dangerous commands.

Usage in settings.json:
{
    "hooks": {
        "PreToolUse": [{
            "matcher": "Bash",
            "hooks": [{"type": "command", "command": "python3 /path/to/destructive_guard.py"}]
        }]
    }
}
"""

import json
import re
import sys

def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    command = data.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    # rm -rf on sensitive paths
    if re.search(r'rm\s+(-[rf]+\s+)*(\/|~|\.\.\/)', command):
        safe_dirs = {"node_modules", "dist", "build", ".cache", "__pycache__", "coverage"}
        if not any(command.rstrip().endswith(d) for d in safe_dirs):
            block("rm on sensitive path detected")

    # git reset --hard
    if re.search(r'(^|;|&&)\s*git\s+reset\s+--hard', command):
        block("git reset --hard discards all uncommitted changes")

    # git clean -fd
    if re.search(r'(^|;|&&)\s*git\s+clean\s+-[a-z]*[fd]', command):
        block("git clean removes untracked files permanently")

    # git checkout/switch --force
    if re.search(r'(^|;|&&)\s*git\s+(checkout|switch)\s+.*(--force|-f\b)', command):
        block("git checkout --force discards uncommitted changes")

    # PowerShell destructive
    if re.search(r'Remove-Item.*-Recurse.*-Force|rd\s+/s\s+/q', command, re.IGNORECASE):
        block("Destructive PowerShell command detected")

    # sudo with dangerous commands
    if re.search(r'^\s*sudo\s+(rm\s+-[rf]|chmod\s+(-R\s+)?777|dd\s+if=|mkfs)', command):
        block("sudo with dangerous command detected")

    sys.exit(0)

def block(reason):
    print(f"BLOCKED: {reason}", file=sys.stderr)
    sys.exit(2)

if __name__ == "__main__":
    main()
