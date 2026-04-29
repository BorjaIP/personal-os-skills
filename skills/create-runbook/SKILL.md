---
name: create-runbook
description: Promote one or more triage notes in ops/<source>/ into a living runbook under ops/runbooks/. Use when the same class of failure has been observed two or more times, when the user says "create a runbook", "promote this to a runbook", or when an on-call procedure for a known failure pattern is needed.
---

# Create Runbook

Turns recurring triage notes into a living, reusable runbook inside the Obsidian `ops/runbooks/` folder. Runbooks are **living documents**: unlike triage notes (frozen snapshots of a moment), they are updated every time the procedure changes.

Refer to `personal-os-skills/docs/triage-architecture.md` for the full promotion pipeline context (**triage → runbook → incident → knowledge**).

## When to Use

Apply this skill when **any** of the following is true:

1. The same class of failure appears in ≥ 2 triage notes under `ops/<source>/`.
2. On-call has handled (or is expected to handle) the same failure mode "blind" at 3am.
3. The user explicitly asks to "create a runbook", "promote to runbook", "document this procedure".
4. A fix exists but touches several systems (chart change, cluster setting, third-party tool) and a checklist would save time next time.

Do **NOT** use for one-off postmortems or SEV-1/SEV-2 incidents — those go to `ops/incidents/` instead (see "Runbook vs Incident" below).

## Inputs

Collect from the user or infer from context:

1. **Triage note paths** (required, ≥ 1): absolute paths or vault-relative links to the source analyses.
2. **Runbook slug** (optional): kebab-case filename stem, e.g. `airflow-db-clean-oom`. If missing, derive from the common resource/symptom across the triage notes.
3. **Applies to** (optional): systems/services the runbook covers, e.g. `[airflow, helm-charts, perfectscale]`.

If fewer than two triage notes are provided, warn the user that promotion to runbook is usually only justified after a second occurrence — but proceed if they confirm.

## Workflow

### Step 1 — Read and align the evidence

Read every triage note in full. Extract and cross-compare:

- **Symptom surface**: what does the user see first? (alert name, pod state, metric shape, error message)
- **Detection signals**: kubectl output, Datadog metric, log line that uniquely identifies this class.
- **Root cause**: the single sentence explanation. All triage notes must agree. If they don't, escalate to the user — you may be merging two different failure classes.
- **Affected resources**: services, environments, namespaces that hit it.
- **Fix(es) applied**: the action that resolved each occurrence. Note divergences.
- **Verification**: how we confirmed the fix worked.

### Step 2 — Decide the runbook scope

Pick the narrowest useful scope. A good runbook answers **one class of failure**, not "everything about Airflow".

Name examples:
- ✅ `airflow-db-clean-oom.md` — one failure mode, one resource class
- ✅ `k8s-probe-port-misalignment.md` — one pattern, multiple services
- ❌ `airflow-problems.md` — too broad, will rot

### Step 3 — Generate the runbook file

Write to `{{RUNBOOKS_DIR}}/<slug>.md` using the **Runbook Template** below. If `{{RUNBOOKS_DIR}}` was not substituted (i.e. Obsidian not configured at install time), fall back to `./docs/runbooks/` and warn the user.

Ensure the directory exists:

```bash
mkdir -p "{{RUNBOOKS_DIR}}"
```

### Step 4 — Backlink the triage notes

For each source triage note, append (at the very bottom, after the existing content — do not rewrite the body) a short "Promoted to runbook" section if it doesn't already have one:

```markdown

---

## Promoted to runbook

This triage has been promoted to `[[<slug>]]` (see `ops/runbooks/<slug>.md`).
```

And flip its `status:` frontmatter to `resolved` if it isn't already.

### Step 5 — Report to the user

Output:
- Path to the new runbook.
- Which triage notes were backlinked.
- Candidate follow-ups (unresolved risks mentioned in the triages that the runbook alone cannot fix — e.g. "add alerting", "update LimitRange").

## Runbook Template

**IMPORTANT — wikilinks policy for this vault**:
- **Never** put `[[wikilinks]]` inside YAML frontmatter. The quoted form (`- "[[Foo]]"`) does not resolve as a link in this Obsidian setup, and unquoted form (`- [[Foo]]`) breaks YAML parsing.
- Keep frontmatter values as plain strings (tags, status, dates, owners, etc.).
- Put every `[[wikilink]]` in a dedicated `## Related` / `## References` / `## History` section in the **body** of the note. Use unquoted `- [[Foo]]`, which is exactly the pattern used across `notes/`.

```markdown
---
title: <One-line human-readable title of the failure class>
tags: [runbook, <topic-tags>]
applies_to: [<systems-or-services>]
first_seen: <YYYY-MM-DD from earliest triage>
last_updated: <YYYY-MM-DD today>
severity_when_triggered: <info|warn|error|critical>
status: active   # active | archived
owners: [<team-or-person>]
source_triages:
  - ops/<source>/<triage-1>
  - ops/<source>/<triage-2>
---

# <Title>

## TL;DR

One paragraph: what fails, why it fails, what to do. Written so someone paged at 3am can skim it in 30 seconds.

## Symptoms

How to recognise this failure. Bullet list of observable signals:

- Alert: `<alert name / Datadog monitor>`
- Pod state: e.g. `OOMKilled`, `CrashLoopBackOff`, `0/1 Ready for > Nm`
- Log line: `<copy the diagnostic line verbatim>`
- Metric shape: e.g. "memory ramps to limit then drops to 0 within Ns"

## Detection checklist

Quick commands/queries to confirm this is the right runbook for the situation:

```bash
# Confirm the failure class
<command 1>
<command 2>
```

Expected output that says "yes, this is it":

```text
<evidence excerpt>
```

## Root cause

One or two paragraphs describing *why* it happens. Link out to the knowledge MOC (e.g. `[[Kubernetes]]`) for background concepts — do not re-teach Kubernetes here.

## Resolution

Numbered steps. Each step includes the exact command/PR change and expected result.

1. **<Step title>** — what, why, how:
   ```bash
   <command>
   ```
   Expected: `<what success looks like>`.

2. **<Next step>** …

### Verification

After the resolution, confirm the fix with:

```bash
<verification command>
```

Expected: `<success criteria>`.

## Rollback

If the fix makes things worse:

1. <revert command / PR>
2. <notify channel>

## Known variants

Sub-cases where the procedure diverges (e.g. different env, different resource flavour). Keep short.

## Prevention / follow-ups

Longer-term work to eliminate the failure class. Cross-reference tasks in `meridian/<project>/tasks/` if they exist.

- [ ] <follow-up 1>
- [ ] <follow-up 2>

## History

Use unquoted body-wikilinks — they render correctly here (unlike frontmatter quoted ones).

| Date | Triage note | Environment | Resolved by |
|------|-------------|-------------|-------------|
| <YYYY-MM-DD> | [[ops/<source>/<file>]] | staging/prod | PR link |
| <YYYY-MM-DD> | [[ops/<source>/<file>]] | staging/prod | PR link |

## References

- [[<related MOC>]]
- [[Kubernetes]]
- External: <docs link if any>
```

## Runbook vs Incident

Use this table to decide where a triage note should be promoted **in addition to** the runbook:

| Condition | Outcome |
|-----------|---------|
| Repeated symptom, procedural fix exists | Runbook only (`ops/runbooks/`) |
| User-visible impact, cross-team response, SEV-1/SEV-2 | Runbook + Incident post-mortem (`ops/incidents/`) |
| One-off weird thing, no clear fix | Keep as triage, do not promote |

An incident is a **frozen post-mortem** for a specific event; a runbook is a **living procedure**. They are complementary, not alternatives.

## Best Practices

1. **One failure class per runbook.** If you find yourself writing "or alternatively", split the runbook.
2. **Commands over prose.** Every step should be something the on-call can copy-paste.
3. **Show expected output.** It's how the reader knows the step worked.
4. **Keep `last_updated` honest.** Edit it on every change, even a typo.
5. **Link, don't repeat.** Background concepts live in `notes/`, not inside runbooks.
6. **Update `History` on every re-trigger.** Adds the new triage note as a row and flips its `status:` to `resolved`.
7. **Retire runbooks.** If the underlying cause is permanently fixed (chart change, architectural fix), set `status: archived` in frontmatter and note the resolution in `History`.

## Anti-Patterns

- ❌ Copy-pasting the whole triage note as the runbook body. A runbook is **not** a retrospective; it's a procedure.
- ❌ Adding every possible related command. Keep the resolution focused on the happy path; edge cases go under "Known variants".
- ❌ Creating a runbook after a single triage. Wait for the second occurrence unless on-call explicitly asks.
- ❌ Putting `[[wikilinks]]` in frontmatter. They don't render in this vault. Keep frontmatter as plain strings and use body sections for links.
- ❌ Omitting the `## Related` / `## References` / `## History` body sections. Dataview queries and manual navigation rely on those body wikilinks.

## Example

**Input**: two triage notes at
- `{{K8S_ANALYSES_DIR}}/2026-03-10-1109-airflow-staging-airflow-db-clean.md`
- `{{K8S_ANALYSES_DIR}}/2026-03-23-1019-airflow-staging-airflow-db-clean.md`

Both reports identify OOMKilled during `airflow db clean`, both trace it to PerfectScale shrinking memory from 512Mi to 216Mi.

**Output**: `{{RUNBOOKS_DIR}}/airflow-db-clean-oom.md` with:
- TL;DR in 2 lines
- Detection checklist with the exact `kubectl describe pod` snippet showing PerfectScale labels
- Resolution: add `perfectscale.io/exclude: "true"` annotation to CronJob pod template (Option A) and the higher-memory override (Option B) as a safety net
- Rollback: remove the annotation, wait for next PerfectScale mutation
- History table with both occurrences

Both triage notes are updated with a "Promoted to runbook" backlink.
