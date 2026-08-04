#!/bin/bash
# A hook that reads a field only one event delivers must be registered on that
# event. Fourteen example hooks were not.
#
# The installer derives the registration from this header: `# TRIGGER:` first,
# then two legacy comment forms, and PreToolUse / Bash when none are present.
# Fourteen files had no TRIGGER at all while their bodies read `.tool_response`
# (delivered only on PostToolUse) or the top-level `.prompt` (delivered only on
# UserPromptSubmit). Installing them put the hook at a moment where the field it
# reads is always empty — it installed, it appeared in the settings file, and it
# did nothing. Nothing errors, so nothing tells you. Measured 2026-08-04.
#
# This checks the invariant rather than the fourteen names, so the same mistake
# cannot come back in a new file.
#
# Deliberately narrow, and the narrowing is the point:
#   - `.tool_input.prompt` is the Task tool's argument on PreToolUse, not the
#     user's prompt. A first version of this check flagged all twelve
#     subagent-* hooks because of it.
#   - Only these two fields are checked. Other fields appear on several events
#     and cannot pin down a single correct registration.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "hook-registration-matches-input"

python3 - "$ROOT" <<'PYEOF'
import glob
import os
import re
import sys

root = sys.argv[1]
ALLOWED = {'PermissionRequest', 'PostToolUse', 'Notification', 'Stop',
           'SessionStart', 'PreCompact', 'SessionEnd', 'UserPromptSubmit',
           'CwdChanged', 'FileChanged'}


def derived(s):
    """Reproduce the installer's own resolution order."""
    m = re.search(r'^#\s*[Tt][Rr][Ii][Gg][Gg][Ee][Rr]:\s*(\S+)', s, re.M)
    if m and m.group(1) in ALLOWED:
        return m.group(1)
    if re.search(r'^#.*PermissionRequest hook', s, re.M):
        return 'PermissionRequest'
    if re.search(r'^#.*UserPromptSubmit hook', s, re.M):
        return 'UserPromptSubmit'
    return 'PreToolUse'


bad = []
checked = 0
for f in sorted(glob.glob(os.path.join(root, 'examples', '*.sh'))):
    s = open(f, encoding='utf-8', errors='replace').read()
    t = derived(s)
    reads_response = re.search(r'\.tool_response\b', s) is not None
    reads_prompt = (re.search(r'(?<!tool_input)(?<!_input)\.prompt\b', s) is not None
                    and not re.search(r'tool_input\.prompt', s))
    checked += 1
    if reads_response and t != 'PostToolUse':
        bad.append((f, t, '.tool_response', 'PostToolUse'))
    elif reads_prompt and not reads_response and t != 'UserPromptSubmit':
        bad.append((f, t, '.prompt', 'UserPromptSubmit'))

for f, got, field, want in bad:
    print(f'  FAIL {os.path.basename(f)}: reads {field} but registers as {got} '
          f'(needs {want})')

print(f'\nhook-registration-matches-input: {checked - len(bad)} passed, '
      f'{len(bad)} failed')
sys.exit(1 if bad else 0)
PYEOF
