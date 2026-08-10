# Project Rules

## Safety
- Do not push to main/master directly
- Do not force-push
- Do not delete files outside this project
- Do not commit .env or credential files

## Before committing
- Run `bash scripts/ci-local.sh` — about 2 seconds, and it is the only command
  that runs what CI runs.
- `npm test` is `bash test.sh` and nothing else. CI stacks four more steps on
  top of it, and those steps are where the failures actually come from: of the
  25 red Tests runs in the fortnight to 2026-08-10, `npm test` would have
  caught 4. Seventeen were `docs/search-index.json is out of date` — a
  generated file, which `ci-local.sh` rebuilds for you.
- Enable the tracked git hook once per clone so the index can never fall behind
  again: `git config core.hooksPath scripts/hooks`.
- `bash test.sh` still has to be run by hand when you change hook behaviour;
  it and the per-hook suites under `tests/` are the two steps too slow to put
  in front of every commit.

## Code Style
- Follow existing conventions
- Keep functions small and focused
- Add comments only when the logic isn't obvious

## Git
- Use descriptive commit messages
- One logical change per commit
- Create feature branches for new work
