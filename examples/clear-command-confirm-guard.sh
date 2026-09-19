#!/bin/bash
# clear-command-confirm-guard.sh — DOES NOT FIRE. Kept as a record, not as a guard.
#
# This hook was written to block an accidental /clear (prefix matching means
# /c + Enter can hit /clear instead of /commit or /compact, #40931). It cannot
# work, and this file is kept so that nobody rebuilds it from the same idea.
#
# WHY IT CANNOT WORK
#   Slash commands never reach UserPromptSubmit. Measured 2026-09-19 on Claude
#   Code 2.1.270 (Linux/WSL2), with every other hook removed via
#   --setting-sources '' and a single recording hook passed inline through
#   --settings, driven through a pty:
#
#     typed           UserPromptSubmit          SessionEnd
#     ordinary text   fires, prompt holds it    --
#     /clear          never fires               fires, reason="clear"
#     /exit           never fires               fires, reason="prompt_input_exit"
#
#   The matcher below is therefore never evaluated. Feeding this script
#   {"prompt":"/clear"} by hand does make it exit 2 -- that proves the script's
#   own logic and nothing else, which is exactly the trap this file now warns
#   about.
#
# TWO MORE DEFECTS, recorded so the pattern is not copied:
#   * grep -qE '^/clear$' matches per line, not against the whole input, so a
#     prompt that merely contains /clear on its own line would have been refused.
#   * The refusal text said "permanently destroys all context". Saved history is
#     still reachable with /resume; only the current context goes.
#
# WHAT TO USE INSTEAD
#   You cannot block /clear with a hook. You can run one last thing against the
#   conversation before it goes: SessionEnd fires with reason="clear" while
#   transcript_path still points at a readable file. See handoff-on-clear.sh.
#
# TRIGGER: none

echo "clear-command-confirm-guard.sh does not fire on Claude Code 2.1.270: slash commands never reach UserPromptSubmit. See handoff-on-clear.sh for what works." >&2
exit 0
