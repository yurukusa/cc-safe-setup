Saved: 2026-03-29T06:19:11+09:00 | Tool call: #1
Branch: main | Dirty files: 1
373ae67 checkpoint: pre-compact auto-save (1 files, 20260328-211903)
f594395 checkpoint: auto-save 06:18:54
c86b1b3 chore: sync public-facing numbers (517 hooks / 7,591 tests) Update SEO pages and READMEs from 514→517 hooks, 7,564→7,591 tests. Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
1a5167c docs: update CHANGELOG for v29.6.31 Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
13ac00c feat: add PreCompact event hook (#517 pre-compact-checkpoint) Auto-saves uncommitted changes before context compaction. Uses PreCompact event (fires at exact moment) instead of tool-call-counting heuristic. 9 new tests (7,591 total). Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
Read this file to understand what you were working on before context was compacted.
Check git status and git log for current state. Continue from the last commit.
