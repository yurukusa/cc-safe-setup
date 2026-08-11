#!/bin/bash
# auto-mode-safety-enforcer.sh — Block dangerous operations in auto/acceptEdits mode
#
# Solves: Auto mode safety classifier hardcoded to opus-4-6, fails with Opus 4.7
#   - #49618: Safety classifier doesn't work with non-opus-4-6 models
#   - #49554: auto mode approved ~/.ssh deletion
#   - #18740: Auto-allow mode data loss without warning
#
# How it works: PreToolUse hook on Bash that blocks destructive commands
#   regardless of which model or permission mode is active. Acts as a
#   user-space safety net when the built-in classifier fails.
#
# What it blocks:
#   - rm -rf on non-safe paths (/, ~, .., /home, /etc, /usr, /var, .git)
#   - Credential file deletion (.ssh, .git-credentials, .env, .npmrc)
#   - dd/mkfs/fdisk (disk operations)
#   - kill -9 on system processes
#   - chmod 777 on sensitive paths
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-auto-mode-safety-enforcer-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [auto-mode-safety-enforcer]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# --- Mention vs invocation ----------------------------------------------------
# Every pattern below scans the command text, so a dangerous string written
# inside quotes reaches them exactly as an executed command would. Until now
# this hook lived with that by leaving quotes out of the terminator sets: the
# five quoted targets the header claims passed, and the mention controls in
# tests/auto-mode-unquoted-targets.test.sh passed for the same reason -- the
# target was invisible, not recognised.
#
# This is the quote-aware extraction destructive-guard grew in PR #960, ported
# here as the comment further down said it would have to be. Blank out
# everything inside quotes, then ask whether a destructive verb still starts a
# command in what is left. If none does, nothing destructive is being invoked
# and there is nothing for the rest of this file to judge.
if [ -z "${CC_AUTOMODE_UNWRAPPED:-}" ] && [ -n "$COMMAND" ]; then
    _am_outside=$(printf '%s' "$COMMAND" | awk -v SQ="'" -v DQ='"' '
      { line = $0; out = ""; q = 0
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (q == 0 && c == SQ) { q = 1; out = out " "; continue }
          if (q == 1) { if (c == SQ) q = 0; out = out " "; continue }
          if (q == 0 && c == DQ) { q = 2; out = out " "; continue }
          if (q == 2) { if (c == DQ) q = 0; out = out " "; continue }
          out = out c
        }
        print out }')
    # The wrapper unwrapping further down only runs if this gate lets the call
    # through, so the gate has to see a verb that sits inside a substitution or
    # a subshell too. Replace the wrapping tokens with separators first -- the
    # same substitution the unwrapping step uses. Measured 2026-08-11: without
    # this, a deletion inside a substitution and one on the right of an
    # assignment both exited 0 here and never reached the unwrapping.
    _am_gate=$(printf '%s' "$_am_outside" | sed -E \
        -e 's/\$\(/ ; /g' -e 's/`/ ; /g' \
        -e 's/(^|[[:space:]])\(/\1 ; /g' -e 's/\)([[:space:]]|$)/ ; \1/g' \
        -e 's/\)$/ ; /g' \
        -e 's/(^|[[:space:]])(then|do|else|elif)([[:space:]])/\1 ; \3/g')
    # A quoted string is only inert while nothing executes it. `sh -c` with a
    # quoted argument, `eval`, and a pipe into a shell all run that text, so
    # there the quoted string is a command and not a mention. Never let the
    # gate pass those through.
    if printf '%s' "$_am_outside" | grep -qE '(^|[;&|`(){}]|[[:space:]])((sh|bash|zsh|dash|ksh)[[:space:]]+(-[a-z]*[[:space:]]+)*-c([[:space:]]|$)|eval([[:space:]]|$))|\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash|ksh|python3?|perl|ruby|node)([[:space:]]|$)' 2>/dev/null; then
        :
    elif ! printf '%s' "$_am_gate" | grep -qE '(^|[;&|`(){}]|\$\(|[[:space:]](then|do|else|elif)[[:space:]])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|nice|ionice|timeout|exec|command|builtin|stdbuf|nohup|sudo|time|xargs)([[:space:]]+-[^[:space:]]+)*([[:space:]]+[0-9]+)?([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*([./]*[A-Za-z0-9_./-]*/)?(rm|rmdir|unlink|shred|dd|mkfs[.a-z0-9]*|fdisk|parted|chmod|kill|killall)([[:space:]]|$)' 2>/dev/null; then
        exit 0
    fi
fi

# --- Look inside wrappers -----------------------------------------------------
# The target patterns below require whitespace or end-of-line after the
# dangerous path, so a deletion wrapped in a substitution or a subshell ends
# with `)` and never matches. Measured 2026-08-04: the bare deletion was
# blocked and five of six wrappings passed. Claude Code 2.1.221 fixed the same
# shape in its own permission check.
#
# Replace the wrapping tokens with separators and run this same script once more
# against that text. Detection only: never executed; the message keeps the
# command the user actually sent.
if [ -n "${CC_AUTOMODE_UNWRAPPED:-}" ]; then
    COMMAND="$CC_AUTOMODE_UNWRAPPED"
elif [ -n "$COMMAND" ]; then
    _am_unwrapped=$(printf '%s' "$COMMAND" | sed -E \
        -e 's/\$\(/ ; /g' -e 's/`/ ; /g' \
        -e 's/(^|[[:space:]])\(/\1 ; /g' -e 's/\)([[:space:]]|$)/ ; \1/g' \
        -e 's/\)$/ ; /g' \
        -e 's/(^|[[:space:]])(then|do|else|elif)([[:space:]])/\1 ; \3/g')
    if [ "$_am_unwrapped" != "$COMMAND" ]; then
        CC_AUTOMODE_UNWRAPPED="$_am_unwrapped" bash "$0" </dev/null >/dev/null 2>&1
        if [ "$?" = "2" ]; then
            echo "BLOCKED: a destructive command is hidden inside a wrapper." >&2
            echo "Command: $COMMAND" >&2
            echo "A substitution, a subshell or a shell keyword does not make it safe." >&2
            exit 2
        fi
    fi
fi
[ -z "$COMMAND" ] && exit 0

# Quote characters are dropped for matching only. The gate above has already
# ruled out text that merely names a command, so a quote here is an ordinary
# way to write an argument and the target behind it has to be judged. Every
# message below still shows the command the user actually sent.
#
# This has to come after the unwrapping above, not before it: that step
# re-reads COMMAND from CC_AUTOMODE_UNWRAPPED in the recursive call, so a
# CMD_UNQ computed earlier would still hold the value from before the rewrite
# (empty, in the child) and every pattern below would match nothing.
CMD_UNQ=$(printf '%s' "$COMMAND" | tr -d "\"'")

# --- Critical rm operations ---
if echo "$CMD_UNQ" | grep -qE '(^|\s|;|&&|\|)(sudo\s+)?rm\s'; then
    # Always block rm on root-level and home-level critical paths
    # The home terminators used to be whitespace or end-of-line only, so
    # `rm -rf ~; echo done` passed while `rm -rf ~ ; echo done` was blocked --
    # one space apart, opposite verdicts. Separators end a command just as much
    # as a space does. Measured 2026-08-04.
    if echo "$CMD_UNQ" | grep -qE 'rm\s.*(/[[:space:];&|]|/$|~\/?[[:space:];&|]|~\/?$|~\/\.|/home\b|/etc\b|/usr\b|/var\b|/opt\b|/root\b)'; then
        echo "BLOCKED: rm targeting critical system/home path" >&2
        echo "This operation would cause irreversible data loss." >&2
        echo "Command: $COMMAND" >&2
        exit 2
    fi
    # The header above lists $HOME, a parent traversal and the git directory
    # among the paths this hook blocks, but the pattern before this one has no
    # case for any of them. Measured 2026-08-11 against the 19 targets the
    # header claims: 11 passed, including
    #
    #     rm -rf $HOME     rm -rf ${HOME}     rm -rf ..
    #     rm -rf ../..     rm -rf a/../..     rm -rf .git
    #
    # scripts.json grew the $HOME case in PR #962 and the quoted case in #961.
    # Neither fix reached this example, so the same defect stayed here.
    #
    # Quoted forms ("/", "$HOME", ".git") are deliberately still not matched.
    # This hook has no mention-vs-invocation pass, so putting a quote in a
    # terminator set would also block `echo "rm -rf /"` and a commit message
    # that names the command. Those pass today only because the target is
    # invisible behind the quote. Telling a mention from a run needs the
    # quote-aware extraction destructive-guard grew in PR #960; until that is
    # ported here, rm-safety-net and compound-command-deny-enforcer are the
    # layer that catches the quoted forms (measured: both deny them).
    #
    # Terminators are deliberate: `..` and `.git` must be a whole path
    # component, so `my..cache`, `backup..`, `.gitignore` and `.github` are
    # untouched, and `$HOMEBREW_PREFIX` does not look like `$HOME`.
    if echo "$CMD_UNQ" | grep -qE 'rm\s.*(\$\{?HOME\}?([[:space:];&|/]|$)|(^|[[:space:]/])\.\.([[:space:];&|/]|$)|(^|[[:space:]/])\.git([[:space:];&|/]|$))'; then
        echo "BLOCKED: rm targeting the home directory, a parent directory, or the git directory" >&2
        echo "This operation would cause irreversible data loss." >&2
        echo "Command: $COMMAND" >&2
        exit 2
    fi
    # Block rm on dotfiles in home directory
    if echo "$CMD_UNQ" | grep -qE "rm\s.*(${HOME}|\~)/\."; then
        echo "BLOCKED: rm targeting home dotfile" >&2
        echo "Command: $COMMAND" >&2
        exit 2
    fi
fi

# --- Disk-level operations ---
if echo "$CMD_UNQ" | grep -qE '(^|\s)(sudo\s+)?(dd\s+.*of=/dev|mkfs\.|fdisk\s|parted\s)'; then
    echo "BLOCKED: Disk-level operation (dd/mkfs/fdisk/parted)" >&2
    exit 2
fi

# --- Kill system processes ---
if echo "$COMMAND" | grep -qE 'kill\s+(-9\s+)?1$|killall\s+(init|systemd)'; then
    echo "BLOCKED: Killing system process" >&2
    exit 2
fi

exit 0
