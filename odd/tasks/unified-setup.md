# unified-setup

## Objective
One entry point (`setup.sh`) with a component menu that covers harness tools
(Claude Code, Codex, Cursor CLI, T3, Gentle AI, Engram) and skill families,
usable interactively and non-interactively (so an agent can ask the user and run it).

## Decision
Option A: thin dispatcher over `bootstrap-harness.sh` and `install.sh`. Both keep working alone.

## Scope
`bootstrap-harness.sh` (component selection), `setup.sh` (new), `README.md`,
`skills/stack-updater/SKILL.md`. Out of scope: merging the two scripts, Obsidian/Raycast logic.

## Tasks
- [x] T1 bootstrap-harness: `--only`, `list` command, `install` respects selected components (fixes: installs CLIs not requested)
- [ ] T2 setup.sh: `--list`, interactive menu, `--only` mixing tool ids and skill families, `--dry-run`/`--yes`/`--preset` passthrough
- [ ] T3 docs: README setup section, stack-updater rule points to setup.sh

## Route
Inline for all tasks: context already loaded, no research needed, files are
shell scripts verified by dry-run. Recorded so the skipped delegation is visible.

## Tests / checks
Shell scripts without a runner: `bash -n` plus dry-run and pty checks (no RED/GREEN possible).

## Progress

- T1 done: `--only`, `list`, install/configure honour selected components; Node check only when t3/codex selected. Checks: `bash -n`, dry-runs for list, unknown component, --only subsets, configure agent targeting. Note: local Node 23.4.0 fails the T3 requirement (pre-existing).
- T1 commit: 53090bc
