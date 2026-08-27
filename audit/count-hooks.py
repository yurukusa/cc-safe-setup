#!/usr/bin/env python3
"""count-hooks.py — how many hook groups are actually registered, per scope.

Why this exists: the usual advice is to run `claude --print-settings`. That flag
does not exist (checked against the CLI's own --help on 2026-08-27); it exits 1
and prints usage. The settings that matter live in up to three files, and
Claude Code merges them. Counting only one of them under-reports.

Run it from your project directory.
"""
import collections
import json
import os

SCOPES = [
    ("user   ", os.path.expanduser("~/.claude/settings.json")),
    ("project", os.path.join(os.getcwd(), ".claude", "settings.json")),
    ("local  ", os.path.join(os.getcwd(), ".claude", "settings.local.json")),
]

total = collections.Counter()
for label, path in SCOPES:
    if not os.path.exists(path):
        print(f"  {label}  (no file)          {path}")
        continue
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception as exc:                      # a malformed file is a finding, not a crash
        print(f"  {label}  UNREADABLE: {exc}   {path}")
        continue
    hooks = data.get("hooks") or {}
    counts = {event: len(groups) for event, groups in hooks.items()}
    total.update(counts)
    print(f"  {label}  {counts if counts else 'no hooks'}")

print()
print("  merged :", dict(total))
print("  total  :", sum(total.values()), "hook groups")
print()
print("  A count above zero means they are registered.")
print("  It does not mean any of them fires. Use fire.sh for that.")
