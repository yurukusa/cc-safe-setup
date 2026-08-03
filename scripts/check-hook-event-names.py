#!/usr/bin/env python3
"""Validate the `# TRIGGER:` header of every example hook against the event names
Claude Code actually accepts.

Why this exists
---------------
An unknown key under `hooks` in settings.json is not an error. Claude Code does
not warn about it; the hook simply never runs. So a single mistyped event name
turns a shipped guard into a file that sits in the config looking installed and
protects nothing — the silent-failure shape this whole repo is about.

Users register hooks by copying the `# TRIGGER:` line out of the example, so a
wrong name in a header propagates straight into somebody's settings.json.
Nothing was checking those headers. On 2026-08-03 a sweep of all 909 examples
found 829 with a TRIGGER header, 12 distinct event names in use out of the 31
that exist, and two headers naming an event that does not exist at all (`Any`,
written as prose meaning "any event").

Run it
------
    python3 scripts/check-hook-event-names.py

Exit 1 and a list of offenders if anything does not match.

Keeping the list current
------------------------
EVENTS below is the roster as documented at https://code.claude.com/docs/en/hooks
on 2026-08-03. `claude doctor` prints the same set. When Claude Code adds an
event, add it here — a name missing from this list makes a correct hook fail the
check, which is the safe direction but still wrong.
"""
from __future__ import annotations

import os
import re
import sys

EVENTS = {
    "SessionStart", "Setup", "UserPromptSubmit", "UserPromptExpansion",
    "PreToolUse", "PermissionRequest", "PermissionDenied", "PostToolUse",
    "PostToolUseFailure", "PostToolBatch", "Notification", "MessageDisplay",
    "SubagentStart", "SubagentStop", "TaskCreated", "TaskCompleted", "Stop",
    "StopFailure", "TeammateIdle", "InstructionsLoaded", "ConfigChange",
    "CwdChanged", "DirectoryAdded", "FileChanged", "WorktreeCreate",
    "WorktreeRemove", "PreCompact", "PostCompact", "Elicitation",
    "ElicitationResult", "SessionEnd",
}

# A handful of examples wrap another hook rather than being registered on their
# own. They have no event of their own, and writing prose in the slot only moves
# the guesswork into the reader. `none` says it explicitly and keeps the check
# meaningful for every other file.
NO_EVENT_OF_ITS_OWN = {"none"}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXAMPLES = os.path.join(ROOT, "examples")

TRIGGER_RE = re.compile(r"^#\s*TRIGGER:\s*(.+?)\s*$", re.M)


def names_in(header: str) -> list[str]:
    """Pull the event names out of a TRIGGER header.

    Headers carry prose alongside the names — a MATCHER on the same line, a
    parenthetical, an em dash. Strip those first, then split on the separators
    the headers actually use.
    """
    s = re.sub(r"MATCHER:.*$", "", header)
    s = re.sub(r"\([^)]*\)", "", s)
    s = re.sub(r"[—–-]{1,2}\s.*$", "", s)
    parts = re.split(r"[,+/]|\bor\b|\bAND\b|\band\b", s)
    return [p.strip().strip('`"\'') for p in parts if p.strip()]


def main() -> int:
    bad: list[tuple[str, str, str]] = []
    unparsed: list[str] = []
    checked = 0
    used: set[str] = set()

    for fn in sorted(os.listdir(EXAMPLES)):
        if not fn.endswith(".sh"):
            continue
        path = os.path.join(EXAMPLES, fn)
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        m = TRIGGER_RE.search(text)
        if not m:
            continue
        checked += 1
        header = m.group(1)
        if header.count("(") != header.count(")"):
            unparsed.append(fn)
        for name in names_in(header):
            if not name:
                continue
            if name.lower() in NO_EVENT_OF_ITS_OWN:
                continue
            used.add(name)
            if name not in EVENTS:
                bad.append((fn, name, header))

    print("examples with a TRIGGER header: %d" % checked)
    print("event names in use: %d of %d" % (len(used & EVENTS), len(EVENTS)))

    if unparsed:
        print()
        print("Unbalanced parentheses in the TRIGGER header (%d):" % len(unparsed))
        for fn in unparsed:
            print("  %s" % fn)

    if bad:
        print()
        print("Event names Claude Code does not accept (%d):" % len(bad))
        for fn, name, header in bad:
            print("  %-46s %r" % (fn, name))
            print("  %-46s in: %s" % ("", header))
        print()
        print("An unknown event key is ignored without a warning, so a hook")
        print("registered under one never runs. Fix the header, or add the name to")
        print("EVENTS in this script if Claude Code has since added it.")

    return 1 if (bad or unparsed) else 0


if __name__ == "__main__":
    sys.exit(main())
