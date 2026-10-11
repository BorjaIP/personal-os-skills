# Update commands by install source

`check` is read-only. `update` mutates and requires user approval.

## By install source

| Source | check | update |
|--------|-------|--------|
| pacman | `checkupdates` (pacman-contrib) or `pacman -Qu` | `sudo pacman -Syu <pkg>` (never partial `-Sy`) |
| apt | `apt list --upgradable 2>/dev/null` | `sudo apt install --only-upgrade <pkg>` |
| dnf | `dnf check-update <pkg>` | `sudo dnf upgrade <pkg>` |
| brew | `brew outdated <formula>` | `brew upgrade <formula>` (casks: `--cask`) |
| npm-global | `npm outdated -g <pkg>` | `npm install -g <pkg>@latest` |
| go-install | `go list -m -versions <module>` | `go install <module>@latest` |
| python-tool | `uv tool list --outdated` / `pipx list` | `uv tool upgrade <pkg>` / `pipx upgrade <pkg>` |
| official-script | tool-specific (below) | tool-specific (below) |

## Tool-specific

| Tool | check | update |
|------|-------|--------|
| Gentle AI | `gentle-ai update` or `gentle-ai upgrade --dry-run` | `gentle-ai upgrade` (managed binaries only; configs untouched) |
| Gentle AI configs/skills | `gentle-ai doctor` | `gentle-ai sync --agent <ids>` |
| Claude Code | `claude --version` vs `claude update` prompt | `claude update` |
| Claude marketplaces | `claude plugin marketplace list` | `claude plugin marketplace update [name]` |
| Cursor CLI | `cursor-agent --version` | `cursor-agent update` |
| Codex CLI | `npm outdated -g @openai/codex` | `npm install -g @openai/codex@latest` |
| Engram | `engram version` | brew: `brew upgrade gentleman-programming/tap/engram`; else `go install github.com/Gentleman-Programming/engram/cmd/engram@latest` |
| External skill (skills CLI) | `./install-external.sh list` (installed or missing; latest unknown) | `npx --yes skills@<SKILLS_CLI_VERSION> update -g <skill>` (pin read from `install-external.sh`) |
| Skill repo (git) | `git -C <path> fetch && git -C <path> rev-list --count HEAD..@{u}` | `git -C <path> pull --ff-only`, then `./install.sh` if skills use placeholders |

## Distro handling

The `os` row of `scan.sh` gives `id`, `wsl`, and `pm`. Use `pm` to pick the system-package row. On Arch, official Gentle AI/Engram installs are not in pacman; they resolve as `official-script` or `go-install`.
