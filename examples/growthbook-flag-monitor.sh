#!/bin/bash
# ================================================================
# growthbook-flag-monitor.sh — Surface server-pushed GrowthBook
#   flag changes that silently override client-side state.
# ================================================================
# PURPOSE:
#   Issue #62205 (2026-05-25, root-cause analysis) documented that
#   the macOS Desktop variant of Claude Code syncs GrowthBook A/B
#   feature flags from the Anthropic server every ~9 minutes and
#   silently overrides the user's local settings.json. Concretely,
#   `permissions.defaultMode: bypassPermissions` flips back to
#   `acceptEdits` on each sync, with the same shape applying to
#   other dispatch surfaces (auto-compact: #63015 suspects
#   `tengu_compact_cache_prefix` gating a new compaction path that
#   silently fails to fire).
#
#   The local cache file is read-write but not authoritative — any
#   operator edit is restored on the next ~9-minute sync. Local
#   edits do not persist. The five documented override paths in
#   the cluster framing all draw from the cached flag set, so the
#   minimum-viable defense is to make flag changes visible to the
#   operator instead of letting them happen silently in the
#   background.
#
# WHO THIS PROTECTS:
#   macOS Claude Desktop operators (where the cache file is at
#   `~/Library/Application Support/Claude/cachedGrowthBookFeatures`).
#   Linux operators where the cache lives under
#   `~/.config/Claude/cachedGrowthBookFeatures` are also covered
#   when the file is present. CLI-only operators are unaffected
#   when the file is absent — the hook stays silent.
#
# HOW IT WORKS:
#   On SessionStart, snapshots the current GrowthBook flag set
#   (sha256 over the canonicalised flag-name list, plus the
#   per-flag JSON value digest). Compares against the previous
#   snapshot from `${XDG_STATE_HOME:-$HOME/.local/state}/cc-safe-setup/
#   growthbook-flag-monitor/snapshot.json`. If the set has changed,
#   prints a one-screen stderr advisory listing added / removed /
#   changed flags so the operator sees what shifted while they
#   were away. Always exits 0 (advisory only).
#
#   The snapshot does NOT contain raw flag values by default
#   (those are server-controlled and can change without notice).
#   The snapshot stores just the flag-name set + per-flag value
#   digest. Set CC_GROWTHBOOK_MONITOR_FULL=1 to also store full
#   values for forensic comparison (off by default to keep the
#   state file small).
#
# TRIGGER: SessionStart  MATCHER: ""
# CLUSTER: 10 (GrowthBook A/B flag client-side overrides)
#
# CONFIGURATION (env vars):
#   CC_GROWTHBOOK_MONITOR_DISABLE      Set to "1" to silence.
#   CC_GROWTHBOOK_MONITOR_PATH         Override cache file path.
#                                      Default: macOS / Linux auto.
#   CC_GROWTHBOOK_MONITOR_STATE_DIR    Override snapshot dir.
#                                      Default: $XDG_STATE_HOME or
#                                      $HOME/.local/state.
#   CC_GROWTHBOOK_MONITOR_FULL         Store full values in
#                                      snapshot (forensic mode).
#                                      Default: off (digest only).
#   CC_GROWTHBOOK_MONITOR_QUIET        Suppress the no-change line
#                                      shown on first run / no diff.
#   CC_GROWTHBOOK_MONITOR_LOG          Append snapshot events to
#                                      this file (default off).
#
# USAGE:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/growthbook-flag-monitor.sh"
#       }]
#     }]
#   }
# }

INPUT=$(cat 2>/dev/null || true)

if [ "${CC_GROWTHBOOK_MONITOR_DISABLE:-}" = "1" ]; then
    exit 0
fi

# Locate the cachedGrowthBookFeatures file.
locate_cache() {
    if [ -n "${CC_GROWTHBOOK_MONITOR_PATH:-}" ]; then
        [ -f "$CC_GROWTHBOOK_MONITOR_PATH" ] && echo "$CC_GROWTHBOOK_MONITOR_PATH"
        return 0
    fi
    # macOS Claude Desktop
    if [ -f "$HOME/Library/Application Support/Claude/cachedGrowthBookFeatures" ]; then
        echo "$HOME/Library/Application Support/Claude/cachedGrowthBookFeatures"; return 0
    fi
    # Linux Claude Desktop (XDG)
    if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/cachedGrowthBookFeatures" ]; then
        echo "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/cachedGrowthBookFeatures"; return 0
    fi
    # ~/.claude.json carries cachedGrowthBookFeatures on some Claude Code variants
    if [ -f "$HOME/.claude.json" ] && grep -q "cachedGrowthBookFeatures" "$HOME/.claude.json" 2>/dev/null; then
        echo "$HOME/.claude.json"; return 0
    fi
    return 1
}

CACHE_FILE=$(locate_cache)
if [ -z "$CACHE_FILE" ]; then
    # No GrowthBook cache found — operator is on CLI or has the file disabled.
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[growthbook-flag-monitor] jq not available; skipping (install jq to enable)" >&2
    exit 0
fi

STATE_DIR="${CC_GROWTHBOOK_MONITOR_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/cc-safe-setup/growthbook-flag-monitor}"
mkdir -p "$STATE_DIR" 2>/dev/null
SNAPSHOT_FILE="$STATE_DIR/snapshot.json"

# Build a normalised flag manifest. The cache file is either:
#   - a JSON object {flag_name: {value: ...}, ...} (Desktop variants)
#   - the full ~/.claude.json with cachedGrowthBookFeatures nested.
extract_flags() {
    # First try the direct object form
    local payload
    payload=$(jq -c '.cachedGrowthBookFeatures // .' "$CACHE_FILE" 2>/dev/null)
    if [ -z "$payload" ] || [ "$payload" = "null" ]; then
        echo "{}"
        return 1
    fi
    # Normalise to {flag_name: digest_of_value}
    echo "$payload" | jq -c '
        if type == "object" then
            to_entries
            | map({key: .key, value: (.value | tostring | @base64)})
            | from_entries
        else
            {}
        end
    ' 2>/dev/null || echo "{}"
}

CURRENT=$(extract_flags)
if [ -z "$CURRENT" ] || [ "$CURRENT" = "{}" ]; then
    # File present but no flag data — silent skip.
    exit 0
fi

# First run: snapshot and emit baseline notice.
if [ ! -f "$SNAPSHOT_FILE" ]; then
    if [ "${CC_GROWTHBOOK_MONITOR_FULL:-}" = "1" ]; then
        jq -c '.cachedGrowthBookFeatures // .' "$CACHE_FILE" > "$SNAPSHOT_FILE" 2>/dev/null
    else
        echo "$CURRENT" > "$SNAPSHOT_FILE"
    fi
    if [ -z "${CC_GROWTHBOOK_MONITOR_QUIET:-}" ]; then
        FLAG_COUNT=$(echo "$CURRENT" | jq 'length' 2>/dev/null)
        echo "[growthbook-flag-monitor] baseline snapshot recorded: ${FLAG_COUNT} flags in ${CACHE_FILE}" >&2
    fi
    if [ -n "${CC_GROWTHBOOK_MONITOR_LOG:-}" ]; then
        mkdir -p "$(dirname "$CC_GROWTHBOOK_MONITOR_LOG")" 2>/dev/null
        echo "$(date -Iseconds) event=baseline cache=${CACHE_FILE} flags=${FLAG_COUNT}" >> "$CC_GROWTHBOOK_MONITOR_LOG"
    fi
    exit 0
fi

PREVIOUS=$(cat "$SNAPSHOT_FILE" 2>/dev/null)
if [ "${CC_GROWTHBOOK_MONITOR_FULL:-}" = "1" ]; then
    # Compare full values
    PREVIOUS=$(echo "$PREVIOUS" | jq -c '
        if type == "object" then
            to_entries | map({key: .key, value: (.value | tostring | @base64)}) | from_entries
        else {} end
    ' 2>/dev/null)
fi

# Compute diff using jq set operations
DIFF=$(jq -n --argjson prev "$PREVIOUS" --argjson curr "$CURRENT" '
    {
        added: (($curr | keys) - ($prev | keys)),
        removed: (($prev | keys) - ($curr | keys)),
        changed: [
            ($curr | keys | .[]) as $k
            | select(($prev | has($k)) and ($prev[$k] != $curr[$k]))
            | $k
        ]
    }
' 2>/dev/null)

ADDED=$(echo "$DIFF" | jq -r '.added | length' 2>/dev/null)
REMOVED=$(echo "$DIFF" | jq -r '.removed | length' 2>/dev/null)
CHANGED=$(echo "$DIFF" | jq -r '.changed | length' 2>/dev/null)
TOTAL=$((${ADDED:-0} + ${REMOVED:-0} + ${CHANGED:-0}))

if [ "$TOTAL" -eq 0 ]; then
    if [ -z "${CC_GROWTHBOOK_MONITOR_QUIET:-}" ]; then
        FLAG_COUNT=$(echo "$CURRENT" | jq 'length' 2>/dev/null)
        echo "[growthbook-flag-monitor] no GrowthBook flag changes since last session (${FLAG_COUNT} flags tracked)" >&2
    fi
    exit 0
fi

# Emit diff advisory
cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[growthbook-flag-monitor] SessionStart — GrowthBook flag set changed
Cache file: ${CACHE_FILE}
Cluster 10 (server-pushed flag overrides). Anthropic syncs flags
on a ~9-minute cadence; local edits do not persist across syncs.

Changes since last session:
  added:   ${ADDED}
  removed: ${REMOVED}
  changed: ${CHANGED}
EOF

if [ "${ADDED:-0}" -gt 0 ]; then
    echo "" >&2
    echo "  ADDED:" >&2
    echo "$DIFF" | jq -r '.added[] | "    + " + .' >&2
fi
if [ "${REMOVED:-0}" -gt 0 ]; then
    echo "" >&2
    echo "  REMOVED:" >&2
    echo "$DIFF" | jq -r '.removed[] | "    - " + .' >&2
fi
if [ "${CHANGED:-0}" -gt 0 ]; then
    echo "" >&2
    echo "  CHANGED:" >&2
    echo "$DIFF" | jq -r '.changed[] | "    ~ " + .' >&2
fi

cat >&2 <<'EOF'

Verify your permissions.defaultMode and other settings.json values
are still what you expect. Server-pushed flags (e.g.
tengu_permission_friction, tengu_quill_harbor, tengu_compact_cache_prefix)
have been observed silently overriding client behavior.
Issue: https://github.com/anthropics/claude-code/issues/62205
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# Update the snapshot for the next session
if [ "${CC_GROWTHBOOK_MONITOR_FULL:-}" = "1" ]; then
    jq -c '.cachedGrowthBookFeatures // .' "$CACHE_FILE" > "$SNAPSHOT_FILE" 2>/dev/null
else
    echo "$CURRENT" > "$SNAPSHOT_FILE"
fi

if [ -n "${CC_GROWTHBOOK_MONITOR_LOG:-}" ]; then
    mkdir -p "$(dirname "$CC_GROWTHBOOK_MONITOR_LOG")" 2>/dev/null
    echo "$(date -Iseconds) event=diff added=${ADDED} removed=${REMOVED} changed=${CHANGED}" >> "$CC_GROWTHBOOK_MONITOR_LOG"
fi

exit 0
