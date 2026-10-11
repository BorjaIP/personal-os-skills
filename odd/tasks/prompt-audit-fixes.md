# prompt-audit-fixes

## Objective
Fix what the `claude-api prompt-audit` run flagged as wrong in this repo's prompt surface
(`AGENTS.md`, `skills/*/SKILL.md`, skill assets/references).

## Scope
In: audit findings F1-F10 (stale facts, fossils, migration-relative phrasing, numeric caps,
unsourced statistics, padding, over-specification, stale tool reference, descriptions over 250
characters), L1 (frozen-triage-note conflict, resolved by `docs/triage-architecture.md`),
L12 (marketplace entries, `meet` name field).
Out (need a user decision or live outside the repo): L2 (migrating 11 skills to the new
style), L3, L4, L5, L6, L7, L8, L9, L10, L11.

## Tasks
- [x] T1 re-run the audit on current `main` (the first report and diff were lost on session resume)
- [x] T2 apply F1-F9: datadog stale pointer, fossils, phrasing, caps, k8s padding, capture-insights, tool reference
- [x] T3 shorten the over-long descriptions (F10) to at most 250 characters, `Trigger:` first
- [x] T4 L1: add the documented exception to the datadog "frozen note" lines
- [x] T5 L12: register `capture-insights` and `meet` in `marketplace.json`; fix `meet` `name:`
- [x] T6 verify: placeholders untouched, descriptions length, JSON valid, `git diff --stat`

## Route
T1 delegated (read-only explorer, broad evidence). T2-T5 inline: applying a checked diff and
small known edits. Recorded so the skipped delegation is visible.

## Checks
No test runner. `git apply --check`, `bash -n`, JSON validation, description-length script,
placeholder regex scan from `install.sh`. Activation of rewritten descriptions needs a manual re-test.

## Progress
- T1 done: audit re-run on current main by a read-only explorer (21 findings); first run was lost on session resume.
- T2 done (commits: datadog, k8s, single-file fixes): F1-F9 applied. One hunk skipped on purpose: the rewritten `meet` example (taste, not a defect).
- T3 done: 12 descriptions rewritten to at most 250 characters starting with `Trigger:`; checked by script. Activation of rewritten skills still needs a manual re-test.
- T4 done: frozen-note exception added to the datadog skills, verified against `docs/triage-architecture.md:134`.
- T5 partly done: `capture-insights` and `meet` registered in `marketplace.json`. NOT done: renaming `meet` `name:` (`meeting-notes-enhance`), because `meet/meet/cli.py:111` tells users to run that name; it needs a code change decided by the user.
- Extra, same cause: README, `docs/datadog.md` and marketplace descriptions still said the datadog suite creates notebooks; fixed. `docs/triage-architecture.md` pointed at `~/.cursor/skills-cursor/`; fixed.
- Left open (need a user decision or live outside the repo): L2 migrate 11 skills to the AGENTS.md style, L3 `get_widget` rule, L4-L11.
- T6 checks: JSON valid, descriptions script, placeholder regex, `git apply --check` for every theme, facts verified against code (Pi detection, `meet stop`, severity table, architecture doc).
