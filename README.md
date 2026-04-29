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


## Kubernetes

I manage multiple clusters and namespaces. When a pod crashes or a deployment is burning money with oversized requests, I need answers fast — not a 20-minute kubectl session. These skills read logs and metrics, produce a structured report, and drop it into `ops/k8s/` so the analysis is searchable later. Full details: **[docs/k8s.md](docs/k8s.md)**.

## Datadog

Datadog is my primary observability stack. Instead of switching between APM, logs, and metrics dashboards manually, the triage orchestrator plans the investigation, delegates to specialised sub-skills, and consolidates everything into a single report with a linked Datadog Notebook. Full details: **[docs/datadog.md](docs/datadog.md)**.

## Ops

Triage notes are useful once. When the same failure repeats, they need to become a runbook. This skill promotes related triage artefacts into a reusable runbook under `ops/runbooks/`, backlinks the originals, and marks them as resolved. Full details: **[docs/triage-architecture.md](docs/triage-architecture.md)**.

## Productivity

Meetings generate decisions and action items that get lost in memory. The `meet` skill records audio, transcribes locally with Whisper, creates an Obsidian note, and lets Claude structure it into Summary / Decisions / Action Items / Open Questions — all without leaving my vault. Full details: **[docs/meet.md](docs/meet.md)**.

---

## Installation

### Option 1 — Install script (recommended)

Installs all skills in this repo and integrates them with your Obsidian vault if you want. Skills without placeholders are installed as **symlinks** (changes in the repo are reflected automatically); skills with placeholders are rendered as a **customised copy** for this machine.

```bash
git clone https://github.com/<your-user>/personal-os-skills.git ~/projects/personal-os-skills
cd ~/projects/personal-os-skills
./install.sh
```

The installer will (optionally) prompt for your Obsidian vault path. If you answer, skills that generate analyses (k8s, datadog, sentry, incidents, runbooks) will land their artefacts under `<vault>/ops/<source>/` directly. If you skip it, they fall back to `./docs/error_analyses/` relative to CWD as before.

Configuration is persisted in `~/.config/personal-os-skills/config.env` and reused on subsequent runs.

Relevant options:

```bash
./install.sh                          # interactive, prompts for vault
./install.sh --no-prompt              # uses previous config or legacy defaults, no prompts
./install.sh --reconfigure            # re-runs the prompt even if config already exists
./install.sh --vault ~/pkm/pkm        # non-interactive vault
./install.sh --ops-dir ~/pkm/pkm/ops  # non-interactive ops dir
./install.sh --claude-only            # installs only into ~/.claude/skills
./install.sh --cursor-only            # installs only into ~/.cursor/skills-cursor
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
ln -s "$PWD/skills/k8s-error-analyzer" ~/.cursor/skills-cursor/k8s-error-analyzer
```

## Repo Layout

```text
personal-os-skills/
├── .claude-plugin/
│   └── marketplace.json     # Claude Code plugin marketplace manifest
├── skills/
│   └── <skill-name>/
│       └── SKILL.md         # frontmatter + skill instructions
├── install.sh               # cross-platform installer (symlink/copy)
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
