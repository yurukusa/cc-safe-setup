#!/bin/bash
# polyglot-rm-guard.sh — Block file deletion via any language, not just rm
#
# Solves: Claude circumvents Bash(rm) deny rules by using Python os.remove(),
#         Node fs.unlinkSync(), or other languages to delete files (#39459).
#         The permission system blocks the tool, not the goal.
#
# How it works: PreToolUse hook on Bash that detects file deletion attempts
#   via Python, Node, Ruby, Perl, or any other interpreter — not just rm.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/polyglot-rm-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Python file deletion
if echo "$CMD" | grep -qE 'python[23]?\s+-c\s.*\b(os\.remove|os\.unlink|shutil\.rmtree|pathlib.*unlink)\b'; then
    echo "BLOCKED: File deletion via Python detected." >&2
    echo "Blocked: os.remove/unlink/rmtree circumvents rm restrictions." >&2
    exit 2
fi

# Node.js file deletion
if echo "$CMD" | grep -qE 'node\s+-e\s.*\b(unlinkSync|rmdirSync|rmSync|fs\.rm)\b'; then
    echo "BLOCKED: File deletion via Node.js detected." >&2
    exit 2
fi

# Ruby file deletion
if echo "$CMD" | grep -qE 'ruby\s+-e\s.*\b(File\.delete|FileUtils\.rm)\b'; then
    echo "BLOCKED: File deletion via Ruby detected." >&2
    exit 2
fi

# Perl file deletion
if echo "$CMD" | grep -qE 'perl\s+-[eE]\s.*\bunlink\b'; then
    echo "BLOCKED: File deletion via Perl detected." >&2
    exit 2
fi

# Generic: any interpreter with remove/delete/unlink in the command
if echo "$CMD" | grep -qE '(python|node|ruby|perl|php)\s+.*-[ceE]\s.*\b(remove|unlink|delete|rmtree|rmdir)\b'; then
    echo "BLOCKED: File deletion via interpreter detected." >&2
    exit 2
fi

exit 0
