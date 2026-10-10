# Personal OS Skills

A personal collection of skills for any coding agent — [Claude Code](https://docs.claude.com/en/docs/claude-code), [Cursor](https://cursor.com), [OpenCode](https://github.com/opencode-ai/opencode), or whichever you prefer. It centralises in a single repository the capabilities I use daily so I can install them at the user level on any machine.

> Inspired by [ArtemXTech/personal-os-skills](https://github.com/ArtemXTech/personal-os-skills).

## Context

I'm an AI Data Platform Engineer working across DevOps, MLOps, and LLMOps. This repo works together with [**pkm**](https://github.com/BorjaIP/pkm) (my Obsidian vault / Second Brain) and [**opstoolkit**](https://github.com/BorjaIP/opstoolkit) (reusable infra templates) — skills generate artifacts, the vault captures them, and the toolkit provides the boilerplate for the infrastructure work that comes out of it.

## Why These Skills Exist

> Inspired by LLM Wiki karpathy and his approach.

I already had a [Second Brain](https://github.com/BorjaIP/pkm) built on an Obsidian vault. The next step was taking it to every level: meetings, observability tools, postmortems, runbooks — everything I touch should end up in my vault as structured, searchable knowledge.

These skills are the bridge. They connect the tools I use daily (Kubernetes, Jenkins, Datadog, meeting recordings) directly to my vault, so the output of my work becomes knowledge automatically. I organised them by category and built each one around a real need. They are purely technical and tailored to my workflow, but the pattern is adaptable — swap the categories and sources for whatever fits yours.

## Skills

### Kubernetes
- **[k8s-error-analyzer](skills/k8s-error-analyzer/)** — Analyze pod failures from logs (label selectors supported), identify errors and generate reports
- **[k8s-optimizer-cost](skills/k8s-optimizer-cost/)** — Right-size workloads using Datadog metrics and PerfectScale's policy-driven methodology

### Datadog
- **[datadog-triage](skills/datadog-triage/)** — End-to-end triage orchestrator: plan, delegate to sub-skills, consolidate into a master report + notebook
- **[datadog-service-health](skills/datadog-service-health/)** — APM health check: latency percentiles, error rate, throughput, failing traces, dependency graph
- **[datadog-logs-analyzer](skills/datadog-logs-analyzer/)** — Log investigation via pattern clustering, attribute discovery and DDSQL aggregation
- **[datadog-metrics-investigator](skills/datadog-metrics-investigator/)** — Metric spike/anomaly investigation with sliced timeseries and baseline comparison
- **[datadog-report-publisher](skills/datadog-report-publisher/)** — Shared publisher: writes Markdown artefact + creates bidirectionally-linked Datadog Notebook

### Ops
- **[create-runbook](skills/create-runbook/)** — Promote related triage notes into a reusable runbook, backlink sources and flip status to resolved

### Productivity
- **[meet](skills/meet/)** — Record meetings, transcribe with Whisper, create Obsidian notes, AI-enhance into structured reports
- **[capture-insights](skills/capture-insights/)** — Extract durable engineering knowledge from conversations and persist it to topic notes in the Obsidian vault
- **[run](skills/run/)** — Execute your own free-form prompts written in the Obsidian PKM (`meridian/<slug>/PROMPTS.md`) directly in the current session
- **[second-opinion](skills/second-opinion/)** — Independent multi-agent QA review of agent-produced work: intent alignment, bug scan, CLAUDE.md compliance, and optional correction plan


### Harness
- **[stack-updater](skills/stack-updater/)** — Report available updates for the tools `bootstrap-harness.sh` installs (Claude Code, Codex, Cursor CLI, Gentle AI, Engram) and for this repo's skills, then apply them on approval

## Kubernetes

I manage multiple clusters and namespaces. When a pod crashes or a deployment is burning money with oversized requests, I need answers fast — not a 20-minute kubectl session. These skills read logs and metrics, produce a structured report, and drop it into `ops/k8s/` so the analysis is searchable later. Full details: **[docs/k8s.md](docs/k8s.md)**.

## Datadog

Datadog is my primary observability stack. Instead of switching between APM, logs, and metrics dashboards manually, the triage orchestrator plans the investigation, delegates to specialised sub-skills, and consolidates everything into a single report with a linked Datadog Notebook. Full details: **[docs/datadog.md](docs/datadog.md)**.

## Ops

Triage notes are useful once. When the same failure repeats, they need to become a runbook. This skill promotes related triage artefacts into a reusable runbook under `ops/runbooks/`, backlinks the originals, and marks them as resolved. Full details: **[docs/triage-architecture.md](docs/triage-architecture.md)**.

## Productivity

Meetings generate decisions and action items that get lost in memory. The `meet` skill records audio, transcribes locally with Whisper, creates an Obsidian note, and lets Claude structure it into Summary / Decisions / Action Items / Open Questions — all without leaving my vault. Full details: **[docs/meet.md](docs/meet.md)**.

`capture-insights` bridges conversations and the vault: when a debugging session or architecture discussion surfaces durable knowledge, one command extracts it, matches it to existing topic notes, and appends — never overwrites — with a date stamp. Good for CI/CD patterns, root-cause analyses, architectural decisions, and data engineering patterns.

`run` flips the interaction model: instead of typing prompts in the chat box, you write them in `meridian/<slug>/PROMPTS.md` inside your vault, then call `/run` to execute the last pending one. The executed prompt is struck through with a timestamp so the file doubles as a run history.

`second-opinion` is an independent QA layer for agent-produced changes. It spawns four parallel review agents (intent alignment, bug scan, CLAUDE.md compliance, historical context), scores every finding, filters out low-confidence noise, and — if significant issues remain — optionally enters Plan Mode to produce a correction plan.

## Harness

`stack-updater` keeps the stack this repo installs current without being invasive. It runs a read-only scan (distro, package manager, install source of each binary), asks `gentle-ai update` for Gentle AI, Engram and GGA, and compares this repo's skills with what is installed. Tools that are not installed are listed in one line, never offered for installation. Nothing is updated until you approve the exact list. Extra items to track go in `~/.config/personal-os-skills/stack.yaml`.

---

## Setup

`setup.sh` is the single entry point. It lists the harness tools (T3 Code, Claude Code, Codex, Cursor CLI, Gentle AI, Engram) and the skill families, lets you pick what you want, and delegates to the two scripts below.

```bash
./setup.sh                                   # interactive menu (numbers or names; Enter cancels)
./setup.sh --list                            # tools with install status, and skill families
./setup.sh --only claude-code,gentle-ai,ops  # non-interactive: tool ids and/or family names
./setup.sh --only harness --dry-run          # preview without changing anything
./setup.sh --only diagram-design             # a third-party skill from the external catalog
```

Without a terminal (an agent, CI) it refuses to run without `--only`, and asks for `--yes` to confirm. From Claude, run `./setup.sh --list`, ask which items you want, then run `./setup.sh --only <ids> --yes`.

## External skills

Third-party skill repositories live in [`external/catalog.tsv`](external/catalog.tsv): one line per repository (id, `owner/repo`, skills, license, description). Nothing is installed until you pick it, from the `setup.sh` menu or with `--only <id>`. The first entry is [diagram-design](https://github.com/cathrynlavery/diagram-design).

`install-external.sh` detects the harnesses present on the machine (Claude Code, Cursor, Gemini CLI, OpenCode, GitHub Copilot, Codex, Windsurf) and installs the selected skills globally into all of them through the [`skills` CLI](https://github.com/vercel-labs/skills), pinned to a fixed version in the script.

```bash
./install-external.sh list                           # catalog, install status, license, source
./install-external.sh agents                         # harnesses detected on this machine
./install-external.sh install --only diagram-design  # asks for confirmation; --dry-run previews
```

To add a repository, append a line to the catalog. A third-party skill adds instructions (and sometimes scripts) that your agents follow, so review a repository before listing it. Skill-only installs do not include a repository's Claude Code plugin commands.

## Harness bootstrap

`setup.sh` calls three scripts that also work on their own (`install-external.sh` is described above):

- `install.sh` installs the personal skills into the user-level Claude Code and Cursor directories, with optional Obsidian path configuration.
- `bootstrap-harness.sh` installs and configures the surrounding AI coding harness: T3 Code, Claude Code, Codex CLI, Cursor CLI, Gentle AI, and Engram.

The harness bootstrap does not install or configure skills, does not initialise a project, and does not write configuration into repositories. It configures Gentle AI globally with the `full-gentleman` preset, which provides Engram, Context7, GGA, skills, permissions, persona, and theme. Use `--preset minimal` (or `HARNESS_GENTLE_PRESET`) for a lighter setup. `configure` only targets agents whose CLI is installed and reports the rest. `--only t3,claude-code,codex,cursor,gentle-ai,engram` restricts `install` and `configure` to those components, and `./bootstrap-harness.sh list` prints their status. Graphify and CodeGraph remain separate options.

On macOS, the bootstrap also trusts `gentleman-programming/tap` before installing the Gentleman Programming Homebrew packages.

### Harness installation

Review the actions first:

```bash
./bootstrap-harness.sh --dry-run
```

Install missing tools and apply the global configuration:

```bash
./bootstrap-harness.sh all
```

The script is conservative by default: installed tools are detected and left unchanged. To review updates one tool at a time:

```bash
./bootstrap-harness.sh all --update
```

Answer `y` to update an installed tool or `n` to keep it; the script continues with the remaining tools. To update everything without prompts:

```bash
./bootstrap-harness.sh all --update --yes
```

Other useful commands:

```bash
./bootstrap-harness.sh doctor
./bootstrap-harness.sh all --without-t3
./bootstrap-harness.sh configure --agents claude-code,codex
./bootstrap-harness.sh configure --preset full-gentleman
```

Authentication remains manual:

```bash
codex --login
cursor-agent login
claude
```

When you open a repository in T3 Code for the first time, run `/sdd-init` from the agent you choose. The bootstrap intentionally leaves project initialisation under your control. For the complete SDD workflow, use a Planner, Implementer, Reviewer, Fixer, and Final Reviewer thread, selecting a different CLI when you want cross-agent review.

## Installation

### Option 1 — Install script (recommended)

> To choose harness tools and skills in one place, use `./setup.sh` (see [Setup](#setup)). `install.sh` below handles skills only.

Installs the skills you choose, grouped by family (`kubernetes`, `datadog`, `ops`, `productivity`, `harness`), and integrates them with your Obsidian vault if you want. It only installs into harnesses it detects (Claude Code: `claude` or `~/.claude`; Cursor: `cursor-agent` or `~/.cursor`) and reports the ones it skips. Skills without placeholders are installed as **symlinks** (changes in the repo are reflected automatically); skills with placeholders are rendered as a **customised copy** for this machine.

```bash
git clone https://github.com/<your-user>/personal-os-skills.git ~/projects/personal-os-skills
cd ~/projects/personal-os-skills
./install.sh
```

The installer will (optionally) prompt for your Obsidian vault path. If you answer, skills that generate analyses (k8s, datadog, sentry, incidents, runbooks) will land their artefacts under `<vault>/ops/<source>/` directly. If you skip it, they fall back to `./docs/error_analyses/` relative to CWD as before.

Configuration is persisted in `~/.config/personal-os-skills/config.env` and reused on subsequent runs. In a terminal the installer asks which families to install and saves the answer in `~/.config/personal-os-skills/skills.env`. Without a terminal (an agent, CI, or `--no-prompt`) it refuses to install everything by default: pass `--family`, `--skip-family`, `--skill` or `--all`.

Relevant options:

```bash
./install.sh                          # interactive, prompts for vault
./install.sh --no-prompt --all        # no prompts; needs a selection (--all, --family, ...) unless one is saved
./install.sh --reconfigure            # re-runs the prompt even if config already exists
./install.sh --vault ~/pkm/pkm        # non-interactive vault
./install.sh --ops-dir ~/pkm/pkm/ops  # non-interactive ops dir
./install.sh --list                   # lists skills grouped by family (kubernetes, datadog, ops, productivity, harness)
./install.sh --family ops,productivity   # installs only those families
./install.sh --skip-family datadog,kubernetes  # installs everything except those families
./install.sh --skill run,meet         # installs only those skills
./install.sh --all                    # ignores the saved selection
./install.sh --claude-only            # installs only into ~/.claude/skills
./install.sh --cursor-only            # installs only into ~/.cursor/skills
./install.sh --copy                   # copy instead of symlink (for skills without placeholders)
./install.sh --uninstall              # removes previously installed entries
./install.sh --dry-run                # shows what it would do without touching anything
./install.sh --force                  # overwrites existing entries
```

Default paths:

- Claude Code (user scope): `~/.claude/skills/<skill>/SKILL.md`
- Cursor (user scope):      `~/.cursor/skills/<skill>/SKILL.md`
- Obsidian ops tree:        `<vault>/ops/{k8s,datadog,sentry,incidents,runbooks}/`
- Obsidian meetings tree:   `<vault>/meetings/{notes,transcriptions}/`
- Obsidian template:        `<vault>/templates/meeting.md`
- Raycast scripts:          `~/Library/Application Support/Raycast/scripts/`

> **Note**: do NOT use `~/.cursor/skills-cursor/` for personal skills — that path is reserved by Cursor for automatically managed skills.

**Important**: if you edit a SKILL.md that contains placeholders, re-run `./install.sh` to re-render the installed copy (a symlink is not enough).

### Option 2 — Claude Code plugin marketplace

The repo ships a `.claude-plugin/marketplace.json`, so you can install the skills as plugins from Claude Code:

```text
/plugin marketplace add <your-user>/personal-os-skills
/plugin
```

In the **Discover** tab pick the plugin and choose **Install for you (user scope)**. Restart Claude Code.

### Option 3 — Manual one-off install

If you only want a specific skill:

```bash
# Claude
ln -s "$PWD/skills/k8s-error-analyzer" ~/.claude/skills/k8s-error-analyzer
# Cursor
ln -s "$PWD/skills/k8s-error-analyzer" ~/.cursor/skills/k8s-error-analyzer
```

## Repo Layout

```text
personal-os-skills/
├── .claude-plugin/
│   └── marketplace.json     # Claude Code plugin marketplace manifest
├── bootstrap-harness.sh     # AI coding harness installer/configurator
├── install.sh               # Personal skills installer
├── skills/
│   └── <skill-name>/
│       └── SKILL.md         # frontmatter + skill instructions
└── README.md
```

Every skill lives in `skills/<name>/` with a `SKILL.md` that starts with YAML frontmatter:

```yaml
---
name: my-skill
description: What the skill does and when to use it (this feeds the automatic selector).
---
```

## Adding a New Skill

1. Create `skills/<name>/SKILL.md` with `name` and `description` in the frontmatter.
2. Add the skill to the **Available Skills** table in this README.
3. (Optional) Register a plugin entry for it in `.claude-plugin/marketplace.json`.
4. Run `./install.sh` again so Claude and Cursor pick it up.

## License

MIT
