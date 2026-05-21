#!/usr/bin/env python3
"""
session-forensic-audit.py — Claude Code session forensic audit.

What this does: read-only scan of a Claude Code session JSONL file (or a
directory of sessions) and reports recognition-without-arrest patterns
observed in the model's text output that lack matching runtime evidence.

Three checks:

  1. Phantom agent dispatches. The assistant claims in text to have
     dispatched, sent to, processed via, or attributed work to a named
     agent, but no `Agent` (or `Task`) tool call to that agent appears in
     the same session. Maps to anthropics/claude-code#61167 (nvst18 health-
     care platform: 39 agents deployed, 5 ever used).

  2. Closure claims without verification. The assistant emits a closure
     word (done, complete, verified, fixed, shipped, saved, etc.) but no
     verification tool call (Bash, Read of the affected path, grep) is
     made in the same assistant turn. Maps to anthropics/claude-code#60226
     (suwayama, recognition-without-arrest).

  3. Read-before-edit ratio. Counts Read tool calls vs Edit/Write/MultiEdit
     tool calls. A low ratio is the #42796 read-before-edit drift pattern.

What this does NOT do: modify any file, run any tool call, send any network
request, or read any file outside the session JSONL you point it at. All
analysis is local and read-only.

Usage:
  session-forensic-audit.py <session.jsonl>
  session-forensic-audit.py <directory>      # audit every .jsonl in dir
  session-forensic-audit.py <path> --json    # machine-readable output
  session-forensic-audit.py <path> --check phantom|closure|read-edit

Safety: stdlib-only, no eval, no network. Tested on Python 3.10+.
License: MIT. Author: yurukusa (@yurukusa_dev).

Companion to:
  - cc-safe-setup (MIT) — https://github.com/yurukusa/cc-safe-setup
  - Claude Code Claim-Verify Handbook — https://yurukusa.gumroad.com/l/claim-verify-handbook
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Closure words that often appear in "done"-claims. The list is conservative:
# common, unambiguous claim verbs. Adding too many words inflates false positives.
CLOSURE_WORDS = [
    "完了", "完成", "確認済", "完了済",
    "done", "complete", "completed", "verified", "fixed", "shipped",
    "deployed", "saved", "applied", "merged", "implemented",
    "succeeded", "successful", "resolved", "ready",
]

# Verification tools — tool calls in the same turn count as evidence the
# assistant did the work it claimed.
VERIFICATION_TOOLS = {"Bash", "Read", "Grep", "Glob"}

# Agent dispatch tools
AGENT_TOOLS = {"Agent", "Task"}

# Edit tools
EDIT_TOOLS = {"Edit", "MultiEdit", "Write", "NotebookEdit"}

# Read tool
READ_TOOLS = {"Read"}


def parse_jsonl(path: Path):
    """Yield each JSON object from a JSONL file."""
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                yield lineno, json.loads(line)
            except json.JSONDecodeError:
                continue


def iter_assistant_turns(path: Path):
    """Yield (lineno, content_list) for each assistant message."""
    for lineno, obj in parse_jsonl(path):
        if obj.get("type") != "assistant":
            continue
        msg = obj.get("message", {})
        content = msg.get("content", [])
        if not isinstance(content, list):
            continue
        yield lineno, content


def extract_text_and_tools(content):
    """Return (concatenated_text, [tool_use_dicts])."""
    texts = []
    tools = []
    for c in content:
        if not isinstance(c, dict):
            continue
        t = c.get("type")
        if t == "text":
            texts.append(c.get("text", ""))
        elif t == "tool_use":
            tools.append(c)
    return "\n".join(texts), tools


def find_phantom_agents(path: Path):
    """
    Scan for phantom agent dispatches: text claims that mention an agent
    name with a dispatch verb, where no Agent tool call to that agent appears
    in the same session.
    """
    claimed_agents = Counter()
    actually_dispatched = Counter()

    # Patterns that signal a dispatch claim. Word-boundary anchored.
    # Example matches: "dispatched ZELDA", "sent to scribe", "agent CFO ran",
    # "via the LEX agent", "ZELDA produced", "CLINIC reviewed"
    DISPATCH_VERBS = (
        r"(?:dispatched|sent to|delegated to|via the|invoked|spawned|"
        r"agent\s+|ran via|attributed (?:to|via)|"
        r"のエージェント|に依頼|に処理させ|を発火|を呼び出)"
    )
    # Match dispatch_verb followed by a CAPITALIZED agent name (2+ uppercase chars).
    # Or "agent <name>" pattern.
    agent_name_pattern = re.compile(
        rf"{DISPATCH_VERBS}\s+([A-Z][A-Z0-9_-]{{1,30}})\b",
        re.IGNORECASE,
    )
    # Also catch: capitalized name followed by past-tense action verb
    name_then_action = re.compile(
        r"\b([A-Z][A-Z0-9_-]{2,30})\b\s+"
        r"(?:produced|reviewed|generated|completed|finished|"
        r"audited|analyzed|approved|signed off|processed|"
        r"が処理|が完成|が承認|が分析)"
    )

    for _, content in iter_assistant_turns(path):
        text, tools = extract_text_and_tools(content)
        for m in agent_name_pattern.finditer(text):
            name = m.group(1)
            if name.isupper() and len(name) >= 3:  # avoid noise like "I", "A"
                claimed_agents[name] += 1
        for m in name_then_action.finditer(text):
            name = m.group(1)
            if name.isupper() and len(name) >= 3:
                claimed_agents[name] += 1
        for tool in tools:
            if tool.get("name") in AGENT_TOOLS:
                inp = tool.get("input", {})
                # The agent name typically appears in subagent_type, agent, or as a token in description
                for key in ("subagent_type", "agent", "name"):
                    val = inp.get(key)
                    if isinstance(val, str):
                        actually_dispatched[val.upper()] += 1
                # Also check description for agent names
                desc = inp.get("description", "")
                if isinstance(desc, str):
                    for word in re.findall(r"\b[A-Z][A-Z0-9_-]{2,30}\b", desc):
                        actually_dispatched[word] += 1

    phantoms = []
    for name, count in claimed_agents.items():
        if actually_dispatched.get(name, 0) == 0:
            # Filter out common false positives (common acronyms, not agent names)
            if name in {"CC", "CLAUDE", "AI", "API", "URL", "HTTP", "JSON",
                       "HTML", "CSS", "JS", "PR", "CI", "MIT", "CDP", "MCP",
                       "TODO", "FIXME", "NOTE", "WARNING", "ERROR", "DEBUG",
                       "INFO", "TEST", "ID", "OS", "TZ", "UTC", "JST",
                       "ANTHROPIC", "OPENAI", "GITHUB", "GIST", "NPM",
                       "PDF", "MD", "PY", "JS", "SH", "TS", "CLI", "IDE",
                       "DSL", "REPL", "REST", "SQL", "SDK", "RFC", "DNS",
                       "TLS", "SSH", "GIT", "SSL", "TCP", "UDP", "IP",
                       "RAM", "CPU", "GPU", "WSL", "UI", "UX", "DB",
                       "ENV", "REPO", "PATH", "USER", "HOME"}:
                continue
            phantoms.append({"agent": name, "claim_count": count})
    return {
        "claimed_agents": dict(claimed_agents),
        "actually_dispatched": dict(actually_dispatched),
        "phantoms": sorted(phantoms, key=lambda x: -x["claim_count"]),
    }


def find_closure_without_verification(path: Path):
    """
    For each assistant turn, check whether closure words appear in text
    AND whether a verification tool call appears in the same turn.
    """
    closure_pattern = re.compile(
        r"\b(" + "|".join(re.escape(w) for w in CLOSURE_WORDS) + r")\b",
        re.IGNORECASE,
    )

    total_closure_turns = 0
    closure_with_verify = 0
    closure_without_verify = []

    for lineno, content in iter_assistant_turns(path):
        text, tools = extract_text_and_tools(content)
        closures = closure_pattern.findall(text)
        if not closures:
            continue
        total_closure_turns += 1
        tool_names = {t.get("name") for t in tools}
        if tool_names & VERIFICATION_TOOLS:
            closure_with_verify += 1
        else:
            closure_without_verify.append({
                "lineno": lineno,
                "closure_words": list(set(c.lower() for c in closures))[:5],
                "text_preview": text[:200].replace("\n", " "),
                "tool_names_in_turn": list(tool_names),
            })

    return {
        "total_closure_turns": total_closure_turns,
        "closure_with_verify": closure_with_verify,
        "closure_without_verify_count": len(closure_without_verify),
        "samples": closure_without_verify[:10],
    }


def read_edit_ratio(path: Path):
    """Compute Read vs Edit tool call counts. Low ratio = read-before-edit drift."""
    reads = 0
    edits = 0
    read_by_file = Counter()
    edit_by_file = Counter()
    for _, content in iter_assistant_turns(path):
        _, tools = extract_text_and_tools(content)
        for tool in tools:
            name = tool.get("name", "")
            inp = tool.get("input", {})
            path_value = inp.get("file_path") or inp.get("path") or ""
            if name in READ_TOOLS:
                reads += 1
                if path_value:
                    read_by_file[path_value] += 1
            elif name in EDIT_TOOLS:
                edits += 1
                if path_value:
                    edit_by_file[path_value] += 1

    edited_without_read = []
    for f, n in edit_by_file.items():
        if read_by_file.get(f, 0) == 0:
            edited_without_read.append({"file": f, "edit_count": n})

    return {
        "reads": reads,
        "edits": edits,
        "ratio": round(reads / edits, 2) if edits > 0 else None,
        "edited_without_read_count": len(edited_without_read),
        "edited_without_read_samples": sorted(
            edited_without_read, key=lambda x: -x["edit_count"]
        )[:10],
    }


def audit_session(path: Path, check: str):
    report = {"session": str(path)}
    if check in ("all", "phantom"):
        report["phantom_agents"] = find_phantom_agents(path)
    if check in ("all", "closure"):
        report["closure_without_verify"] = find_closure_without_verification(path)
    if check in ("all", "read-edit"):
        report["read_edit_ratio"] = read_edit_ratio(path)
    return report


def render_text(report):
    lines = []
    lines.append(f"=== {report['session']} ===")

    phantom = report.get("phantom_agents")
    if phantom is not None:
        lines.append("\n--- Phantom agent dispatches ---")
        ca = sum(phantom["claimed_agents"].values())
        ad = sum(phantom["actually_dispatched"].values())
        lines.append(f"Total agent name mentions in dispatch contexts: {ca}")
        lines.append(f"Total Agent/Task tool calls: {ad}")
        if phantom["phantoms"]:
            lines.append(f"\n⚠ PHANTOM CANDIDATES: {len(phantom['phantoms'])}")
            for p in phantom["phantoms"][:10]:
                lines.append(f"  - {p['agent']}: {p['claim_count']} claims, 0 dispatches")
        else:
            lines.append("(no phantom candidates detected)")

    closure = report.get("closure_without_verify")
    if closure is not None:
        lines.append("\n--- Closure claims without verification ---")
        lines.append(f"Total closure turns: {closure['total_closure_turns']}")
        lines.append(f"  with verification tool: {closure['closure_with_verify']}")
        lines.append(f"  without verification:   {closure['closure_without_verify_count']}")
        if closure["closure_without_verify_count"] > 0:
            ratio = closure["closure_without_verify_count"] / max(closure["total_closure_turns"], 1)
            lines.append(f"  unverified ratio: {ratio:.0%}")
            if ratio >= 0.3:
                lines.append("  ⚠ HIGH UNVERIFIED RATIO — recognition-without-arrest pattern")
            for s in closure["samples"][:5]:
                lines.append(f"    line {s['lineno']}: [{', '.join(s['closure_words'])}] {s['text_preview']}")

    re_ratio = report.get("read_edit_ratio")
    if re_ratio is not None:
        lines.append("\n--- Read-before-edit ratio ---")
        lines.append(f"Read calls:  {re_ratio['reads']}")
        lines.append(f"Edit calls:  {re_ratio['edits']}")
        if re_ratio["ratio"] is not None:
            ratio = re_ratio["ratio"]
            lines.append(f"Ratio (R/E): {ratio}")
            if ratio < 1.0:
                lines.append("  ⚠ LOW READ-BEFORE-EDIT — #42796 drift pattern")
        if re_ratio["edited_without_read_count"] > 0:
            lines.append(f"Files edited without Read: {re_ratio['edited_without_read_count']}")
            for s in re_ratio["edited_without_read_samples"][:5]:
                lines.append(f"  - {s['file']}: {s['edit_count']} edits, 0 reads")

    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="Session JSONL file or directory")
    ap.add_argument("--json", action="store_true", help="Machine-readable output")
    ap.add_argument("--check", default="all",
                    choices=["all", "phantom", "closure", "read-edit"],
                    help="Which check to run")
    args = ap.parse_args()

    p = Path(args.path)
    if not p.exists():
        raise SystemExit(f"path not found: {p}")

    if p.is_dir():
        sessions = sorted(p.glob("*.jsonl"))
        if not sessions:
            raise SystemExit(f"no .jsonl files in {p}")
    else:
        sessions = [p]

    reports = [audit_session(s, args.check) for s in sessions]

    if args.json:
        print(json.dumps({"reports": reports}, indent=2, ensure_ascii=False))
    else:
        for r in reports:
            print(render_text(r))
            print()


if __name__ == "__main__":
    main()
