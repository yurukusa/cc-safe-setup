#!/bin/bash
# ephemeral-container-permission-warning.sh — Warn the operator when a
# session starts in what looks like an ephemeral container that won't
# persist ~/.claude/ between runs, so permission-related state will be
# lost every restart.
#
# Solves: anthropics/claude-code#61141 — "Remote routines lose MCP
# connector permissions every run — tools blocked in ephemeral container"
# (Awis-style report, regression from v2.1.122 to v2.1.123).
#
# In that case, a scheduled routine ran every hour. Each run prompted for
# MCP-tool permission approval ("Allow Claude to edit settings.json?")
# even though the connectors were configured as "always allowed" in prior
# runs. The reporter discovered the home directory was changing between
# runs (/root/.claude/ vs /home/user/.claude/), so any state written to
# ~/.claude/settings.json was discarded with the container. The routine
# attempting to self-heal by writing permissions to settings.json hit the
# same approval gate — producing a blocking loop the operator could not
# resolve from inside the ephemeral environment.
#
# This hook cannot fix the persistence problem from inside the container.
# It can only detect the failure mode at session start and surface
# operator-side workarounds before the routine tries to self-heal:
#
#   1. Bake permissions.allow into the container image (~/.claude/
#      mounted from the image layer, not from a writable layer that is
#      discarded between runs).
#   2. Mount a persistent volume at ~/.claude/ so the host preserves
#      settings between runs.
#   3. Pre-stage settings.json at the start of each run via a startup
#      script that copies a known-good config into ~/.claude/ before
#      claude-code starts (works around the container's write-discard
#      behavior at the cost of one extra step in the routine wrapper).
#
# Detection logic (deliberately conservative — false positives are worse
# than false negatives here, since the warning is an interruption):
#
#   container_signal = ANY OF:
#     - /.dockerenv exists
#     - /run/.containerenv exists
#     - /proc/1/cgroup mentions docker / containerd / kubepods / lxc
#     - $CONTAINER, $KUBERNETES_SERVICE_HOST, or $CODESPACES is set
#
#   AND
#
#   fresh_settings_signal = settings.json missing OR created < 60s ago
#
# Both must be true. Either alone is too weak.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_EPHEMERAL_WARN_DISABLE       set to "1" to skip
#   CC_EPHEMERAL_SETTINGS_PATH      default ~/.claude/settings.json
#   CC_EPHEMERAL_FRESH_THRESHOLD    default 60 (seconds since settings.json
#                                              creation that count as "fresh")
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/ephemeral-container-permission-warning.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_EPHEMERAL_WARN_DISABLE:-0}" = "1" ] && exit 0

SETTINGS_PATH="${CC_EPHEMERAL_SETTINGS_PATH:-$HOME/.claude/settings.json}"
FRESH_THRESHOLD="${CC_EPHEMERAL_FRESH_THRESHOLD:-60}"

# Container signal — ANY one is enough.
CONTAINER_SIGNAL=""

if [ -e "/.dockerenv" ]; then
    CONTAINER_SIGNAL="docker (/.dockerenv)"
elif [ -e "/run/.containerenv" ]; then
    CONTAINER_SIGNAL="podman/containerenv"
elif [ -r "/proc/1/cgroup" ] && grep -qE 'docker|containerd|kubepods|lxc' /proc/1/cgroup 2>/dev/null; then
    cg=$(grep -m1 -oE 'docker|containerd|kubepods|lxc' /proc/1/cgroup 2>/dev/null || echo "container")
    CONTAINER_SIGNAL="cgroup ($cg)"
elif [ -n "${CONTAINER:-}" ]; then
    CONTAINER_SIGNAL="\$CONTAINER=$CONTAINER"
elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
    CONTAINER_SIGNAL="\$KUBERNETES_SERVICE_HOST set"
elif [ -n "${CODESPACES:-}" ]; then
    CONTAINER_SIGNAL="\$CODESPACES=$CODESPACES"
fi

[ -z "$CONTAINER_SIGNAL" ] && exit 0

# Fresh-settings signal — settings missing OR very recently created.
FRESH_SIGNAL=""
if [ ! -f "$SETTINGS_PATH" ]; then
    FRESH_SIGNAL="missing"
else
    if [ -r "$SETTINGS_PATH" ]; then
        # Get file age in seconds (creation/modification time).
        now=$(date +%s)
        # Use stat to get mtime portably (Linux + macOS forms differ).
        mtime=$(stat -c %Y "$SETTINGS_PATH" 2>/dev/null || stat -f %m "$SETTINGS_PATH" 2>/dev/null || echo 0)
        if [ -n "$mtime" ] && [ "$mtime" -gt 0 ]; then
            age=$(( now - mtime ))
            if [ "$age" -le "$FRESH_THRESHOLD" ]; then
                FRESH_SIGNAL="created ${age}s ago"
            fi
        fi
    fi
fi

[ -z "$FRESH_SIGNAL" ] && exit 0

# Both signals fire — surface the warning.
cat >&2 <<EOF
<system-reminder>
EPHEMERAL-CONTAINER PERMISSION PERSISTENCE WARNING — this session is
starting in an environment with strong signals of being an ephemeral
container, and ~/.claude/settings.json is either missing or was just
created. Any permission state written this session ("Always allow",
manually-edited permissions.allow entries, MCP connector approvals) will
likely be DISCARDED when this container is recycled.

Container signal:  $CONTAINER_SIGNAL
Settings status:   $FRESH_SIGNAL ($SETTINGS_PATH)
Home directory:    $HOME

This is the failure mode documented in anthropics/claude-code#61141:
remote routines lose MCP connector permissions every run, and the
routine's own attempt to self-heal by writing settings.json hits the
permission-approval gate it was trying to bypass.

Operator-side workarounds (in order of robustness):

  1. BAKE INTO IMAGE — store the desired settings.json in your container
     image at ~/.claude/settings.json. Each run starts with the
     pre-approved permissions already in place. Survives container
     recycling.

  2. MOUNT PERSISTENT VOLUME — mount a host volume at ~/.claude/. The
     host preserves state across runs. Best for self-hosted environments;
     not available on most managed routine platforms.

  3. PRE-STAGE PER RUN — in the routine wrapper script (before claude
     starts), cp a known-good settings.json into ~/.claude/. Reads from
     a location the container does preserve (mounted secrets, env-var
     payload, fetched from a URL). One extra step per run but works on
     fully-managed platforms.

What does NOT help:
  - Clicking "Always allow" — does not survive container recycle.
  - Letting the routine self-heal via Write tool — hits the same gate.
  - Spawning sub-agents — they inherit the same permission boundary.

To disable this warning, set CC_EPHEMERAL_WARN_DISABLE=1.
</system-reminder>
EOF

# Exit 0 — detection-only, don't block session.
exit 0
