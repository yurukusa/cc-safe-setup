#!/bin/bash
# registry-publish-guard.sh — Block publishing to package registries
#
# Solves: Claude Code accidentally publishing packages to npm, PyPI,
#         RubyGems, crates.io, or other registries. Publishing is
#         irreversible for many registries (npm unpublish has a 72h limit).
#
# Note: npm-publish-guard.sh covers npm specifically.
#       This hook covers ALL package registries.
#
# Detects:
#   gem push              (RubyGems)
#   twine upload          (PyPI)
#   pip upload            (PyPI alternative)
#   cargo publish         (crates.io)
#   dotnet nuget push     (.NET NuGet)
#   docker push           (Docker Hub)
#   helm push             (Helm charts)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block gem push (RubyGems)
if echo "$COMMAND" | grep -qE '\bgem\s+push\b'; then
    echo "BLOCKED: RubyGems publish detected." >&2
    echo "  Publishing to RubyGems is irreversible. Verify version and credentials." >&2
    exit 2
fi

# Block PyPI upload (twine/pip)
if echo "$COMMAND" | grep -qE '\b(twine|pip)\s+upload\b'; then
    echo "BLOCKED: PyPI upload detected." >&2
    exit 2
fi

# Block cargo publish (crates.io)
if echo "$COMMAND" | grep -qE '\bcargo\s+publish\b'; then
    echo "BLOCKED: crates.io publish detected." >&2
    exit 2
fi

# Block dotnet nuget push
if echo "$COMMAND" | grep -qE '\bdotnet\s+nuget\s+push\b'; then
    echo "BLOCKED: NuGet publish detected." >&2
    exit 2
fi

# Block docker push
if echo "$COMMAND" | grep -qE '\bdocker\s+push\b'; then
    echo "BLOCKED: Docker image push detected." >&2
    echo "  Verify the image tag and registry before pushing." >&2
    exit 2
fi

# Block helm push
if echo "$COMMAND" | grep -qE '\bhelm\s+(push|package.*push)\b'; then
    echo "BLOCKED: Helm chart push detected." >&2
    exit 2
fi

exit 0
