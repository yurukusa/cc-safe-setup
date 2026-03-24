#!/bin/bash
# ================================================================
# typosquat-guard.sh — Detect potential typosquatting in npm install
# ================================================================
# PURPOSE:
#   Claude sometimes installs packages with slightly misspelled
#   names (e.g., "loadsh" instead of "lodash"). This hook checks
#   common typosquatting patterns in npm/pip install commands.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Extract package name from install command
PKG=""
if echo "$COMMAND" | grep -qE '^\s*npm\s+install\s+'; then
    PKG=$(echo "$COMMAND" | grep -oE 'npm\s+install\s+(\S+)' | awk '{print $3}' | head -1)
elif echo "$COMMAND" | grep -qE '^\s*pip\s+install\s+'; then
    PKG=$(echo "$COMMAND" | grep -oE 'pip\s+install\s+(\S+)' | awk '{print $3}' | head -1)
fi
[ -z "$PKG" ] && exit 0

# Strip scope and version
PKG=$(echo "$PKG" | sed 's/@[^/]*\///' | sed 's/@.*//')

# Known popular packages and their common typos
declare -A POPULAR=(
    ["lodash"]="loadsh lodassh lodas"
    ["express"]="expresss expres exppress"
    ["react"]="recat raect reatc"
    ["axios"]="axois axio axioss"
    ["moment"]="momnet moemnt momet"
    ["webpack"]="webpak webpackk wepback"
    ["typescript"]="typscript typescrip tyepscript"
    ["eslint"]="esling eslnt elsint"
    ["prettier"]="pretier pretter prettir"
    ["mongoose"]="mongose mongooe mongooes"
)

for legit in "${!POPULAR[@]}"; do
    for typo in ${POPULAR[$legit]}; do
        if [ "$PKG" = "$typo" ]; then
            echo "WARNING: '$PKG' looks like a typo of '$legit'." >&2
            echo "Did you mean: npm install $legit" >&2
            echo "Typosquatting packages can contain malware." >&2
            exit 0
        fi
    done
done

# Check for suspicious single-char differences from popular packages
LEN=${#PKG}
if [ "$LEN" -gt 3 ] && [ "$LEN" -lt 20 ]; then
    for legit in "${!POPULAR[@]}"; do
        LEGIT_LEN=${#legit}
        DIFF=$((LEN - LEGIT_LEN))
        [ "$DIFF" -lt -1 ] || [ "$DIFF" -gt 1 ] && continue
        # Simple Levenshtein approximation: count differing chars
        MATCH=0
        for ((i=0; i<LEN && i<LEGIT_LEN; i++)); do
            [ "${PKG:$i:1}" = "${legit:$i:1}" ] && MATCH=$((MATCH+1))
        done
        SIMILARITY=$((MATCH * 100 / (LEGIT_LEN > LEN ? LEGIT_LEN : LEN)))
        if [ "$SIMILARITY" -ge 80 ] && [ "$PKG" != "$legit" ]; then
            echo "NOTE: '$PKG' is similar to '$legit' (${SIMILARITY}% match)." >&2
            echo "Verify this is the correct package name." >&2
        fi
    done
fi

exit 0
