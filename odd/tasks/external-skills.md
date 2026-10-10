# external-skills

## Objective
A catalog of third-party skill repositories (first: cathrynlavery/diagram-design) from which
the user picks what to install, globally, into every harness detected on the machine.

## Decision
Wrap the cross-agent `skills` CLI (vercel-labs/skills) pinned to 1.7.2. It knows each
harness's global skills directory; we keep only the catalog, harness detection and selection.

## Scope
`external/catalog.tsv`, `install-external.sh` (new), `setup.sh`, `README.md`,
`skills/stack-updater/*`. Out of scope: auditing third-party skill content, project-scope installs.

## Tasks
- [x] T1 catalog + `install-external.sh` (`list`, `install --only`, harness detection, pinned CLI, `--dry-run`)
- [ ] T2 `setup.sh` integration: External section in menu, `--list`, `--only <id>`
- [ ] T3 stack-updater (list/update external skills) + README docs

## Route
Inline: context already loaded; shell scripts verified with dry-run and `skills add --list`.

## Checks
No test runner for shell: `bash -n`, dry-run command inspection, `skills add --list` (read-only).

## Progress
- T1 done: `external/catalog.tsv` (diagram-design) and `install-external.sh` (`list`, `agents`, `install --only`, confirmation, `--dry-run`, pinned `skills@1.7.2`). Checks: `bash -n`, list/agents/guards/dry-run, and `npx skills@1.7.2 add cathrynlavery/diagram-design --list` found 1 skill `diagram-design` (nothing installed). Detected harnesses here: claude-code, cursor, gemini-cli.
