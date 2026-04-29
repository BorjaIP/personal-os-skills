# Personal OS Skills

A personal collection of skills for [Claude Code](https://docs.claude.com/en/docs/claude-code) and [Cursor](https://cursor.com). It centralises in a single repository the capabilities I use daily so I can install them at the user level on any machine.

> Inspired by [ArtemXTech/personal-os-skills](https://github.com/ArtemXTech/personal-os-skills).

## Context

I'm an AI Data Platform Engineer. My day-to-day spans DevOps, MLOps, and LLMOps. This repo is one piece of a three-repo system that forms my personal workflow:

| Repo | Purpose |
|------|---------|
| **personal-os-skills** (this repo) | Claude Code / Cursor skills for triage, observability, cost optimisation, and meeting notes. |
| [**pkm**](https://github.com/borjairigoyen/pkm) | Obsidian vault — my Second Brain. Notes, meetings, ops artifacts, and task management live here. Skills write their output directly into this vault under `ops/`. |
| [**opstoolkit**](https://github.com/borjairigoyen/opstoolkit) | Boilerplate collection for DevOps/MLOps/LLMOps: Dockerfiles, Kubernetes manifests, Istio configs, devcontainers, and helper scripts. |

The three repos form a closed loop: **skills** generate artifacts and analyses, the **vault** captures and organises that knowledge, and **opstoolkit** provides reusable templates for the infrastructure work that comes out of it.

## Triage & Error-Detection Architecture

Every diagnostic / triage skill in this repo shares the same output architecture: artefacts land under `ops/<source>/` inside your Obsidian vault, with a well-defined promotion pipeline (**triage → runbook → incident → knowledge**).

Full document: **[docs/triage-architecture.md](docs/triage-architecture.md)**.

Summary:

- Detection → the skill produces a Markdown artefact with evidence (`ops/<source>/YYYY-MM-DD-*.md`).
- Ad-hoc triage → lives in `ops/k8s/`, `ops/datadog/`, `ops/sentry/`, …
- If the same failure class repeats → promote it to `ops/runbooks/`.
- If there is severe or cross-team impact → `ops/incidents/` with a post-mortem.
- Generalisable knowledge graduates to `notes/` as a perennial MOC.

## Available Skills

| Skill | Source | Destination | Description |
|-------|--------|-------------|-------------|
| [k8s-error-analyzer](skills/k8s-error-analyzer/) | `k8s` | `ops/k8s/` | Analyzes Kubernetes pod failures by reading logs (with label selector support), identifies errors and generates analysis reports. |
| [k8s-optimizer-cost](skills/k8s-optimizer-cost/) | `k8s-cost` | `ops/k8s-cost/` | Analyzes cost and right-sizing of a namespace's workloads using 7 days of Datadog metrics and PerfectScale's policy-driven methodology (MaxSavings / Balanced / ExtraHeadroom / MaxHeadroom). Usage guide: **[docs/k8s-optimizer-cost.md](docs/k8s-optimizer-cost.md)**. |
| [datadog-triage](skills/datadog-triage/) | `datadog` | `ops/datadog/triage/` | End-to-end Datadog triage orchestrator. Entry point for incident / monitor / service / alert triage. Plans the investigation, delegates to the three Datadog sub-skills, consolidates findings into a master report + master Datadog notebook. |
| [datadog-service-health](skills/datadog-service-health/) | `datadog` | `ops/datadog/triage/` | APM-centric service health check. Latency p50/p95/p99, error rate, throughput, representative failing traces, dependency graph, monitor coverage, deploy correlation. |
| [datadog-logs-analyzer](skills/datadog-logs-analyzer/) | `datadog` | `ops/datadog/triage/` | Log investigation via pattern clustering + attribute discovery + DDSQL aggregation. Produces top-patterns-over-time + top-offenders-by-attribute analysis. |
| [datadog-metrics-investigator](skills/datadog-metrics-investigator/) | `datadog` | `ops/datadog/triage/` | Metric spike / anomaly investigation. Resolves metadata, queries sliced timeseries, compares to baseline, reuses existing dashboards / monitors, supports Cloud Cost metrics. |
| [datadog-report-publisher](skills/datadog-report-publisher/) | `datadog` (utility) | `ops/datadog/triage/` | Shared publisher invoked by the Datadog skills: writes the Markdown artefact AND creates a bidirectionally-linked Datadog Notebook with embedded widgets. |
| [create-runbook](skills/create-runbook/) | promotion | `ops/runbooks/` | Promotes ≥2 related triage notes into a reusable runbook under `ops/runbooks/`. Backlinks the source triage notes and flips their `status` to `resolved`. |
| [meet](skills/meet/) | meetings | `meetings/` | Records meeting audio, transcribes with Whisper, creates Obsidian notes with wikilinks. AI enhancement skill for structuring raw notes into Summary / Decisions / Action Items / Open Questions. See [Meet — Meeting Notes](#meet--meeting-notes). |

### Datadog skill suite — how they fit together

```
                ┌────────────────────┐
  user input ──▶│  datadog-triage    │  (orchestrator: plan + delegate + consolidate)
                └────────┬───────────┘
                         │
           ┌─────────────┼────────────────────┐
           ▼             ▼                    ▼
  ┌───────────────┐ ┌──────────────────┐ ┌────────────────────────┐
  │ service-health│ │ logs-analyzer    │ │ metrics-investigator   │
  │  (APM)        │ │ (patterns+DDSQL) │ │ (timeseries+widgets)   │
  └───────┬───────┘ └─────────┬────────┘ └─────────┬──────────────┘
          └─────────────────┬─┴──────────────────────┘
                            ▼
                 ┌───────────────────────┐
                 │ datadog-report-       │  writes MD to ops/datadog/triage/
                 │ publisher             │  + creates Datadog Notebook (linked)
                 └───────────────────────┘
```

Every sub-skill delegates final publication to `datadog-report-publisher`, which writes an Obsidian-compatible Markdown artefact AND creates a persistent Datadog Notebook with embedded widgets. Both are linked bidirectionally (notebook URL in MD header, MD path in notebook first cell). Recurring triage notes can be promoted to a runbook via the `create-runbook` skill.

### Further reading & inspiration

For `k8s-optimizer-cost` specifically, the design draws from PerfectScale's Podfit methodology and the official Kubernetes docs. Recommended reading:

- [PerfectScale — Podfit (vertical pod right-sizing)](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing)
- [PerfectScale — Optimization Policy customization](https://docs.perfectscale.io/customize-workflow/optimization-policy-customization)
- [PerfectScale — HPA view](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing#hpa-view)
- [PerfectScale — LimitRange and ResourceQuota](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/limitrange-and-resourcequota)
- [PerfectScale — Muted workload](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/muted-workload)
- [Kubernetes — Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes — Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Kubernetes — Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)

---

## Meet — Meeting Notes

A local, AI-enhanced meeting notes workflow inspired by Granola. Records your voice during meetings, transcribes it with Whisper, creates an Obsidian note, and lets any Claude agent structure your sparse bullet points into a full meeting report.

### How it works

```
meet start standup          # starts mic recording (sox rec in background)
  → take a few notes in Obsidian during the meeting
meet stop                   # stops recording → Whisper transcription → Obsidian notes created
  → ask Claude: /meet       # AI enhancement: Summary, Decisions, Action Items, Open Questions
```

### Vault structure

```
pkm/
  meetings/
    notes/           ← YYYY-MM-DD-slug.md  (enhanced notes, one per meeting)
    transcriptions/  ← YYYY-MM-DD-slug.md  (raw Whisper output)
  templates/
    meeting.md       ← Obsidian Templater template (auto-inserted wikilink)
```

Each note in `meetings/notes/` contains a wikilink pointing to its transcription:

```markdown
[[meetings/transcriptions/2026-04-27-standup]]
```

Wikilinks live in the **body** of the note, never in YAML frontmatter (Obsidian does not resolve links in frontmatter).

### System dependencies

| Dependency | Install | Used for |
|---|---|---|
| `sox` | `brew install sox` | `rec` command — records audio from mic |
| `mlx-whisper` | included in `meet` package | Apple Silicon transcription (fast, local) |

`sox` is a C binary — it is the only dependency that cannot be installed by `uv`. Everything else is handled by the Python package.

### Installing the CLI

The `meet/` directory is a standalone Python package. Install it as a [uv tool](https://docs.astral.sh/uv/concepts/tools/) so the `meet` command is available globally:

```bash
brew install sox                                    # system dependency (one-time)
uv tool install --python 3.13 ./meet               # installs meet to ~/.local/bin
```

Verify:

```bash
meet --help
meet status   # should print "No active recording."
```

> `uv tool install` puts the `meet` binary at `~/.local/bin/meet`. Make sure `~/.local/bin` is in your shell `$PATH` (uv adds this automatically if you follow the uv install instructions).

### CLI commands

```bash
meet start <slug>            # start recording (slug = short name, e.g. "standup")
meet stop                    # stop + transcribe + create Obsidian notes
meet stop --no-transcribe    # stop without running Whisper (faster, no transcript)
meet stop --model mlx-community/whisper-large-v3-turbo  # use a larger model
meet status                  # check whether a recording is active
```

The slug is sanitised to lowercase kebab-case. Recording state is persisted to `~/.meet/current.json` so `meet stop` works from any shell or Raycast.

### Whisper model quality vs speed

| Model | Speed (Apple M-series) | Quality |
|---|---|---|
| `mlx-community/whisper-small` | Fast (~30s for 1h meeting) | Good for most meetings |
| `mlx-community/whisper-large-v3-turbo` | Moderate | Better for accents / technical jargon |
| `mlx-community/whisper-large-v3` | Slow | Best accuracy |

Default is `whisper-small`. Override with `meet stop --model mlx-community/whisper-large-v3-turbo`.

### AI enhancement skill

Once the note is created, open it in Obsidian, add any notes you took during the meeting (a few bullet points is enough), then ask Claude to enhance it:

```
/meet                                              # in Claude Code
enhance my meeting notes at meetings/notes/2026-04-27-standup.md
```

Claude reads the note and the auto-detected transcription, and rewrites the file in-place:

```markdown
---
date: 2026-04-27
attendees: [borja, alice, rob]
tags: [meeting]
project: infra
---

[[meetings/transcriptions/2026-04-27-standup]]

## Summary
...

## Decisions
...

## Action Items
- [ ] Investigate PerfectScale cost impact — @rob
- [ ] Open ticket for node pool review — @alice

## Open Questions
- Is the staging environment also affected?

## Raw Notes
(your original bullet points, verbatim)
```

The skill never modifies YAML frontmatter, never invents information, and always preserves your raw notes at the bottom.

### Activating from Raycast

`install.sh` installs two Raycast Script Commands: **Start Meeting Recording** and **Stop Meeting Recording**. They appear in Raycast as soon as you add your scripts directory.

**One-time setup in Raycast:**

1. Open Raycast → Settings (`⌘,`) → Extensions → Script Commands
2. Click **Add Directory** and select the directory where `install.sh` copied the scripts (default: `~/Library/Application Support/Raycast/scripts/`)
3. Search "Meeting" in Raycast — both commands appear

**Why no venv activation is needed:** `uv tool install` puts `meet` at `~/.local/bin/meet`. The Raycast scripts prepend `~/.local/bin` to `$PATH` before calling `meet`, so no virtual environment activation is required. Raycast's sandboxed shell does not inherit your shell's `$PATH`, which is why the PATH export is explicit in the script.

**Usage:**
- `Start Meeting Recording` → Raycast prompts for a slug → starts recording in the background
- `Stop Meeting Recording` → stops sox, runs Whisper, creates Obsidian notes, shows confirmation

### Obsidian Templater template

`install.sh` copies `skills/meet/vault/templates/meeting.md` to `<vault>/templates/meeting.md`. If you have the [Templater plugin](https://github.com/SilverStreet/Templater) installed, you can create a new meeting note from this template and it will auto-fill the date and wikilink.

To use: in Obsidian, open the Command Palette → **Templater: Create new note from template** → select `meeting`.

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
