---
name: datadog-triage
description: End-to-end Datadog triage orchestrator. Entry point for "triage this incident", "triage service X", "something is wrong in Datadog", "investigate this alert/monitor", or "triage this Datadog URL" requests. Accepts Datadog URLs (dashboards, monitors, incidents, metric explorer, log explorer, APM trace) and auto-resolves the scope. Plans the investigation, delegates to datadog-service-health / datadog-logs-analyzer / datadog-metrics-investigator, consolidates findings, and produces a single top-level triage Markdown report under ops/datadog/triage/ with embedded live Datadog UI deep-links and a Next Steps section. Knowledge lives in the Obsidian vault — no Datadog notebooks or dashboards are created. Use this as the default entry point for any Datadog diagnostic task that is not already narrowed to logs-only / metrics-only / service-only.
---

# Datadog Triage (Orchestrator)

## Hard Constraints — READ-ONLY in Datadog

**This orchestrator and all its sub-skills are read-only against Datadog.** Every artefact produced lives **exclusively** in the Obsidian vault under `{{DATADOG_TRIAGE_DIR}}/`. Datadog itself is never written to.

You **MUST NOT** call any of the following Datadog MCP tools, regardless of the URL the user pasted, the situation, or any legacy text further down in this document:

- `create_datadog_notebook` — never. The triage suite does not create notebooks.
- `edit_datadog_notebook` — never as part of triage.
- `upsert_datadog_dashboard` — never. Permanent dashboards are managed by humans.

Read-only tools that ARE allowed and useful: `get_datadog_dashboard`, `get_datadog_notebook`, `get_widget` (when reading data from an EXISTING widget on an EXISTING dashboard or share URL), `search_datadog_*`, `aggregate_*`, `get_datadog_*`. The line is simple: **reading current state from Datadog is fine; producing new persistent Datadog artefacts is not**.

**Preflight (mandatory, Step 0)**: before delegating to any sub-skill, restate the contract: "I will publish a single Markdown triage report at `<path>` and my sub-skills will publish their own Markdown reports. No Datadog notebooks or dashboards will be created." If the user explicitly asks for a notebook, refuse and explain that the triage suite is Markdown-only.

When delegating to sub-skills, **never** include `notebook_cells` in the payload. Sub-skills enforce the same constraint and the publisher silently drops the field; passing it just wastes tokens.

---

Top-level triage entry point. Plans an investigation across APM, logs, and metrics, delegates each facet to the specialised sub-skill, then consolidates the findings into a single master Markdown report under `{{DATADOG_TRIAGE_DIR}}/`.

See [docs/triage-architecture.md](../../docs/triage-architecture.md) for how this plugs into the **triage → runbook → incident → knowledge** pipeline.

## When to Use

Trigger when the user asks any of:

- "Triage `<incident-id>` / `<alert>` / `<monitor>`"
- "Something is wrong with `<service>` — figure it out"
- "What's happening in prod right now?"
- "Investigate this Datadog alert"
- "End-to-end triage on `<service>` for the last hour"
- "Pager just fired on `<monitor>` — analyse it"

Do **NOT** use this skill when the scope is already narrowed:

- Logs-only investigation → call `datadog-logs-analyzer` directly.
- Metric spike with a known metric → call `datadog-metrics-investigator` directly.
- APM-only service health check → call `datadog-service-health` directly.
- Post-mortem drafting → manual work under `{{INCIDENTS_DIR}}`.

## Required MCP

Datadog MCP server (`plugin-datadog-datadog`) with these entry-point tools:

- `search_datadog_incidents` / `get_datadog_incident` — incident-driven triage.
- `search_datadog_monitors` — monitor-driven triage.
- `search_datadog_services` — resolve service names.
- `search_datadog_events` — deploys, config changes.

Delegated sub-skills (must be installed):

- `datadog-service-health`
- `datadog-logs-analyzer`
- `datadog-metrics-investigator`
- `datadog-report-publisher`

## Inputs

Gather from the user; if ambiguous, ask one clarifying question before delegating:

1. **entry_point** (required, infer from request):
   - `url` — user pasted a Datadog URL → auto-resolve via URL parsing (see "URL-based triage" below).
   - `incident` — user mentioned an incident ID → fetch via `get_datadog_incident`.
   - `monitor` — user mentioned a monitor name or ID → fetch via `search_datadog_monitors`.
   - `service` — user named a service → use it as primary scope.
   - `alert` — user pasted an alert payload → extract service / metric / env.
   - `freeform` — "something is wrong in prod" → ask for narrowing (see below).
2. **env** (required): `staging | prod | local | other`. Default `prod` if unspecified.
3. **time_window** (optional, default `1h`).
4. **incident_id** (optional if entry_point=incident).

If the user's request is purely `freeform` (e.g. "prod is slow"), ask ONE question to narrow:

> Which of these best fits: a specific service, a specific metric/alert, an open incident, or a log surge?

## Workflow

### Step 0 — Init audit trail

Maintain the master audit list. Each delegated sub-skill will return its own trail; merge them at publication time.

### Step 1 — Resolve the entry point

**If `entry_point = url`:** see the "URL-based triage" section below for the parsing table. After parsing, set the real `entry_point` (incident / monitor / service / metric / log / trace) and fall through to the matching resolver below.

**If `entry_point = incident`:**

```
get_datadog_incident(id=<incident_id>)
```

Extract: title, severity, state, affected services (from fields / tags), timeline events, assigned users.

**If `entry_point = monitor`:**

```
search_datadog_monitors(query="<monitor name or id>")
```

Extract: query expression, tags (service, env), current state, last triggered timestamp. From the query expression, identify whether it is APM, log-based, or metric-based → this drives sub-skill selection in Step 3.

**If `entry_point = service`:** use the service directly; no extra resolution.

**If `entry_point = alert`:** parse the pasted payload for service, env, and metric/log references.

### URL-based triage

When the user pastes a Datadog URL, recognise it by its path prefix and resolve it to a concrete scope. Common URL shapes (domain is `app.datadoghq.com` or `app.datadoghq.eu` — treat both identically):

| URL pattern | Meaning | Resolver |
|-------------|---------|----------|
| `/dashboard/<id>` or `/dashboard/<id>/<slug>` | Dashboard | `get_datadog_dashboard(id=<id>)` → list its widgets → pick the 1–3 most signal-rich widgets, render each via `get_widget(dashboard_id, widget_id)` to pull current data → summarise into findings. If any widget shows a regression → delegate to `datadog-metrics-investigator` for the offending metric. |
| `/dashboard/<id>/...?fullscreen_widget=<widget_id>` | Dashboard widget zoom | Same as dashboard, but start with the focused widget only (`get_widget(dashboard_id=<id>, widget_id=<widget_id>)`) and expand scope only if regression is found. |
| `/s/<share_token>` | Share link (usually a widget) | `get_widget(url=<full URL>)` — this tool accepts share URLs directly and resolves the data. |
| `/monitors/<id>` | Monitor | Set `entry_point = monitor`; call `search_datadog_monitors(query="id:<id>")` or pass the id to the monitor resolver above. |
| `/monitors/manage?...` (filters) | Monitor list view | Ask the user which specific monitor; do NOT triage an entire list. |
| `/metric/explorer?...&query=<expr>` | Metric explorer | Parse `query` param (e.g. `avg:foo.bar{env:prod} by {host}`). Extract metric name + filters + group_by. Set `entry_point = metric` and delegate to `datadog-metrics-investigator`. |
| `/metric/summary?metric=<name>` | Metric summary | Delegate to `datadog-metrics-investigator` with `metric=<name>`. |
| `/incidents/<id>` | Incident | Set `entry_point = incident` and use `<id>`. |
| `/apm/services/<service>?env=<env>` | APM service view | Set `entry_point = service` with `<service>` + `<env>`. Delegate to `datadog-service-health`. |
| `/apm/trace/<trace_id>` | APM trace | `get_datadog_trace(trace_id=<trace_id>)` → extract the root service + env → set `entry_point = service` and run `datadog-service-health` anchored on the trace's time window. |
| `/logs?query=<expr>` or `/logs/livetail?query=<expr>` | Log explorer | Parse `query`. Extract `service:` / `env:` tokens if present. Delegate to `datadog-logs-analyzer` with that query and (if present) service/env scope. |
| `/notebook/<id>` | Existing notebook | `get_datadog_notebook(id=<id>)` — read its content. **Note:** this triage suite no longer creates Datadog notebooks (knowledge lives in the Obsidian vault under `{{DATADOG_TRIAGE_DIR}}/`). If the URL points to a third-party notebook, read it and use its queries as a starting scope. If it points to a deprecated `[triage]` notebook from before this skill change, ignore it and start a fresh triage. Either way: do NOT call `edit_datadog_notebook` to update it. |

**URL resolution steps:**

1. Strip the domain; keep only the path + query string.
2. Match against the table above (first hit wins).
3. Extract required params (id, trace_id, metric name, service name, env).
4. If the URL type isn't recognised → state what you saw and ask the user to narrow (do not guess).
5. Announce the resolution: *"I read this as a `<type>` URL pointing to `<id/metric/service>`. Plan: …"*. Let the user correct before delegating.
6. Fall through to the matching resolver in Step 1 (incident / monitor / service / metric / log / trace) or directly invoke the sub-skill if it's a single-facet URL (metric explorer, log explorer, APM trace).

### Step 2 — Define the triage plan

Based on what Step 1 revealed, compose a plan listing which sub-skills to run. Common plans:

| Situation | Sub-skills to run (in order) |
|-----------|------------------------------|
| Incident affecting a single service | 1) `datadog-service-health`, 2) `datadog-logs-analyzer` (same service), 3) `datadog-metrics-investigator` (infra metric if service-health flagged saturation) |
| Metric-triggered alert | 1) `datadog-metrics-investigator`, 2) `datadog-service-health` if metric maps to a service |
| Log-triggered alert | 1) `datadog-logs-analyzer`, 2) `datadog-service-health` if dominant pattern maps to a service |
| "Something is wrong with service X" | 1) `datadog-service-health`, 2) `datadog-logs-analyzer` on the same scope |
| Freeform incident (multi-service) | Run `datadog-service-health` in parallel for each affected service from incident fields, then `datadog-logs-analyzer` per service in sequence |

**State the plan to the user before executing** — brief 3–5 bullet points. They may correct scope before the skill burns tokens on the wrong investigation.

### Step 3 — Execute the plan (delegate)

For each entry in the plan, delegate to the sub-skill by invoking it with the structured inputs expected by its SKILL.md. Capture from each:

- The returned `markdown_path` (the sub-skill's triage note).
- The top finding in 1 sentence.
- Severity the sub-skill assigned.
- Any curated `datadog_links` the sub-skill surfaced in the MD header (you'll merge them into the master report).

> **No Datadog notebooks are produced.** All knowledge lives in the Obsidian vault — sub-skills only emit Markdown artefacts with embedded live Datadog UI deep-links. Per the Hard Constraints, never request notebook output from a sub-skill.

**Parallelism**: if two sub-skills are scope-independent (e.g. two different services, or metrics vs logs on the same service), invoke them in parallel. If scope-dependent (service-health's output drives which metric to investigate), run sequentially.

**Stop conditions**:

- If the first sub-skill's finding is a hard failure (service down, deploy rollback obvious) → skip secondary sub-skills and jump to publication. Note in the master report what was skipped and why.
- If a sub-skill reports `no data` → record it and continue; don't retry.

### Step 4 — Consolidate findings

Build the master findings payload. This is NOT just a concatenation of sub-reports — it is a curated narrative:

- `Executive Summary` (3–7 lines, from the orchestrator's POV):
  - Overall verdict (single sentence: healthy / degraded / broken / unknown).
  - The single most likely root cause (if consensus across sub-skills).
  - The mitigation already suggested by the highest-severity sub-skill.
  - Blast radius: services, envs, users affected.
- `Evidence`: aggregated table with ONE row per sub-skill pointing to its own MD (as an Obsidian wikilink, not a notebook URL) + top finding.
- `Timeline`: merged timeline from all sub-skills, ordered chronologically.
- `Root Cause`: consensus across sub-skills; if they disagree, name the disagreement explicitly (don't paper over it).
- `Recommendations`:
  - Deduplicate identical P1/P2/P3 items from sub-skills.
  - Add orchestrator-level items (e.g. cross-service patterns that no single sub-skill sees).
- `Next Steps`: a curated, opinionated checklist of what the user should do *after* reading this triage. Cover at most these dimensions, and only when relevant — skip the ones that don't apply:
  - **Apply the P1 fixes**: who owns the work and how to track it (e.g. `mdn-add` to a Meridian project).
  - **Spin off follow-up triages**: if a sub-skill flagged a wider issue (e.g. namespace-wide log gap), suggest re-running the relevant skill with broader scope or opening it as its own task.
  - **Runbook promotion**: if this is the second triage with the same signature (search the vault), suggest `create-runbook` and link the matching paths. Otherwise state "first occurrence — do not promote yet".
  - **Incident / post-mortem**: if `severity ≥ critical` or `incident_id` is set, suggest opening (or escalating) the incident and writing the post-mortem under `{{INCIDENTS_DIR}}`. Otherwise explicitly say "no incident needed".
  - **Datadog UI deep-links to keep open during the fix**: a short bullet list of 3–6 live URLs from the sub-skills (APM service, dashboards, monitor, metric explorer, logs explorer). These are the launching pads from the vault back into live data.
- `Query Audit Trail`: merge of all sub-skills' trails, tagged with which sub-skill ran it.

Also pass to the publisher:

- `datadog_links` (header-level): the same 3–6 curated URLs from the Next Steps deep-links bullet — surfaced in the MD header so the reader sees them immediately.

Severity of the master report = max() of all sub-skills' severities.

### Step 5 — Publish master report

Delegate to `datadog-report-publisher` with:

- `source_skill: datadog-triage`
- `scope`: consolidated scope (use incident_id if present; else primary service + env)
- `findings`: the master payload above (including the `Next Steps` section)
- `datadog_links`: the curated header URLs from Step 4
- `related_artefacts`: list of each sub-skill's `markdown_path` (so the master MD's `## Related` section backlinks them as unquoted Obsidian wikilinks).

> Do **NOT** pass `notebook_cells`. The publisher emits a Markdown-only artefact; knowledge lives in the Obsidian vault.

Filename examples produced by publisher:

- `2026-04-21-incident-INC-1234-checkout-web.md` (incident-driven)
- `2026-04-21-triage-data-ai-studio-backend-staging.md` (service-driven)
- `2026-04-21-triage-monitor-high-error-rate.md` (monitor-driven)

### Step 6 — Final report to the user

Print a compact summary, the master MD path, and the most useful next action:

```
Verdict:       <healthy|degraded|broken|unknown>
Primary cause: <single sentence>
Severity:      <info|warn|error|critical>
Master MD:     <path>
Sub-reports:
  - <sub-skill-1>: <path> (<top finding>)
  - <sub-skill-2>: <path> (<top finding>)
  - ...

Next step (most important): <one short sentence pulled from the master Next Steps section — usually the top P1 action or "promote to runbook" / "open incident" if applicable>
```

## Promotion Hints

After publication, check the vault for patterns:

- **≥ 2 triage notes with the same root-cause signature** → suggest invoking the `create-runbook` skill with the relevant MD paths.
- **`severity: critical` AND `incident_id` is set** → suggest drafting a post-mortem under `{{INCIDENTS_DIR}}/<YYYY-MM-DD>-<scope>.md` (manual work; not automated here).
- **Observability gap flagged by ≥ 1 sub-skill** → suggest creating a monitor.

These are suggestions. Do NOT auto-execute promotion — require an explicit user confirmation.

## Severity Guidance

Master severity = max() of sub-skill severities. Additionally escalate one notch if:

- `incident_id` has state `active` and severity SEV-1/SEV-2.
- Multiple sub-skills independently flagged the same service → correlated signal, stronger evidence.

## Example Usage

### Example 1 — Incident-driven

User: "Triage incident INC-1234"

Agent flow:

1. `get_datadog_incident(id="INC-1234")` → title "checkout-web p99 spike", severity SEV-2, affected services `[checkout-web, payments-api]`, window last 30m.
2. Plan:
   - Parallel: `datadog-service-health(service=checkout-web, env=prod, window=30m, incident_id=INC-1234)` and `datadog-service-health(service=payments-api, env=prod, window=30m, incident_id=INC-1234)`.
   - Then: `datadog-logs-analyzer(service=checkout-web, env=prod, window=30m)` (if service-health flagged errors).
   - Then: `datadog-metrics-investigator` on infra saturation metric if flagged.
3. Execute plan.
4. Consolidate: both services degraded, payments-api is downstream origin (from checkout-web's trace drill-down), deploy of payments-api correlates with onset.
5. Publish master report → `2026-04-21-incident-INC-1234-checkout-web.md`.
6. Report to user + suggest rollback of payments-api.

### Example 2 — Service-driven

User: "End-to-end triage on `data-ai-studio-backend` in staging for the last 2h"

1. No incident; entry_point = service.
2. Plan: `datadog-service-health` → `datadog-logs-analyzer`.
3. Execute, consolidate, publish.
4. Filename: `2026-04-21-triage-data-ai-studio-backend-staging.md`.

### Example 3 — Monitor-driven

User: "The `Kubernetes prod memory high` monitor just fired, triage it"

1. `search_datadog_monitors(query="Kubernetes prod memory high")` → extract query `max:kubernetes.memory.usage{env:prod}` → metric-type monitor.
2. Plan: `datadog-metrics-investigator(metric=kubernetes.memory.usage, scope_filters={env:prod}, window=1h)` → if high in a specific deployment, `datadog-service-health` on that deployment's mapped service.
3. Consolidate, publish.

### Example 4 — Dashboard URL

User pastes: `https://app.datadoghq.com/dashboard/abc-123/checkout-overview?from_ts=...&to_ts=...`

1. Recognise `/dashboard/<id>` → `get_datadog_dashboard(id="abc-123")`.
2. List widgets; identify signal-rich ones (timeseries for latency, error rate, RPS).
3. For each signal widget, call `get_widget(dashboard_id="abc-123", widget_id=<wid>)` to pull current values + compare to baseline (via the widget's own query rerun with shifted time range).
4. Any widget regressing > 50% vs baseline → delegate to `datadog-metrics-investigator` for the offending metric. If the dashboard is scoped to a service, also run `datadog-service-health`.
5. Consolidate all findings, publish master Markdown report. The master MD links back to the original dashboard URL in its `Datadog deep-links` header so the reader can reopen the live widgets with one click.

### Example 5 — Metric explorer URL

User pastes: `https://app.datadoghq.com/metric/explorer?query=avg%3Akubernetes.cpu.usage.total%7Benv%3Aprod%7D%20by%20%7Bkube_deployment%7D&from_ts=...`

1. Recognise `/metric/explorer` → parse `query` param → `avg:kubernetes.cpu.usage.total{env:prod} by {kube_deployment}`.
2. Extract: metric=`kubernetes.cpu.usage.total`, filters=`{env:prod}`, group_by=`[kube_deployment]`.
3. Delegate directly to `datadog-metrics-investigator(metric="kubernetes.cpu.usage.total", scope_filters={env:"prod"}, group_by=["kube_deployment"], time_window=<from URL ts range>)`.
4. `datadog-metrics-investigator` runs its full flow and publishes. The orchestrator adds a master wrapper pointing to the child report.

### Example 6 — APM trace URL

User pastes: `https://app.datadoghq.com/apm/trace/1234abcd`

1. Recognise `/apm/trace/<id>` → `get_datadog_trace(trace_id="1234abcd", only_service_entry_spans=true)`.
2. Extract root service, env, and time window (trace start/end ± 15m for context).
3. Delegate to `datadog-service-health(service=<root>, env=<env>, window=30m)` anchored on the trace.
4. Consolidate; master report includes the original trace deep link alongside the sub-skill's findings.

## Edge Cases

- **Multiple affected services in an incident**: run service-health in parallel; keep logs-analyzer sequential per service to avoid log-API throttling.
- **No sub-skill produces findings**: publish a master report with `severity: info` and status `open` stating "no actionable evidence found; suggest extending the window or narrowing scope".
- **Sub-skill fails (MCP error)**: record the failure in the master report's `## Publication Notes`, continue with remaining sub-skills.
- **Scope is truly freeform** ("prod is slow"): do not guess. Ask the user to pick one narrowing dimension (service, metric, monitor) before starting.
- **User wants a dry-run of the plan**: state Step 2 plan and stop; do not execute.

## Best Practices

1. **State the plan before executing** — cheap sanity check that prevents wasted MCP calls.
2. **Parallelise scope-independent sub-skills** — triage latency matters.
3. **Narrate the verdict, not a list of numbers** — the executive summary must tell a story.
4. **Always publish a master report, even for "no findings"** — absence of evidence is itself an artefact.
5. **Respect stop conditions** — once the root cause is clear, stop; don't burn tokens on comprehensive-but-irrelevant deep dives.
6. **Do not auto-promote to runbook / incident** — suggest, let the human decide.
7. **Merge audit trails faithfully** — the consolidated trail is the single source of truth for reproducibility.

## Dependencies

Required:
- Datadog MCP server `plugin-datadog-datadog`.
- All four sibling skills installed: `datadog-report-publisher`, `datadog-service-health`, `datadog-logs-analyzer`, `datadog-metrics-investigator`.

Optional:
- `create-runbook` (for pattern promotion after triage completes).
