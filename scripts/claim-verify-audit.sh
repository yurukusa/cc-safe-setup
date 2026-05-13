#!/usr/bin/env bash
# claim-verify-audit.sh — Diagnostic one-shot audit for Claude Code claim/reality divergence patterns
#
# What this does: read-only scan of your Claude Code configuration and reports
# known risk patterns observed in May 2026 GitHub issues. Reports severity,
# evidence, and the issue number + book chapter where the structural pattern
# and prevention defense are documented.
#
# What this does NOT do: modify any file, run any tool call, send any network
# request, or read any file outside ~/.claude/, ~/.cache/claude-cli-nodejs/,
# %AppData%/Claude/ (Windows), or the directory you run it from. All checks
# are local and read-only.
#
# Safety: bash strict mode, no eval of config content, all reads use grep/jq.
# License: MIT. Author: yurukusa (@yurukusa_dev).
#
# Companion to:
# - Claude Code Claim-Verify Handbook (Edition 1, ships 2026-05-22)
#   https://yurukusa.gumroad.com/l/claim-verify-handbook
# - cc-safe-setup (MIT, ~730 PreToolUse/PostToolUse hooks)
#   https://github.com/yurukusa/cc-safe-setup
#
# Usage: bash claim-verify-audit.sh
# Tested: bash 4+, macOS 14+, Ubuntu 22.04+, WSL2.

set -uo pipefail

# Parse args (single optional flag: --json for machine-readable output)
JSON_MODE=0
case "${1:-}" in
    --json) JSON_MODE=1 ;;
    -h|--help)
        cat <<'USAGE'
claim-verify-audit.sh — Diagnostic for Claude Code claim/reality divergence patterns

Usage:
  bash claim-verify-audit.sh             # human-readable text output
  bash claim-verify-audit.sh --json      # machine-readable JSON (for CI integration)

Exit codes:
  0 — no HIGH-severity findings
  1 — one or more HIGH-severity findings

Read-only, MIT, no network access, runs in ~1 second.
USAGE
        exit 0
        ;;
esac

# Severity counts
HIGH=0
MED=0
LOW=0
INFO=0

# JSON findings buffer (lines of pre-escaped JSON)
JSON_FINDINGS=""

# Color codes (respect NO_COLOR + JSON mode)
if (( JSON_MODE )) || [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    R="" Y="" B="" G="" N=""
else
    R=$'\033[31m' Y=$'\033[33m' B=$'\033[34m' G=$'\033[32m' N=$'\033[0m'
fi

# JSON escape for string values (handles backslash, quote, newline, tab)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

report() {
    local sev="$1" title="$2" detail="$3" fix="$4"
    case "$sev" in
        HIGH)   HIGH=$((HIGH+1)) ;;
        MEDIUM) MED=$((MED+1)) ;;
        LOW)    LOW=$((LOW+1)) ;;
        INFO)   INFO=$((INFO+1)) ;;
    esac
    if (( JSON_MODE )); then
        # Append JSON object for this finding
        local obj="{\"severity\":\"$sev\",\"title\":\"$(json_escape "$title")\",\"detail\":\"$(json_escape "$detail")\",\"fix\":\"$(json_escape "$fix")\"}"
        if [[ -z "$JSON_FINDINGS" ]]; then
            JSON_FINDINGS="$obj"
        else
            JSON_FINDINGS="$JSON_FINDINGS,$obj"
        fi
    else
        case "$sev" in
            HIGH)   echo "${R}[HIGH]${N}    $title" ;;
            MEDIUM) echo "${Y}[MEDIUM]${N}  $title" ;;
            LOW)    echo "${B}[LOW]${N}     $title" ;;
            INFO)   echo "${G}[INFO]${N}    $title" ;;
        esac
        [[ -n "$detail" ]] && echo "          $detail"
        [[ -n "$fix" ]] && echo "          Fix: $fix"
        echo
    fi
}

section() {
    if (( JSON_MODE )); then
        return  # sections are suppressed in JSON mode
    fi
    echo
    echo "=== $1 ==="
    echo
}

# ============================================================
# Header
# ============================================================
if (( JSON_MODE == 0 )); then
    cat <<'HEADER'

Claude Code Claim-Verify Audit
==============================
Read-only scan for known May 2026 failure-mode patterns.
Each finding cites the source GitHub issue and the book chapter
where the structural pattern + prevention defense are documented.

HEADER
fi

# ============================================================
# Platform detection
# ============================================================
OS="unknown"
case "$(uname -s)" in
    Linux*)   OS="linux"; [[ -d /mnt/c/Users ]] && OS="wsl" ;;
    Darwin*)  OS="macos" ;;
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac

USERNAME="${USER:-$(whoami 2>/dev/null || echo unknown)}"
# Under WSL, $USER is the Linux distro account, not the Windows profile that owns
# the C:\Users\... 8.3 short path issue #58614 actually triggers from. Derive the
# Windows username from /mnt/c/Users/, skipping system pseudo-accounts (Default,
# Public, ".NET v4.5", etc.) and accepting only profiles that contain a real
# AppData subdirectory.
WIN_USERNAME=""
if [[ "$(uname -s)" == Linux* ]] && [[ -d /mnt/c/Users ]]; then
    while IFS= read -r d; do
        name="$(basename "$d")"
        case "$name" in
            .*|Default|Default*|Public|"All Users"|desktop.ini) continue ;;
        esac
        # Real user profiles have AppData; system pseudo-accounts don't.
        if [[ -d "$d/AppData" ]]; then
            WIN_USERNAME="$name"
            break
        fi
    done < <(find /mnt/c/Users -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CACHE_DIR="${HOME}/.cache/claude-cli-nodejs"

if (( JSON_MODE == 0 )); then
    echo "Platform: $OS"
    echo "User: $USERNAME"
    echo "Claude dir: $CLAUDE_DIR"
    echo
fi

# ============================================================
# Check 1 — Settings file presence and JSON validity (issue #57491 family)
# ============================================================
section "Check 1: settings.json validity"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    report INFO "settings.json not found" \
        "Path: $SETTINGS_FILE" \
        "If you've never configured Claude Code, this is expected."
else
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$SETTINGS_FILE" 2>/dev/null; then
            report INFO "settings.json parses as valid JSON" \
                "Size: $(wc -c < "$SETTINGS_FILE") bytes" ""
        else
            report HIGH "settings.json has invalid JSON syntax" \
                "Path: $SETTINGS_FILE — Claude Code may silently fall back to defaults without warning you." \
                "Run jq . on the file to find the syntax error. See issue #57491 (settings silent fallback)."
        fi
    else
        report LOW "jq not installed — skipping JSON validation" \
            "Install jq for stronger checks (apt-get install jq / brew install jq)." \
            ""
    fi
fi

# ============================================================
# Check 2 — Windows 8.3 short-name allow-rule bypass (issue #58614)
# ============================================================
section "Check 2: Windows 8.3 short-name allow-rule bypass"

if [[ "$OS" == "windows" ]] || [[ "$OS" == "wsl" ]]; then
    # Under WSL, the relevant username is the Windows profile owner, not the
    # Linux distro account. Issue #58614 triggers when the Windows profile path
    # contains non-ASCII chars and therefore gets an 8.3 short name.
    CHECK_NAME="$USERNAME"
    NAME_SOURCE="Linux user"
    if [[ "$OS" == "wsl" ]] && [[ -n "$WIN_USERNAME" ]]; then
        CHECK_NAME="$WIN_USERNAME"
        NAME_SOURCE="Windows profile under /mnt/c/Users"
    fi
    if [[ "$CHECK_NAME" =~ [^[:ascii:]] ]] || [[ "$CHECK_NAME" =~ [äöüåéÄÖÜÅÉàèìòùÀÈÌÒÙ] ]]; then
        report HIGH "Windows username contains non-ASCII character — 8.3 scanner will bypass allow-rules" \
            "Username ($CHECK_NAME, source: $NAME_SOURCE) generates an 8.3 short name (e.g. ${CHECK_NAME:0:6}~1). Claude Code's path-pattern scanner runs above the permission/allow-list layer and forces manual approval on every Read/Write touching paths in that account, even when settings.json has an explicit allow rule." \
            "Issue #58614 — book Chapter 5 (silent override) extends to allow-rule site. Workarounds (none clean): rename Windows account / move %TEMP% to ASCII path / disable 8.3 generation system-wide. Track vendor fix: https://github.com/anthropics/claude-code/issues/58614"
    else
        report INFO "Windows username is ASCII-clean — 8.3 short-name scanner won't trigger on you" \
            "Checked: $CHECK_NAME (source: $NAME_SOURCE)" \
            ""
    fi
else
    report INFO "Not on Windows — issue #58614 (8.3 short-name) does not apply" \
        "Platform: $OS" \
        ""
fi

# ============================================================
# Check 3 — Skill bloat / per-session token tax (Reddit 1tbbove)
# ============================================================
section "Check 3: skill bloat per-session token cost"

SKILLS_DIR="${CLAUDE_DIR}/skills"
if [[ -d "$SKILLS_DIR" ]]; then
    SKILL_COUNT=$(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    # Per-skill descriptor estimate calibrated against:
    # - Reporter 1tbbove's measurement: 2,596 skills → 102K tokens (~40 tokens/skill avg)
    # - Dogfooding measurement via eliransu/skill-tax against this author's install:
    #   97 skills → 6,031 tokens (~62 tokens/skill avg, tiktoken cl100k_base)
    # Conservative estimate at 80 tokens/skill captures verbose-metadata installs.
    # For accurate per-skill measurement, use eliransu/skill-tax (tiktoken-based).
    EST_TOKENS=$((SKILL_COUNT * 80))

    if (( EST_TOKENS > 30000 )); then
        report HIGH "$SKILL_COUNT skills installed — heavy per-session token tax (~${EST_TOKENS} tokens estimated)" \
            "Every installed skill loads its descriptor into every session regardless of invocation. Reporter 1tbbove measured ~\$91/month at 2,596 skills with 102K tokens/session. Your estimated cost at typical Pro usage: ~\$$(( EST_TOKENS / 1100 ))/month. For accurate measurement use eliransu/skill-tax." \
            "Use eliransu/skill-tax (https://github.com/eliransu/skill-tax) for per-skill cost measurement and pruning. See book §1tbbove."
    elif (( EST_TOKENS > 10000 )); then
        report MEDIUM "$SKILL_COUNT skills installed — moderate per-session token tax (~${EST_TOKENS} tokens estimated)" \
            "Review which skills you actually invoke. For accurate measurement use eliransu/skill-tax." \
            "Run eliransu/skill-tax report to identify never-invoked skills."
    elif (( EST_TOKENS > 3000 )); then
        report LOW "$SKILL_COUNT skills installed — minor per-session token tax (~${EST_TOKENS} tokens estimated)" \
            "Worth a periodic audit if invocation rate is low. eliransu/skill-tax gives accurate per-skill costs." \
            ""
    else
        report INFO "$SKILL_COUNT skills installed — token tax is negligible (~${EST_TOKENS} tokens estimated)" \
            "" \
            ""
    fi
else
    report INFO "No skills directory — skill bloat not applicable" \
        "Path: $SKILLS_DIR" \
        ""
fi

# ============================================================
# Check 4 — Session backup state (issue #58608)
# ============================================================
section "Check 4: session backup against silent deletion"

PROJECTS_DIR="${CLAUDE_DIR}/projects"
if [[ -d "$PROJECTS_DIR" ]]; then
    SESSION_COUNT=$(find "$PROJECTS_DIR" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
    NEWEST=$(find "$PROJECTS_DIR" -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')

    if (( SESSION_COUNT == 0 )); then
        report MEDIUM "No .jsonl session files found under projects/" \
            "If you have used Claude Code, sessions may have been silently deleted (see #58608 — Windows background-update wiped session storage)." \
            "If you have an Electron cache, check it for old paths that prove sessions existed. Book Chapter 3 + defense #5."
    else
        report INFO "$SESSION_COUNT session .jsonl files present" \
            "Newest: $NEWEST" \
            ""

        # Check for any backup mechanism — accept either ~/.claude/backups or
        # ~/.claude/session-backups (the latter is what this repo's own
        # examples/session-backup-on-start.sh writes to per COOKBOOK.md).
        BACKUP_FILE_COUNT=0
        FOUND_BACKUP_DIR=""
        for cand in "${CLAUDE_DIR}/backups" "${CLAUDE_DIR}/session-backups"; do
            if [[ -d "$cand" ]]; then
                cand_count=$(find "$cand" -type f 2>/dev/null | wc -l | tr -d ' ')
                if (( cand_count > 0 )); then
                    BACKUP_FILE_COUNT=$((BACKUP_FILE_COUNT + cand_count))
                    FOUND_BACKUP_DIR="${FOUND_BACKUP_DIR:+$FOUND_BACKUP_DIR, }$cand ($cand_count file(s))"
                fi
            fi
        done

        if (( BACKUP_FILE_COUNT == 0 )); then
            report MEDIUM "No session backups present — protection against silent deletion is absent" \
                "Issues #58608 (Windows auto-update), #57453 (session jsonl silent deletion), #58361 (transcript silent overwrite) all result in unrecoverable session loss. Without an off-system backup, weeks of conversation context can vanish without warning. Checked: ${CLAUDE_DIR}/backups and ${CLAUDE_DIR}/session-backups (the latter is where this repo's session-backup-on-start.sh writes)." \
                "Install cc-safe-setup's session-backup-on-start.sh (writes to ~/.claude/session-backups) or set up rsync/restic. Book defense #5 + Chapter 3."
        else
            report INFO "Backup directory has $BACKUP_FILE_COUNT file(s)" \
                "Found: $FOUND_BACKUP_DIR" \
                ""
        fi
    fi
else
    report INFO "No projects directory — session backup check not applicable" \
        "Path: $PROJECTS_DIR" \
        ""
fi

# ============================================================
# Check 5 — Sub-agent .env inheritance (issue #57068)
# ============================================================
section "Check 5: sub-agent .env protection inheritance"

# First: classify what's present in cwd. The cwd .env risk is independent of
# whether ~/.claude/settings.json exists or jq is installed — if settings is
# missing/unparseable, the user definitely has no deny rules, which is the
# worst case and must still surface a HIGH warning.
ENV_IN_CWD=0
if [[ -f .env ]] || ls .env.* >/dev/null 2>&1; then
    ENV_IN_CWD=1
fi

DENY_ENV=0
SETTINGS_USABLE=0
if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1 && jq empty "$SETTINGS_FILE" >/dev/null 2>&1; then
    SETTINGS_USABLE=1
    DENY_ENV=$(jq -r '.permissions.deny // [] | map(select(. | tostring | test("\\.env|credentials|secrets"; "i"))) | length' "$SETTINGS_FILE" 2>/dev/null || echo 0)
fi

if (( DENY_ENV > 0 )); then
    # Settings has deny rules — check sub-agent inheritance
    AGENT_COUNT=0
    [[ -d "${CLAUDE_DIR}/agents" ]] && AGENT_COUNT=$(find "${CLAUDE_DIR}/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

    if (( AGENT_COUNT > 0 )); then
        report MEDIUM "Parent has $DENY_ENV .env-related deny rules + $AGENT_COUNT sub-agents — verify inheritance" \
            "Issue #57068: sub-agents do not inherit parent's .env deny rules by default. The parent's allow-list propagates, but the deny-list does not. Your sub-agents may be able to read .env files even though your parent settings deny it." \
            "Add an explicit PreToolUse hook that blocks Read/Edit/Write against .env paths in the sub-agent dispatch chain. cc-safe-setup ships credential-exfil-guard.sh for this. Book Chapter 4 + defense #10."
    else
        report INFO ".env deny rules present + no sub-agents defined" \
            "Deny rules: $DENY_ENV / Sub-agents: 0" \
            ""
    fi
elif (( ENV_IN_CWD )); then
    # No deny rules (settings missing, unparseable, or simply has none) but
    # .env present in cwd. This is the worst case — always HIGH.
    if (( SETTINGS_USABLE )); then
        reason="Your settings.json does not deny Read/Edit/Write on .env files."
    elif [[ ! -f "$SETTINGS_FILE" ]]; then
        reason="No ~/.claude/settings.json — no deny rules anywhere."
    elif ! command -v jq >/dev/null 2>&1; then
        reason="jq not installed — could not parse settings.json to verify deny rules. Assuming no protection."
    else
        reason="~/.claude/settings.json failed to parse — cannot rely on any deny rule in it."
    fi
    report HIGH "Found .env file in current directory but NO usable deny rules" \
        "$reason Claude Code or its sub-agents may read your credentials into a transcript. Issue #58173 reports leaks of GitHub PAT, Vercel token, Slack bot token, Supabase service key, Anthropic API key, Brave search key from this exact pattern." \
        "Add to settings.json: \"permissions\": {\"deny\": [\"Read(./.env)\", \"Edit(./.env)\", \"Write(./.env)\"]}. Then test that sub-agents respect it (see #57068). Book Chapter 4 + defense #10."
else
    report INFO "No .env in cwd, no .env deny rules needed — clean state" \
        "" \
        ""
fi

# ============================================================
# Check 6 — Auto-compact configuration drift (issues #57490, #58373)
# ============================================================
section "Check 6: auto-compact configuration drift"

if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    AUTOCOMPACT=$(jq -r '.autoCompact // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [[ "$AUTOCOMPACT" == "false" ]]; then
        report MEDIUM "autoCompact set to false in settings.json — verify it actually holds at runtime" \
            "Issue #57490 reports auto-compaction firing despite explicit disable in /config. Issue #58373 reports the inverse: /goal-bounded long work fails to trigger auto-compact even when it should. The display state and runtime state diverge in both directions." \
            "Add a SessionStart hook that captures the /context state and a Stop hook that compares post-session. See book Chapter 5 + defense #11 (context snapshot)."
    fi
fi

# ============================================================
# Check 7 — bypassPermissions remote override (issue #57810)
# ============================================================
section "Check 7: bypassPermissions remote override"

if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    BYPASS=$(jq -r '.permissions.defaultMode // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [[ "$BYPASS" == "bypassPermissions" ]]; then
        report LOW "permissions.defaultMode set to bypassPermissions" \
            "Issue #57810: in claude.ai/code remote sessions, this setting is silently ignored and approval prompts continue to fire. Your local setting may not transfer when you start a remote session." \
            "Re-confirm permissions behavior in any remote session you start. Book Chapter 5 + defense #13."
    fi
fi

# ============================================================
# Check 8 — Cache directory references to deleted storage (issue #58608 evidence trail)
# ============================================================
section "Check 8: forensic — cache references to deleted storage"

if [[ -d "$CACHE_DIR" ]]; then
    SUSPICIOUS=$(find "$CACHE_DIR" -name "*local-agent-mode-sessions*" 2>/dev/null | head -3 | wc -l | tr -d ' ')
    if (( SUSPICIOUS > 0 )); then
        report MEDIUM "Cache contains references to legacy session storage paths" \
            "Found $SUSPICIOUS folders matching legacy 'local-agent-mode-sessions' path. Per issue #58608, this is the forensic trail of session data that existed under the legacy path. If your projects/ directory is also empty, you may have experienced a silent migration loss." \
            "Compare current session count (Check 4 above) against the cache folder dates. If sessions are gone but cache references remain, file or +1 #58608."
    else
        report INFO "Cache directory has no legacy-storage references" \
            "Path: $CACHE_DIR" \
            ""
    fi
fi

# ============================================================
# Summary
# ============================================================
TOTAL_FINDINGS=$((HIGH + MED + LOW))

if (( JSON_MODE )); then
    # Emit single JSON object to stdout
    TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"schema":"claim-verify-audit/v1","timestamp":"%s","platform":"%s","user":"%s","claude_dir":"%s","summary":{"high":%d,"medium":%d,"low":%d,"info":%d},"findings":[%s]}\n' \
        "$TIMESTAMP" "$OS" "$(json_escape "$USERNAME")" "$(json_escape "$CLAUDE_DIR")" \
        "$HIGH" "$MED" "$LOW" "$INFO" "$JSON_FINDINGS"
else
    section "Audit Summary"
    echo "Findings: ${R}${HIGH} HIGH${N}  ${Y}${MED} MEDIUM${N}  ${B}${LOW} LOW${N}  ${G}${INFO} INFO${N}"
    echo

    if (( HIGH > 0 )); then
        echo "${R}Action required${N}: $HIGH high-severity finding(s) above. Each cites the source issue and the book chapter for structural prevention."
    elif (( MED > 0 )); then
        echo "${Y}Review recommended${N}: $MED medium-severity finding(s) above. Worth addressing in your next operations review."
    else
        echo "${G}No high or medium-severity findings.${N} Continue periodic auditing as Claude Code ships changes."
    fi

    cat <<'FOOTER'

────────────────────────────────────────────────────────────────
Structural prevention reference:
• Claude Code Claim-Verify Handbook — 58 cases (15 body + 43 appendix D)
  with 14 prevention defenses mapped per case. Ships 2026-05-22, USD 19.
  Free preview: https://gist.github.com/yurukusa/6dd608049064ed66c54f1a545a7b47a8

Runtime prevention (hooks):
• cc-safe-setup — MIT-licensed PreToolUse/PostToolUse hook collection.
  https://github.com/yurukusa/cc-safe-setup
• skill-tax — per-skill token cost audit.
  https://github.com/eliransu/skill-tax

This audit is read-only and stateless. Rerun anytime after updates.
Run `bash claim-verify-audit.sh --json` for machine-readable output.
Patches welcome: open an issue or PR against the gist.
────────────────────────────────────────────────────────────────
FOOTER
fi

# Exit code: 1 if any HIGH-severity finding, 0 otherwise (for CI integration)
if (( HIGH > 0 )); then
    exit 1
fi
exit 0
