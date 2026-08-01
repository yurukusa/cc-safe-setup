#!/bin/bash
# post-edit-disk-verify.sh — Catch "Edit/Write reported success but didn't
# persist to disk" silent failures at the tool boundary.
#
# Solves: anthropics/claude-code#61303 — Windows MAX_PATH(260) + isolated
# worktree + deep nested path yielded an `Edit`/`Write` that reported success
# in-tool while the filesystem still showed the original content. The agent's
# `Read` reflected the "edited" state; the disk did not. A defensive
# verification step inside the dispatched subagent caught it, but the failure
# mode was invisible until that defensive step fired.
#
# The structural class is broader than the MAX_PATH trigger: any condition
# under which the harness reports a successful write but the on-disk content
# diverges from the claimed write should be caught at the tool boundary, not
# at the next session's read.
#
# Type: PostToolUse hook on Edit and Write.
#
# Decision rule:
#
#   exit 0  — verification passed, or hook does not apply
#   exit 2  — verification failed; stderr explains why and Claude sees it
#
# The hook is intentionally permissive on edge cases (Edit with no content
# field, ephemeral files, non-regular files) and intentionally strict on the
# specific divergence shape #61303 names.
#
# Configuration env vars:
#
#   CC_POST_EDIT_VERIFY_DISABLE=1  — skip the hook entirely
#   CC_POST_EDIT_VERIFY_QUIET=1    — exit 0 even on detected divergence,
#                                    but still write the divergence to
#                                    ~/.claude/receipts/post-edit-divergence.jsonl
#                                    for audit (the "observe but don't gate"
#                                    mode useful for first-week deployment)

set -u

# Read tool input from stdin (Claude Code passes a JSON envelope).
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-post-edit-disk-verify-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [post-edit-disk-verify]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ -z "$TOOL" ]] && exit 0
[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0

# Honor the global disable.
[[ "${CC_POST_EDIT_VERIFY_DISABLE:-0}" == "1" ]] && exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0

# Helper: append a divergence record to the receipt log.
# Defined before first use — the missing-after-write path below calls it.
_record_divergence() {
    local file="$1"
    local tool="$2"
    local kind="$3"
    local msg="$4"
    local dir="${CC_POST_EDIT_VERIFY_RECEIPT_DIR:-$HOME/.claude/receipts}"
    mkdir -p "$dir" 2>/dev/null || return 0
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # The missing-after-write path calls this for a file that does not exist,
    # so guard the redirection to avoid a leaked "No such file" shell error.
    local file_size=0
    [ -f "$file" ] && file_size=$(wc -c < "$file" 2>/dev/null || echo 0)
    printf '{"ts":"%s","tool":"%s","file":"%s","kind":"%s","file_size":%s}\n' \
        "$ts" "$tool" "$file" "$kind" "$file_size" \
        >> "$dir/post-edit-divergence.jsonl" 2>/dev/null || true
}

# File must exist (Write may have created it; Edit always operates on existing).
[[ ! -e "$FILE" ]] && {
    # If the tool reported success on a Write to a path that doesn't exist
    # post-call, that is itself a divergence.
    if [[ "$TOOL" == "Write" ]]; then
        msg="post-edit-disk-verify: $TOOL claimed success on $FILE but file does not exist on disk (silent fail-to-persist; see anthropics/claude-code#61303)"
        _record_divergence "$FILE" "$TOOL" "missing-after-write" "$msg"
        if [[ "${CC_POST_EDIT_VERIFY_QUIET:-0}" != "1" ]]; then
            echo "$msg" >&2
            exit 2
        fi
    fi
    exit 0
}

# Regular file only (skip symlinks, sockets, devices).
[[ ! -f "$FILE" ]] && exit 0

# --- Check 1: Write with claimed content vs actual on-disk size ---
# If a Write claimed N bytes but disk shows much less, that is the
# strongest single signal of silent fail-to-persist.
if [[ "$TOOL" == "Write" ]]; then
    CLAIMED=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null)
    CLAIMED_LEN=${#CLAIMED}
    ACTUAL_LEN=$(wc -c < "$FILE" 2>/dev/null || echo 0)

    # Only fire when claimed content is non-trivial (avoid empty-write false positives).
    if [[ "$CLAIMED_LEN" -gt 100 ]]; then
        # Allow up to 2x slack for CRLF / encoding / final newline differences,
        # but a >50% shortfall is highly suggestive of fail-to-persist.
        if [[ "$ACTUAL_LEN" -lt $((CLAIMED_LEN / 2)) ]]; then
            msg="post-edit-disk-verify: Write to $FILE claimed $CLAIMED_LEN bytes but disk shows $ACTUAL_LEN bytes (>50% shortfall — likely silent fail-to-persist per anthropics/claude-code#61303). Check Windows MAX_PATH (260) on Windows, deep worktrees, or filesystem encoding."
            _record_divergence "$FILE" "$TOOL" "size-shortfall" "$msg"
            if [[ "${CC_POST_EDIT_VERIFY_QUIET:-0}" != "1" ]]; then
                echo "$msg" >&2
                exit 2
            fi
        fi
    fi
fi

# --- Check 2: Edit with no diff in git ---
# If an Edit reported success on a git-tracked file and produces no diff,
# either the Edit was a no-op (legitimate) or the change failed to persist.
# The hook treats a "claimed-non-trivial Edit with no diff" as the latter.
if [[ "$TOOL" == "Edit" ]]; then
    NEW=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
    OLD=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)

    # Only check if old_string != new_string (a real claimed change).
    if [[ -n "$NEW" && "$NEW" != "$OLD" ]]; then
        # Find git root for the file's directory.
        FILE_DIR=$(dirname "$FILE")
        if git -C "$FILE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            # File is in a git repo. Check whether the new_string appears in
            # the on-disk content. If not, the Edit did not persist.
            if ! grep -F -q -- "$NEW" "$FILE" 2>/dev/null; then
                msg="post-edit-disk-verify: Edit on $FILE claimed to insert content that is not found in the on-disk file (silent fail-to-persist per anthropics/claude-code#61303). Either the Edit did not land, or in-tool Read is showing stale-cached content."
                _record_divergence "$FILE" "$TOOL" "edit-not-in-file" "$msg"
                if [[ "${CC_POST_EDIT_VERIFY_QUIET:-0}" != "1" ]]; then
                    echo "$msg" >&2
                    exit 2
                fi
            fi
        fi
    fi
fi

exit 0
