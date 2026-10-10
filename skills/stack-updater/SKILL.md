---
name: stack-updater
description: "Trigger: check updates, update my stack, update skills, update gentle-ai, outdated tools, actualizar mi stack. Report available updates for bootstrap tools and this repo's skills, apply them on approval."
license: Apache-2.0
metadata:
  author: "BorjaIP"
  version: "1.1"
---

## Activation Contract

Load when the user asks whether anything installed by this repo can be updated: bootstrap tools (Claude Code, Codex, Cursor CLI, Gentle AI, Engram), Gentle AI-managed tools, or the skills in this repository. Also load when the user names a new tool or repo to track.

## Hard Rules

- Audit is read-only. NEVER update before the user approves the exact list.
- Not-installed tools are NOT a problem: list them in ONE line ("Not installed: a, b") with no advice, no install offer, no follow-up question.
- Never run `sudo` or system-package commands without showing the command and getting approval.
- Use only the updater matching the binary's `source` from `assets/scan.sh`. Never mix managers.
- Never invent a "latest" version; report `unknown`.
- Never touch project repositories. Write only to `~/.config/personal-os-skills/stack.yaml`, and only when the user names a new item.
- Stay terse: no installation suggestions, no unrelated tooling.
- Before running `./install.sh`, run `./install.sh --list`, ask the user which families to install, and pass `--family`. Never run it without an explicit selection.

## Decision Gates

| Situation | Action |
|-----------|--------|
| Gentle AI, Engram, GGA | Use `gentle-ai update` for installed vs latest; apply with `gentle-ai upgrade` |
| Claude / Cursor / Codex | Source-specific command in `references/update-commands.md` |
| Repo `behind` > 0 | `git pull --ff-only`, then `./install.sh --no-prompt` to re-render placeholder skills |
| Repo `dirty` > 0 | Report it; do not pull until the user decides |
| Skill `missing` for a detected harness | Report names in one line; install only via `./install.sh` on approval |
| Skill `copy` with placeholders | Needs `./install.sh` after a pull to refresh |
| `source` = unknown | Report; do not guess a manager |
| Update fails | Stop that item, show output, continue the rest |

## Execution Steps

1. Run `bash assets/scan.sh` (path relative to this skill) and `gentle-ai update` when `gentle-ai` is present.
2. Merge extra items from `~/.config/personal-os-skills/stack.yaml` if it exists.
3. Build the report; consider cursor skills only if `~/.cursor` exists.
4. Show it, then ask once: update all / pick / none. STOP and wait.
5. Apply approved items one at a time; re-check each version.
6. Run `gentle-ai doctor` only if Gentle AI was upgraded.

## Output Contract

Table `item | current | latest | status` (`up-to-date | update available | unknown`), skills summary (`N installed, M missing`), one line for not-installed tools. After approval: `item | command | result | new version`, plus skipped and failed items.

## References

- `references/update-commands.md` — per-source commands.
- `assets/scan.sh` — read-only detector.
- `assets/stack.example.yaml` — manifest for extra items.
