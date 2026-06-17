#!/bin/bash
# edit-quote-ambiguity-guard.sh — Block an Edit that is ambiguous under the
#   tool's own quote-normalization, so it can't silently change the wrong line.
#
# Solves (#68962): the Edit tool normalizes typographic quotes when matching
# old_string (straight " ' are treated as equivalent to curly “ ” ‘ ’), but its
# uniqueness check counts occurrences of the RAW old_string, not the normalized
# form. When a file contains curly-quote variants, an old_string written with
# straight quotes can pass the uniqueness check yet correspond to MORE THAN ONE
# normalized-equivalent location — the tool then edits the wrong occurrence with
# no error. Verified on 2.1.179: with
#     message1 = ”hello“        (reversed curly, matches neither raw form)
#     message2 = “hello”
# an Edit using old_string '"hello"' (replace_all:false) silently rewrote
# message1 and even mutated its surrounding quote bytes — no ambiguity raised.
#
# This guard recomputes the uniqueness check the way the matcher does (over
# normalized content). It fires ONLY when normalization creates extra matches
# the raw count can't see (norm_count > raw_count AND norm_count >= 2) — i.e.
# exactly the silent-wrong-occurrence window. A plain duplicate (raw_count >= 2)
# is already rejected by the tool itself, so we stay silent there.
#
# Precision: BLOCK (exit 2). A silent wrong-line edit is not visible after the
# fact (that is the whole danger), so prevention beats a non-blocking warning.
# The fix is cheap: add surrounding context to old_string to make it unique, or
# set replace_all:true if every variant should change.
#
# TRIGGER: PreToolUse   MATCHER: "Edit|MultiEdit"

# Read the hook payload from stdin into an env var so the heredoc below can be
# Python's script on stdin without consuming the JSON.
HOOK_JSON=$(cat)
export HOOK_JSON

python3 <<'PY'
import os, sys, json

try:
    data = json.loads(os.environ.get("HOOK_JSON", ""))
except Exception:
    sys.exit(0)

ti = data.get("tool_input", {}) or {}

# MultiEdit carries a list of edits; Edit carries one. Normalize to a list.
edits = ti.get("edits")
if not isinstance(edits, list):
    edits = [ti]

fp = ti.get("file_path")
if not fp:
    sys.exit(0)

try:
    with open(fp, "r", encoding="utf-8", errors="replace") as fh:
        content = fh.read()
except Exception:
    sys.exit(0)

# Same equivalence relation the matcher uses: fold typographic quotes to ASCII.
DOUBLE = "“”„‟"   # “ ” „ ‟
SINGLE = "‘’‚‛"   # ‘ ’ ‚ ‛
TBL = {ord(c): '"' for c in DOUBLE}
TBL.update({ord(c): "'" for c in SINGLE})

def norm(s):
    return s.translate(TBL)

norm_content = norm(content)

for e in edits:
    old = e.get("old_string")
    if old is None or old == "":
        continue
    if e.get("replace_all"):
        continue
    raw_count = content.count(old)
    norm_count = norm_content.count(norm(old))
    # Silent-wrong-occurrence window: normalization reveals matches the raw
    # uniqueness check cannot see, and there is genuine ambiguity (>= 2).
    if norm_count > raw_count and norm_count >= 2:
        msg = (
            "BLOCKED (edit-quote-ambiguity-guard): this Edit's old_string is "
            "ambiguous under the Edit tool's quote-normalization.\n"
            f"  old_string matches {raw_count} exact occurrence(s) but "
            f"{norm_count} when straight/curly quotes (\" ' vs “ ” ‘ ’) "
            "are treated as equal.\n"
            "  The tool's uniqueness check counts only the raw form, so it can "
            "silently edit the WRONG occurrence (verified, #68962).\n"
            "  Fix: add surrounding context to old_string so it is unique in the "
            "file, or set replace_all:true if every variant should change."
        )
        sys.stderr.write(msg + "\n")
        sys.exit(2)

sys.exit(0)
PY
