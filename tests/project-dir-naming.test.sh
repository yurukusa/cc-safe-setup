#!/bin/bash
# Hooks that look inside ~/.claude/projects/ must derive the directory name the
# way Claude Code actually writes it.
#
# Claude Code names a project directory by replacing every `/` in the absolute
# working directory with `-`. The leading slash becomes a leading dash, and it
# stays:
#
#   /home/u/projects/app   ->   -home-u-projects-app
#
# Six shipped hooks stripped that leading dash, in two different spellings:
# `sed 's|/|-|g; s|^-||'` removes it after the conversion, `sed 's|^/||; s|/|-|g'`
# removes the slash before it. The path they built therefore never existed, and each
# hook has an early `[ ! -d "$SESSION_DIR" ] && exit 0` guard — so all six ran,
# exited 0, and did nothing. One of them is the session backup. It had never made
# a backup.
#
# The first sweep grepped for one spelling and found three. The other three were
# structurally invisible to that search — the same shape of mistake the hooks
# themselves had. That is why both spellings are controls below.
#
# Measured on 2026-08-12 against a real install:
#   built by the old form:  ~/.claude/projects/home-namakusa-projects-cc-loop   (absent)
#   built by the fixed form: ~/.claude/projects/-home-namakusa-projects-cc-loop (present)
#
# The control below is the point of this file. Asserting only that the fixed form
# is right would pass just as happily if the assertion were vacuous; the old form
# has to fail it.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0

check() {
    local label="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "      got:  $got"
        echo "      want: $want"
    fi
}

# The naming rule, stated once.
name_of() { printf '%s' "$1" | sed 's|/|-|g'; }

for abs in /home/u/projects/app /home/namakusa/projects/cc-loop /tmp/x; do
    want="$(printf '%s' "$abs" | tr '/' '-')"
    check "leading dash kept: $abs" "$(name_of "$abs")" "$want"
done

# Control: the form that shipped must NOT satisfy the rule. If this ever passes,
# the assertions above are not testing anything.
old_form() { printf '%s' "$1" | sed 's|/|-|g; s|^-||'; }
for abs in /home/u/projects/app /tmp/x; do
    if [ "$(old_form "$abs")" = "$(name_of "$abs")" ]; then
        FAIL=$((FAIL + 1))
        echo "FAIL: control did not discriminate for $abs"
    else
        PASS=$((PASS + 1))
    fi
done

# The stripping shows up in two spellings. Searching for one of them is how the
# first sweep found three of the six: `s|^-||` removes the dash after the
# conversion, `s|^/||` removes the slash before it. Same result, different grep.
old_form_b() { printf '%s' "$1" | sed 's|^/||; s|/|-|g'; }
for abs in /home/u/projects/app /tmp/x; do
    if [ "$(old_form_b "$abs")" = "$(name_of "$abs")" ]; then
        FAIL=$((FAIL + 1))
        echo "FAIL: control B did not discriminate for $abs"
    else
        PASS=$((PASS + 1))
    fi
done

# The shipped hooks must not carry either spelling any more.
for f in examples/session-backup-on-start.sh \
         examples/session-index-repair.sh \
         examples/worktree-project-unify.sh \
         examples/extended-thinking-loop-guard.sh \
         examples/extended-thinking-resume-warning.sh \
         examples/opus48-thinking-wedge-advisor.sh; do
    if grep -qF 's|^-||' "$ROOT/$f" || grep -qF 's|^/||; s|/|-|g' "$ROOT/$f"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $f still strips the leading separator"
    else
        PASS=$((PASS + 1))
    fi
    # And they must still build the name at all — a hook that stopped deriving a
    # path would also pass the grep above.
    if grep -qF "sed 's|/|-|g'" "$ROOT/$f"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $f no longer derives a project directory name"
    fi
done

echo
echo "project-dir-naming: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
