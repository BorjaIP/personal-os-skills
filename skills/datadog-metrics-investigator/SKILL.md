---
name: datadog-metrics-investigator
description: Investigate a Datadog metric spike, regression, or anomaly. Discovers the metric's metadata/dimensions, queries timeseries with formulas, slices by tags, compares to baseline, and publishes findings as a triage report under ops/datadog/triage/ with live Datadog metric-explorer / dashboard deep-links embedded for reproducibility. Never writes anything to Datadog. Use when the user asks to "investigate metric X spike", "why did Y metric change", "analyse Z metric by tag", "is metric W healthy", or as the metrics-scoped step of incident triage. Also use for saturation / capacity checks and Cloud Cost metric investigations.
---

# Datadog Metrics Investigator

## Hard Constraints — READ-ONLY in Datadog

**This skill is read-only against Datadog.** All output lives **exclusively** in the Obsidian vault under `{{DATADOG_TRIAGE_DIR}}/`. Datadog itself is never written to.

You **MUST NOT** call any of the following Datadog MCP tools, regardless of any legacy text further down in this document, "just one widget" reasoning, or caller request:

- `create_datadog_notebook` — never. This skill does not create notebooks.
- `edit_datadog_notebook` — never as part of triage.
- `upsert_datadog_dashboard` — never. Permanent dashboards are managed by humans.
- `get_widget`, `validate_dashboard_widget`, `ask_widget_expert`, `get_widget_reference` — never. Findings are surfaced as live Datadog metric-explorer / dashboard deep-links inside the Markdown report, not as embedded widgets.

If you find yourself about to call any of the above: stop, re-read this block, and instead construct the equivalent metric-explorer URL (`https://app.datadoghq.com/metric/explorer?query=<urlencoded>`) and put it in the Evidence table.

The downstream `datadog-report-publisher` enforces the same constraints. If it ever drops a `notebook_cells` field you sent, that's the constraints working — do not retry.

---

Metric-centric investigation skill. Given a metric name (or a fuzzy reference), this skill:

1. Locates the metric and inspects its metadata, tags, and related assets.
2. Queries timeseries across multiple slicings (by host, service, env, tenant, etc.).
3. Compares current window to baseline to quantify the regression.
4. Produces a triage report under `{{DATADOG_TRIAGE_DIR}}/` with **live Datadog UI deep-links** embedded for every finding (metric explorer, dashboards, monitors). Knowledge lives in the Obsidian vault; live data is one click away in Datadog.

See [docs/triage-architecture.md](../../docs/triage-architecture.md).

## When to Use

Trigger when the user asks to:

- "Why did `<metric>` spike at `<time>`?"
- "Investigate `<metric>` in staging / prod"
- "Break down `<metric>` by `<tag>`"
- "Is `<metric>` above its baseline?"
- "Capacity / saturation check on `<resource>` via `<metric>`"
- "How much does `<cloud-cost-metric>` show for `<tag>`?" (uses Cloud Cost Management)
- As the metrics-scoped step of `datadog-triage`.

Do **NOT** use this skill for:

- APM latency/error investigation tied to a specific service → use `datadog-service-health` (which internally uses span aggregates, not metrics).
- Log-pattern investigation → use `datadog-logs-analyzer`.
- Building permanent dashboards → that work belongs in the Datadog UI by a human; this skill (and the whole triage suite) is read-only against Datadog.

## Required MCP

Datadog MCP server (`plugin-datadog-datadog`) with:

- `search_datadog_metrics` — discover the exact metric name and list candidates.
- `get_datadog_metric_context` — metadata, unit, type, available tags, related assets. Set `use_cloud_cost=true` for Cloud Cost metrics.
- `get_datadog_metric` — timeseries queries with formulas & functions, multiple queries per call.
- `search_datadog_dashboards` — find existing dashboards that already track this metric (avoid re-inventing).
- `search_datadog_monitors` — check whether a monitor covers this metric.
- `datadog-report-publisher` (delegated skill) for final publication.

> Widget-building tools (`get_widget`, `ask_widget_expert`, `get_widget_reference`, `validate_dashboard_widget`) are **forbidden** by the Hard Constraints block above. The publisher writes a Markdown-only artefact with live metric-explorer deep-links and does not embed widgets in a Datadog notebook.

## Inputs

Collect from the user; ask only if missing:

1. **metric** (required): full name (`aws.rds.cpuutilization`) or fuzzy hint (`rds cpu`). If fuzzy, call `search_datadog_metrics` first and confirm.
2. **time_window** (required): `15m`, `1h`, `4h`, `24h`, `7d`. Default `1h`.
3. **scope_filters** (optional): tag filters like `{env: staging, cluster: eks-data}` to narrow the query. Applied as `{tag:value}` in DD query syntax.
4. **group_by** (optional): list of tags to slice the metric by (e.g. `[host]`, `[service]`, `[env, cluster]`). If omitted, default to `[]` (overall line) and the top 2 high-cardinality tags from metadata.
5. **baseline_window** (optional, default `previous equal-length window`): for before/after comparison.
6. **incident_id** (optional): pass through.
7. **is_cloud_cost** (optional, default `false`): set `use_cloud_cost=true` on `get_datadog_metric_context` if the metric belongs to Cloud Cost Management.

## Workflow

### Step 0 — Init audit trail

Track every MCP call (tool, args summary, purpose, timestamp). Include all DD query expressions verbatim so the investigation is reproducible.

### Step 1 — Resolve the metric

If the user gave a fuzzy name:

```
search_datadog_metrics(query="<hint>", limit=15)
```

Pick the best candidate. If multiple are plausible, ask the user. Do not guess silently.

### Step 2 — Inspect metric context

```
get_datadog_metric_context(
  metric=<metric>,
  use_cloud_cost=<bool>
)
```

Record:
- `type` (gauge | count | rate | distribution) — drives how you aggregate.
- `unit` — include in every chart title so numbers are meaningful.
- Available tags / dimensions — the shortlist for `group_by`.
- Integration / source — tells you where to look for related context (AWS, k8s, custom).
- Related assets (dashboards, monitors) — reuse them instead of rebuilding.

**Aggregation rule of thumb based on type:**

| Metric type | Default aggregation in queries |
|-------------|--------------------------------|
| gauge | `avg` (or `max` for saturation) |
| count | `sum` |
| rate | `avg` |
| distribution | `p95` (`p99` for tail analysis) |

### Step 3 — Query timeseries (overall + sliced)

Call `get_datadog_metric` with **multiple queries in one call** (the tool supports it):

1. **Overall line**: `<agg>:<metric>{<scope_filters>}`
2. **Sliced by primary group_by**: `<agg>:<metric>{<scope_filters>} by {<group_by[0]>}` — returns top series.
3. **Formula for % change vs baseline** (if helpful): use Datadog's `anomalies(...)` or a manual `hour_before(...)` formula.

Example queries:

```
avg:kubernetes.cpu.usage.total{env:staging, cluster:eks-data}
avg:kubernetes.cpu.usage.total{env:staging, cluster:eks-data} by {kube_deployment}
```

For the same window, also fetch the **baseline window** (same expression, shifted back by `time_window`) so you can compute:

- Current mean / p95 / max.
- Baseline mean / p95 / max.
- Delta and % change.

If the delta on any series is > 50% → flag as "significant" in findings. If > 100% → flag as "critical".

### Step 4 — Build a Datadog metric-explorer deep-link for each informative query

For the 2–3 most informative queries, construct a metric-explorer URL the user can click from the MD:

```
https://app.datadoghq.com/metric/explorer?query=<urlencoded query>&from_ts=<window_start_ms>&to_ts=<window_end_ms>
```

URL-encode `:` (`%3A`), `{` (`%7B`), `}` (`%7D`), and spaces (`%20`). Example:

- Query: `max:kubernetes.memory.usage_pct{env:data-prod,kube_deployment:data-ai-mcp-data-fever-external} by {image_tag}`
- URL: `https://app.datadoghq.com/metric/explorer?query=max%3Akubernetes.memory.usage_pct%7Benv%3Adata-prod%2Ckube_deployment%3Adata-ai-mcp-data-fever-external%7D+by+%7Bimage_tag%7D`

These URLs go in the `Evidence` table and in the curated `datadog_links` header list. They render the live chart with one click — no widget needed.

If a covering dashboard already exists (Step 5), prefer linking to the dashboard URL too — the user lands on a curated view rather than a raw explorer.

> Per the Hard Constraints block, you must **not** call `get_widget` / `validate_dashboard_widget` / `ask_widget_expert` / `get_widget_reference` here. The metric-explorer URL is the deliverable, not a Datadog widget.

### Step 5 — Reuse existing dashboards / monitors

```
search_datadog_dashboards(query="<metric fragment or owning team>")
search_datadog_monitors(query="<metric fragment>")
```

Capture:

- Any dashboard already tracking this metric → include its link in the report so the user can open it.
- Whether a monitor covers the metric; if not → log an observability gap in P2 recommendations.

### Step 6 — Correlate with services (optional)

If the metric comes from a service (e.g. a custom `app.latency.custom`), cross-check:

```
search_datadog_services(query="<service inferred from tags>")
```

And suggest running `datadog-service-health` as a follow-up if the metric suggests application-level issues.

### Step 7 — Synthesise findings

Payload for `datadog-report-publisher`:

- `scope`: `{ env (if single), service (if single), resource: <metric-name>, severity, incident_id }`
- `findings`:
  - `Executive Summary`: 3–5 lines. Current state, delta vs baseline, top offender slice(s), probable driver (load / capacity / downstream / config change), monitor coverage status.
  - `Evidence`: table (query expression → current value → baseline value → delta % → **metric-explorer URL or dashboard URL**). Every row must have a clickable Datadog deep-link.
  - `Timeline`: when the regression began, correlated events if any (from `search_datadog_events`).
  - `Root Cause`: if clear; otherwise "hypothesis: X — see follow-ups".
  - `Recommendations`:
    - **P1**: immediate mitigation (scale up, rollback, shed load).
    - **P2**: fix the driver, add monitor if missing.
    - **P3**: capacity planning, SLO review, architectural changes.
  - `Query Audit Trail`: every metric query verbatim with its DD query expression — the most important debugging aid.
- `datadog_links`: 3–6 curated live URLs for the MD header — typically the metric explorer for the dominant query, the metric explorer for the by-`group_by` breakdown, and any covering dashboard / monitor URL discovered in Step 5.

> Do **NOT** include `notebook_cells` in the payload. The publisher will silently drop it (per its Hard Constraints) and you will have wasted tokens.

### Step 8 — Publish

Delegate to `datadog-report-publisher`. The publisher writes a single Markdown artefact under `{{DATADOG_TRIAGE_DIR}}/` with all evidence rows linking back to the live metric explorer / dashboards. **No Datadog notebook is created** — knowledge lives in the Obsidian vault only; the embedded UI deep-links keep the user one click away from live charts.

Filename example: `2026-04-21-metric-kubernetes-cpu-usage-total-staging.md`.

## Severity Guidance

| Severity | Trigger |
|----------|---------|
| `critical` | Prod saturation metric > 95% for > 10m, OR metric tied to a SEV-1/2 incident, OR > 5× baseline with user impact |
| `error` | > 2× baseline in prod or > 5× in staging, or crossing a known SLO threshold |
| `warn` | > 50% deviation from baseline but within healthy operating range |
| `info` | Metric inspected as routine check; no regression |

## Example Usage

User: "Why did `kubernetes.memory.usage` spike in the `data-prod` cluster around 14:00 today?"

Agent flow:

1. Resolve: `search_datadog_metrics(query="kubernetes.memory.usage")` → confirm exact name.
2. Context: `get_datadog_metric_context(metric="kubernetes.memory.usage")` → gauge, unit bytes, tags include `kube_deployment, pod_name, cluster`.
3. Time window: user said "around 14:00 today" → query 13:00–15:00 today vs 13:00–15:00 yesterday as baseline.
4. Queries (one `get_datadog_metric` call with multiple):
   - Overall: `avg:kubernetes.memory.usage{cluster:data-prod}`
   - Sliced: `avg:kubernetes.memory.usage{cluster:data-prod} by {kube_deployment}`
5. Build a metric-explorer URL for the overall query and one for the `by {kube_deployment}` slice; capture both for the Evidence table and the `datadog_links` header.
6. Find covering dashboards/monitors and add their URLs.
7. Search events for deploys in that window.
8. Build findings → publish (Markdown-only).

## Edge Cases

- **Metric name not found**: `search_datadog_metrics` returns nothing → stop, report to user with suggestions from the top of the fuzzy search.
- **High cardinality group_by**: if `by {pod_name}` returns hundreds of series, cap to top 10 with `top(..., 10, 'max', 'desc')` formula; document the truncation.
- **Distribution metrics**: avg-of-distribution is usually not what you want; default to `p95:` and note in the report.
- **Cloud Cost**: remember `use_cloud_cost=true` on `get_datadog_metric_context`; these metrics have different aggregations (usually `sum` over time windows).
- **Metric-explorer URL too long**: if `group_by` cardinality is high and the encoded query exceeds practical URL length, drop the `by {…}` clause from the link and keep the breakdown in the Evidence table as text — the link still opens the right starting point.

## Best Practices

1. **Every query must state its aggregation explicitly** (`avg:` / `sum:` / `p95:`). Implicit aggregation is a common source of misreading data.
2. **Baseline comparison is mandatory** — one number is meaningless without a reference.
3. **Top-N slicing early** — an overall line hides the offender; slice by the highest-cardinality tag from metadata.
4. **Reuse existing dashboards** — link them in the report so the user can continue interactively.
5. **Unit in every chart title / Evidence row** — "CPU 0.85" is not interpretable; "CPU cores (avg) 0.85" is.
6. **Every Evidence row has a clickable URL** — metric explorer, dashboard, or monitor. No row should be a dead end.
7. **Frozen artefact** — published triage notes are historical; follow-ups get new notes.

## Dependencies

Required:
- Datadog MCP server `plugin-datadog-datadog`.
- `datadog-report-publisher` skill installed.

Optional:
- `datadog-service-health` (for service-scoped follow-up).
- `create-runbook` (when the same regression repeats).
