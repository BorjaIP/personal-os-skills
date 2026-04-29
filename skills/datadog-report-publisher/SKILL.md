---
name: datadog-report-publisher
description: Publish a Datadog triage finding as a Markdown artefact in ops/datadog/triage/. The MD is the single source of truth — knowledge lives in the Obsidian vault, never in Datadog. Every finding must include live Datadog UI deep-links so the queries are reproducible from the note. Use as the final step of any Datadog triage skill (datadog-triage, datadog-service-health, datadog-logs-analyzer, datadog-metrics-investigator) to commit findings to the ops/ knowledge base.
---

# Datadog Report Publisher

## Hard Constraints — READ-ONLY in Datadog

**This skill is read-only against Datadog.** All output of the triage suite lives **exclusively** in the Obsidian vault under `{{DATADOG_TRIAGE_DIR}}/`. Datadog itself is never written to.

You **MUST NOT** call any of the following Datadog MCP tools, regardless of the caller's payload, "just one widget" reasoning, or any legacy text further down in this document:

- `create_datadog_notebook` — never. The publisher does not create notebooks.
- `edit_datadog_notebook` — never (except as a one-off cleanup the user explicitly requested out-of-band; not as part of any publication flow).
- `upsert_datadog_dashboard` — never. Permanent dashboards are managed by humans, not by triage skills.
- `get_widget`, `validate_dashboard_widget`, `ask_widget_expert`, `get_widget_reference` — never for publication purposes; they exist to render widgets that go *into* Datadog artefacts, which this skill no longer produces.

**Preflight check (mandatory)**: before doing anything, scan the caller's payload. If it contains `notebook_cells`, `notebook_url`, `notebook_status`, `widget_definition`, `widget_cells`, or any field whose name implies writing to Datadog, **drop those fields silently and emit only the Markdown artefact**. Do not warn the caller — just produce the MD. The Markdown artefact is the single source of truth.

If a caller (parent agent, sub-skill, or user) explicitly asks for "publish to Datadog", "create a notebook", or "embed widgets in a notebook": refuse, state that the publisher writes Markdown only, and produce the MD anyway. Knowledge lives in Obsidian.

---

Utility skill that turns an in-flight Datadog investigation into a single Markdown artefact under `{{DATADOG_TRIAGE_DIR}}/` (Obsidian-friendly, promotable via `create-runbook`).

> **Knowledge lives in Obsidian, not in Datadog.** Every Datadog query, dashboard, monitor, trace, log search, etc. cited in the triage MUST be embedded in the MD as a live Datadog UI deep-link, so the user can reproduce the chart with one click without leaving their vault.

See [docs/triage-architecture.md](../../docs/triage-architecture.md) for how this plugs into the **triage → runbook → incident → knowledge** pipeline.

## When the caller invokes this skill

Other Datadog skills (`datadog-triage`, `datadog-service-health`, `datadog-logs-analyzer`, `datadog-metrics-investigator`) call this skill at their final step, passing a structured payload (see "Inputs" below). Do not invoke this skill directly for primary analysis — it is a publisher, not an investigator.

## Required MCP

This skill does **not** require any MCP tool to publish. It only writes a Markdown file.

> Historical note: previous versions of this skill also created a Datadog Notebook via `create_datadog_notebook` / `edit_datadog_notebook`. That step has been **removed** by design — knowledge lives in Obsidian only. See the Hard Constraints block above; those tools are explicitly forbidden.

## Inputs

The caller must provide:

1. **source_skill** (required): `datadog-triage` | `datadog-service-health` | `datadog-logs-analyzer` | `datadog-metrics-investigator`.
2. **scope** (required): a short dict with
   - `service` (optional, string)
   - `env` (required, one of `staging | prod | local | other`)
   - `project` (optional, inferred from service owner in Datadog)
   - `resource` (optional, free text — e.g. metric name, log pattern, endpoint)
   - `severity` (required, one of `info | warn | error | critical`)
   - `incident_id` (optional, Datadog incident ID if triage was incident-driven)
3. **findings** (required): structured markdown body with sections
   - `Executive Summary` (mandatory, ≤ 5 lines)
   - `Evidence` (mandatory, table mapping finding → MCP tool used → query → **Datadog UI deep-link URL**)
   - `Timeline` (optional)
   - `Root Cause` (optional, may be "unknown — see follow-ups")
   - `Recommendations` (mandatory, P1/P2/P3 buckets)
   - `Query Audit Trail` (mandatory, reproducible list of every MCP query executed)
   - `Next Steps` (mandatory for `datadog-triage` master reports; recommended for sub-skills)
4. **datadog_links** (optional but strongly recommended): a list of curated live Datadog UI URLs to embed in the MD header (APM service page, dashboards, monitors, metric-explorer, log-explorer queries, traces). The publisher renders these as a bullet list under the header so the user lands one click away from the live data.
5. **related_artefacts** (optional): list of paths to other triage notes, runbooks, or incidents to backlink as Obsidian wikilinks.

> **`notebook_cells` is deprecated.** If the caller passes it, ignore it and emit only the MD. See the Hard Constraints block.

## Workflow

### Step 1 — Preflight: enforce read-only

Verify the caller's payload contains no Datadog write directives. If `notebook_cells`, `widget_definition`, `widget_cells`, or any "publish to Datadog" hint is present, drop the field, log it in the `## Publication Notes` section of the final MD ("Caller passed `<field>`; ignored per skill constraints"), and continue.

### Step 2 — Resolve output directory

Target dir:

```
{{DATADOG_TRIAGE_DIR}}
```

Fallback if placeholder was not substituted at install time: `./docs/datadog_analyses/triage/`. Warn the user once when falling back.

Ensure the directory exists:

```bash
mkdir -p "{{DATADOG_TRIAGE_DIR}}"
```

### Step 3 — Derive filename (date-first, kebab-case)

```
<YYYY-MM-DD>-<scope_slug>.md
```

Where `<scope_slug>` is built from the scope dict, in priority order:

- `incident_id` present → `incident-<id>-<service>`
- `service` present → `<service>-<env>[-<resource-slug>]`
- Otherwise → `<source_skill-suffix>-<resource-slug>`

If the file already exists for the same day, append `-HHMM`:

```
<YYYY-MM-DD>-<HHMM>-<scope_slug>.md
```

Examples:

- `2026-04-21-data-ai-studio-backend-staging.md`
- `2026-04-21-1530-incident-INC-1234-checkout-web.md`
- `2026-04-21-logs-data-ai-mcp-timeout-pattern.md`

### Step 4 — Write the Markdown artefact

**Frontmatter contract (no wikilinks inside YAML — keep values as plain strings):**

```yaml
---
title: <short human title — e.g. "data-ai-studio-backend staging latency p95 spike">
created: <YYYY-MM-DD HH:mm>
source: datadog
source_skill: <source_skill>
env: <staging|prod|local|other>
service: <service-or-empty>
project: <inferred-project-or-empty>
resource: <resource-or-empty>
severity: <info|warn|error|critical>
status: open
incident_id: <dd-incident-id-or-empty>
tags: [ops, datadog, triage]
---
```

> Frontmatter never contains `notebook_url` or `notebook_status` — those fields are forbidden by the Hard Constraints.

**Body skeleton:**

```markdown
# <Short human title>

**Source skill:** `<source_skill>`
**Scope:** `<service>` / `<env>` / `<resource>`
**Severity:** `<severity>`
**Datadog deep-links (live):**
- [<label>](<url>)
- [<label>](<url>)
- ...
**Created:** <YYYY-MM-DD HH:mm>

---

## Executive Summary

<from findings.Executive Summary — ≤ 5 lines>

---

## Evidence

| # | Finding | MCP Tool | Query / Params | Datadog Link |
|---|---------|----------|----------------|--------------|
| 1 | ... | `aggregate_spans` | `service:foo env:staging` | [traces](https://app.datadoghq.com/apm/traces?...) |
| 2 | ... | `analyze_datadog_logs` | `SELECT ... FROM logs WHERE ...` | [logs](https://app.datadoghq.com/logs?...) |

> Every row of the evidence table MUST have a clickable Datadog Link. If the MCP returned data with no natural UI URL (e.g. service-catalog metadata), put `n/a` and explain in the row.

---

## Timeline

<from findings.Timeline, if provided>

---

## Root Cause

<from findings.Root Cause>

---

## Recommendations

### P1 — Immediate
- ...

### P2 — Short-term
- ...

### P3 — Long-term / Follow-up
- ...

---

## Query Audit Trail

| # | Timestamp | MCP Tool | Arguments (summary) | Purpose |
|---|-----------|----------|---------------------|---------|
| 1 | HH:MM:SS | `search_datadog_services` | `team=data-ai-agents` | Locate owned services |
| ... | ... | ... | ... | ... |

**Total queries executed:** X

---

## Next Steps

<from findings.Next Steps — see datadog-triage SKILL for the master-report template; sub-skills typically contribute 2–4 bullets here>

---

## Related

- [[Observability]]
- [[Datadog]]
- [[<project-MOC-if-known>]]
<!-- if related_artefacts was passed, append one bullet per artefact as an unquoted Obsidian wikilink -->
```

**Important — wikilinks in frontmatter**: never put `[[wikilinks]]` inside YAML. Keep frontmatter values as plain strings; wikilinks live only in the `## Related` body section.

### Step 5 — Embed the curated `datadog_links`

If the caller passed a `datadog_links` list, render it as the bullet list immediately under the `**Severity:**` line in the header (template above). This is the user's primary launching pad back into the live Datadog UI from inside Obsidian.

If the caller did not pass `datadog_links`, mine the `Evidence` table for the most informative URLs (typically the APM service page, the metric explorer, the logs explorer) and surface them in the header anyway. Aim for 3–6 links — too many becomes noise.

### Step 6 — Report to caller

Return to the calling skill:

```
{
  "markdown_path": "<absolute path>"
}
```

And print a brief 2-line human summary:

```
Published:
  MD: <path>
```

## Datadog UI URL recipes

Use these patterns when you need to construct deep-links from MCP data (the orchestrator and sub-skills should already have these from their own queries, but include here as a reference):

- **APM service**: `https://app.datadoghq.com/apm/services/<service>?env=<env>`
- **APM traces (filter)**: `https://app.datadoghq.com/apm/traces?query=<urlencoded>&historicalData=true`
- **APM single trace**: `https://app.datadoghq.com/apm/trace/<trace_id>`
- **Logs explorer**: `https://app.datadoghq.com/logs?query=<urlencoded>&from_ts=<ms>&to_ts=<ms>`
- **Logs Flex tier**: same with `&storage=flex_tier`
- **Logs patterns view**: same with `&viz=pattern&clustering_pattern_field_path=message`
- **Metric explorer**: `https://app.datadoghq.com/metric/explorer?query=<urlencoded metric query>`
- **Metric summary**: `https://app.datadoghq.com/metric/summary?metric=<metric_name>`
- **Dashboard**: `https://app.datadoghq.com/dashboard/<id>`
- **Monitor**: `https://app.datadoghq.com/monitors/<id>`
- **Event explorer**: `https://app.datadoghq.com/event/explorer?query=<urlencoded>`
- **Incident**: `https://app.datadoghq.com/incidents/<id>`

URL-encode values that contain `:`, spaces, `{` `}`, etc. (`%3A`, `%20`, `%7B`, `%7D`).

## Promotion Hints

After publishing, check whether the `{{DATADOG_TRIAGE_DIR}}` folder already contains another triage note with the same `service` + similar `resource`/symptom. If yes (≥ 2 occurrences), **suggest** (do not auto-run) promoting to a runbook using the `create-runbook` skill. Example hint to the user:

> I found a related triage note from <date> with the same symptom on `<service>`. Consider promoting both to a runbook with: `create a runbook from <path-1>, <path-2>`.

If severity is `critical` and `incident_id` is set, suggest writing the post-mortem under `{{INCIDENTS_DIR}}` instead.

## Best Practices

1. **Markdown only** — no Datadog notebook is created. Knowledge lives in Obsidian. Re-read the Hard Constraints block at the top of this skill if in doubt.
2. **Deep links over screenshots** — every finding must include a Datadog URL the user can click (traces_explorer_url, trace_deep_link_url, metric explorer, dashboard links, etc.).
3. **Curated header links** — always surface 3–6 live UI URLs in the header so the user has a fast launching pad to the live data.
4. **Redact secrets** — tokens, passwords, customer PII must never make it into the MD.
5. **Query audit trail is non-negotiable** — every query executed during triage must appear in the trail, with arguments summarised (not raw dumps).
6. **Atomic artefacts** — triage notes are frozen after creation. If new evidence arrives, write a new triage note and cross-link, don't mutate the old one.
7. **Never put wikilinks in frontmatter** — they break Dataview in this vault. Always body-only.

## Edge Cases

- **MCP tool fails mid-investigation**: write what you have, add a `## Publication Notes` section explaining what's missing.
- **User has no Obsidian configured**: the placeholder falls back to `./docs/datadog_analyses/triage/` relative to CWD. Warn once.
- **Caller didn't provide findings in the expected shape**: do NOT fabricate content. Ask the caller to re-emit findings in the contract shape.
- **Scope lacks service**: use `source_skill` as fallback in the scope_slug (e.g. `2026-04-21-logs-<resource>.md`).
- **Caller passes `notebook_cells` (or any Datadog write directive)**: silently drop the field, log in `## Publication Notes`, and emit only the MD. Do NOT call any Datadog write tool.

## Dependencies

Required:
- Obsidian vault configured via `install.sh --reconfigure` (optional; otherwise falls back to `./docs/...`).

Optional:
- `create-runbook` skill (for promotion suggestions after ≥ 2 related triages).
