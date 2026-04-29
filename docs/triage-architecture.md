# Triage & Error-Detection Architecture

This repo centralises the skills I use to diagnose problems (Kubernetes, Datadog, Sentry, etc.) and ships a convention for **where their output goes** and **how it flows from an ad-hoc observation to durable operational knowledge**.

The goal is to stop generating throw-away logs in random folders and instead build a queryable, promotable ops knowledge base inside my Obsidian vault.

---

## 1. Mental model

```
    ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
    │  DETECTION   │──────▶│    TRIAGE    │──────▶│  RESOLUTION  │
    │ (observe)    │       │  (analyse)   │       │  (act/learn) │
    └──────┬───────┘       └──────┬───────┘       └──────┬───────┘
           │                      │                      │
           ▼                      ▼                      ▼
     alerts, pages,         skill output             incidents,
     "something's           markdown file            runbooks,
     weird" moment          in ops/<source>/          permanent fix
```

Every skill in this repo lives on the *Triage* lane: they turn a vague "something is wrong in X" into a structured markdown artefact with evidence, root cause, and recommended actions.

Those artefacts then flow towards durable knowledge through a **promotion pipeline**.

---

## 2. The ops/ folder taxonomy

All skill output lands inside your Obsidian vault at `ops/` (configured via `install.sh` and injected into each skill). The structure is:

```
<vault>/ops/
├── _index.md                  # MOC with Dataview queries over the whole tree
├── k8s/                       # kubectl/pod-level analyses
│   ├── _index.md
│   └── 2026-04-20-payments-staging-checkout-web.md
├── datadog/
│   ├── triage/                # "why did metric X spike?" ad-hoc investigations
│   ├── monitors/              # analyses anchored to a specific monitor
│   └── dashboards/            # notes on saved/curated dashboards
├── sentry/                    # error-selection / issue triage
├── incidents/                 # formal post-mortems (rare, high-severity)
│   └── 2026-03-15-airflow-outage.md
└── runbooks/                  # reusable procedures (promoted from triage)
    └── msk-connector-lag.md
```

### Why `ops/` as a top-level folder

- **Orthogonal to knowledge**: `notes/Kubernetes.md` stays a perennial MOC. `ops/k8s/2026-...` is an artefact with a timestamp. They link to each other but don't mix.
- **Orthogonal to projects**: `meridian/<project>/` is about plans/tasks. `ops/<source>/` is about *what happened*. Cross-project issues live happily here without duplication.
- **Source-first routing**: each skill knows exactly one destination folder. No ambiguity when automating.

### Naming convention

Always **date-first**, ISO 8601, so lexical sort == chronological sort:

```
YYYY-MM-DD-<scope>-<resource>.md
YYYY-MM-DD-HHMM-<scope>-<resource>.md     # if multiple per day
```

### Frontmatter contract

Every artefact starts with YAML frontmatter so `_index.md` can use Dataview queries over `status`, `severity`, `source`, `env`, `project`, etc.

**Never put `[[wikilinks]]` inside frontmatter** — the quoted form (`- "[[Foo]]"`) does not resolve as a link in this vault and the unquoted form (`- [[Foo]]`) is invalid YAML. Keep frontmatter values as plain strings; put every wikilink in a `## Related` / `## References` / `## History` section in the body.

```yaml
---
title: <short human title>
created: 2026-04-20 18:03
source: k8s                 # k8s | datadog | sentry | incident | runbook
env: staging                # staging | prod | local | other
namespace: payments-staging
project: payments-platform
resource: checkout-web
severity: warn              # info | warn | error | critical
status: open                # open | mitigated | resolved | monitoring
tags: [ops, k8s, triage]
---
```

And in the body, near the bottom:

```markdown
## Related

- [[Kubernetes]]
- [[Observability]]
- [[Payments Platform]]
```

---

## 3. The promotion pipeline

Not every triage note should be read again. Some should die quietly. Others should become part of the oncall toolkit. The rule of thumb:

```
                  ┌────────────┐
                  │  TRIAGE    │  ← every skill output lands here by default
                  │  ops/*/…   │
                  └─────┬──────┘
          repeats?      │       severe / cross-team impact?
              ┌─────────┴──────────┐
              ▼                    ▼
        ┌───────────┐        ┌──────────────┐
        │ RUNBOOK   │        │   INCIDENT   │   ← disciplined post-mortem
        │ runbooks/ │        │  incidents/  │
        └─────┬─────┘        └──────┬───────┘
              │                     │
              └──────────┬──────────┘
                         ▼
                   ┌───────────┐
                   │ KNOWLEDGE │  ← permanent MOCs: notes/Kubernetes.md,
                   │  notes/   │     notes/Observability.md, etc.
                   └───────────┘
```

### Rules for promotion

| From | To | Trigger |
|------|----|---------|
| `ops/<source>/` | `ops/runbooks/` | Same class of issue has been triaged ≥ 2 times, OR it's the kind of thing oncall should know how to resolve blind. |
| `ops/<source>/` | `ops/incidents/` | User-visible impact, cross-team response, or any postmortem-worthy event (SEV-1/SEV-2). |
| `ops/runbooks/` | `notes/<Topic>.md` | The runbook reveals a generalisable concept / pattern worth a standalone knowledge note. |
| *anywhere* | `status: resolved` in frontmatter | Problem is fixed and verified. Keep the note for historical reference and link-back. |

### What stays where

- **`ops/<source>/`**: evidence + analysis of a specific moment in time. **Never mutated** after creation (except to update `status:` or add a "Resolution" section at the bottom).
- **`ops/runbooks/`**: *living* documents. Update them every time the procedure changes.
- **`ops/incidents/`**: **frozen** post-mortem. The incident ran at a specific time, its RCA is historical. Follow-ups live elsewhere (tasks, runbooks).
- **`notes/`**: your perennial second-brain. Nothing operational or time-bound.

---

## 4. Worked example (end-to-end)

Let's trace a realistic scenario all the way through the pipeline.

### Day 0 — Detection

Datadog pages you: "`checkout-web` Deployment Available = 0/1 for > 15m, staging".

You don't know if it's the image, the probes, the node, or traffic. You need to *see what's happening*.

### Day 0 — Triage (skill output)

You run the `k8s-error-analyzer` skill:

```
> Analyse the failures in the checkout-web pods in payments-staging
```

The skill:
1. Inspects pod status, events and logs.
2. Captures every `kubectl` command in an audit trail.
3. Writes the analysis to
   `~/pkm/pkm/ops/k8s/2026-04-20-payments-staging-checkout-web.md`
   with frontmatter `severity: error`, `status: open`, `source: k8s`.

Key finding: container listens on 80 but probes hit 3000 → liveness fails forever.

### Day 0 — Resolution action

You open `meridian/infra-charts/tasks/` and create a task: *"Align probe port with nginx listen port in checkout-web"*. You link it back to the triage note with `[[ops/k8s/2026-04-20-payments-staging-checkout-web]]`.

Once merged and verified, you edit the triage note and change `status: open` → `status: resolved`, adding a "Resolution" section at the bottom with the PR link.

### Day 12 — It happens again (different service)

Two weeks later, `checkout-api` hits the exact same kind of probe misalignment. You generate a second triage note: `2026-05-02-payments-staging-checkout-api.md`.

Now you have two instances of the same failure class → **promote to runbook**.

### Day 12 — Promotion to runbook

You create `ops/runbooks/probe-port-misalignment.md`. The frontmatter stays plain strings (YAML-safe) and the wikilinks live at the bottom of the body in a `## Related` / `## History` section:

```yaml
---
title: Probe / containerPort / Service targetPort misalignment
tags: [runbook, k8s, probes]
applies_to: [helm-charts]
first_seen: 2026-04-20
last_updated: 2026-05-02
status: active
source_triages:
  - ops/k8s/2026-04-20-payments-staging-checkout-web
  - ops/k8s/2026-05-02-payments-staging-checkout-api
---
```

Body: symptoms, detection checklist, the three possible fixes, the one we prefer by default, and a rollback procedure. At the bottom, a `## Related` section with unquoted wikilinks:

```markdown
## Related

- [[ops/k8s/2026-04-20-payments-staging-checkout-web]]
- [[ops/k8s/2026-05-02-payments-staging-checkout-api]]
- [[Kubernetes]]
```

This is now the canonical doc anyone on-call consults when they see a liveness-probe loop.

### Day 30 — Major incident

Unrelated: production `msk-connector` stops forwarding to Snowflake during peak. Revenue-impacting. SEV-2.

During the firefight, a `k8s-error-analyzer` triage note gets generated. Once the dust settles, you open `ops/incidents/2026-05-20-msk-snowflake-lag.md` and write the post-mortem: timeline, contributing factors, what we changed, what we won't change, follow-ups.

The post-mortem links to:
- the original triage note (evidence),
- the runbook we created or updated,
- the tasks spawned (`[[meridian/infra-charts/tasks/...]]`).

### Day N — Knowledge promotion

After a handful of similar Datadog-vs-K8s coordination incidents, you notice a pattern: *probe alignment with actual listen ports* is a recurring cross-cutting concern. You write a note in `notes/Kubernetes.md` (or a standalone `notes/Kubernetes Probes.md`) explaining the general principle. All the runbooks and triage notes backlink to it.

The second-brain now encodes the **principle**, not just the operational steps.

---

## 5. Dataview queries that keep this honest

Put these in `ops/_index.md` so the taxonomy actually pays off:

```dataview
TABLE file.ctime AS Created, source, env, severity, status
FROM "ops"
WHERE source
SORT file.ctime DESC
LIMIT 30
```

Open items across all sources:

```dataview
TABLE source, env, severity, namespace
FROM "ops"
WHERE status = "open"
SORT severity DESC, file.ctime DESC
```

Candidates for promotion to runbook (repeated symptoms):

```dataview
TABLE rows.file.link AS Analyses
FROM "ops"
WHERE source AND status
GROUP BY namespace + " / " + string(source)
WHERE length(rows) >= 2
```

---

## 6. How skills plug into all this

Each skill in `skills/<name>/SKILL.md` uses `{{PLACEHOLDER}}` tokens for its output directory. At install time, `install.sh`:

1. Prompts for your Obsidian vault path (optional; skip = fall back to local `./docs/...`).
2. Derives the per-source paths (`K8S_ANALYSES_DIR`, `DATADOG_ANALYSES_DIR`, etc.).
3. Persists them in `~/.config/personal-os-skills/config.env`.
4. For any skill that contains placeholders, it renders a customised copy into `~/.claude/skills/<name>/` and `~/.cursor/skills-cursor/<name>/` with the paths baked in.
5. Bootstraps `ops/_index.md` and the source subfolders on the vault if they don't already exist.

Re-run `./install.sh --reconfigure` any time you want to change paths. Re-run `./install.sh` after editing a SKILL.md so the rendered copies pick up the changes.

---

## 7. Adding a new source

To add a new source (e.g. "GitHub Actions failure triage"):

1. Create `skills/gha-error-analyzer/SKILL.md` using `{{GHA_ANALYSES_DIR}}` (or reuse an existing placeholder) as output dir.
2. Add the variable to `install.sh` (`PLACEHOLDER_VARS`, `derive_paths`, `save_config`, `bootstrap_ops_tree`).
3. Add a row to the README's **Available Skills** table.
4. Run `./install.sh`.

That's it — the artefacts will flow through the exact same triage → runbook → incident → knowledge pipeline.
