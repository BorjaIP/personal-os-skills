---
name: datadog-logs-analyzer
description: Analyse Datadog logs for a service, time window, or error pattern. Discovers patterns, aggregates by attributes with DDSQL, inspects raw samples, and produces a triage report under ops/datadog/triage/ with live Datadog Logs Explorer deep-links embedded for reproducibility. Never writes anything to Datadog. Use when the user asks to "investigate logs for X", "what errors are there in service X", "find log pattern Y", "aggregate logs by Z", "top errors in staging/prod", or when deeper log analysis is needed as a sub-step of incident or service-health triage.
---

# Datadog Logs Analyzer

## Hard Constraints — READ-ONLY in Datadog

**This skill is read-only against Datadog.** All output lives **exclusively** in the Obsidian vault under `{{DATADOG_TRIAGE_DIR}}/`. Datadog itself is never written to.

You **MUST NOT** call any of the following Datadog MCP tools, regardless of any legacy text further down in this document, "just one widget" reasoning, or caller request:

- `create_datadog_notebook` — never. This skill does not create notebooks.
- `edit_datadog_notebook` — never as part of triage.
- `upsert_datadog_dashboard` — never. Permanent dashboards are managed by humans.
- `get_widget`, `validate_dashboard_widget`, `ask_widget_expert`, `get_widget_reference` — never. Findings are surfaced as live Datadog Logs Explorer deep-links inside the Markdown report.

If you find yourself about to call any of the above: stop, re-read this block, and instead construct the equivalent Datadog Logs Explorer URL (raw search, patterns view, Flex tier) and put it in the Evidence table.

The downstream `datadog-report-publisher` enforces the same constraints. If it ever drops a `notebook_cells` field you sent, that's the constraints working — do not retry.

---

Log-centric investigation skill that combines three Datadog MCP patterns:

1. **Pattern discovery** — `search_datadog_logs` with `use_log_patterns=true` to cluster similar messages.
2. **Raw sampling** — `search_datadog_logs` with `extra_fields` to inspect individual lines and discover attributes.
3. **Aggregation** — `analyze_datadog_logs` with DDSQL for counts, group-bys, and time-bucketed analysis.

Every run produces a triage note under `{{DATADOG_TRIAGE_DIR}}/` with evidence linked to Datadog. See [docs/triage-architecture.md](../../docs/triage-architecture.md).

## When to Use

Trigger when the user asks to:

- "Analyse logs for `<service>` in the last hour"
- "What errors is `<service>` throwing?"
- "Top error patterns in `<service>` / `<env>`"
- "Count errors by endpoint / customer / status code"
- "Is there a surge of `<pattern>` logs?"
- As the logs-scoped step of `datadog-triage` or a follow-up to `datadog-service-health`.

Do **NOT** use this skill for:

- APM trace investigation → use `datadog-service-health`.
- Metric spikes → use `datadog-metrics-investigator`.

## Required MCP

Datadog MCP server (`plugin-datadog-datadog`) with these tools:

- `search_datadog_logs` — raw samples and pattern clustering.
- `analyze_datadog_logs` — DDSQL aggregations over the virtual `logs` table.
- `datadog-report-publisher` (delegated skill) for final publication.

## Inputs

Collect from the user; ask only if missing:

1. **scope** (required): either a `service`, a free-text pattern, or both.
   - `service:<name> env:<env>` — preferred.
   - Or `query="<DD search query>"` for ad-hoc patterns (e.g. `"Connection refused"`).
2. **env** (required if scope is service): `staging | prod | local | other`.
3. **time_window** (optional, default `1h`): `15m`, `1h`, `4h`, `24h`, `7d`.
4. **focus** (optional): hint to prioritise one of `errors | warnings | patterns | volume`. Default `errors`.
5. **incident_id** (optional): pass through to the report.

## DDSQL Primer (critical)

`analyze_datadog_logs` runs DDSQL (a PostgreSQL subset) against a virtual `logs` table filtered by the supplied search `query`. Key rules the model frequently gets wrong:

- **Every non-aggregated SELECT column must appear in GROUP BY.**
- **SELECT aliases cannot be reused in WHERE / GROUP BY / HAVING.** Repeat the full expression:
  - ✅ `GROUP BY DATE_TRUNC('hour', timestamp)`
  - ❌ `SELECT DATE_TRUNC('hour', timestamp) AS hour ... GROUP BY hour`
- **Columns with special characters** (e.g. custom attributes `@user.id`) must be quoted: `"@user.id"`.
- **Custom attributes must be declared as `extra_columns`** — you discover them first via `search_datadog_logs` with `extra_fields`.
- Unsupported constructs: `ANY()`, `->>` (use `->` + casts), `QUALIFY`, `information_schema`, `current_timestamp`. Use explicit `now() - interval '1 hour'` style if needed.
- If a query times out → shorten the time range or add more restrictive filters in `query`.

## Workflow

### Step 0 — Init audit trail

Track every MCP call with timestamp, tool, args summary, purpose. Required in the final report.

### Step 1 — Pattern discovery (first pass)

```
search_datadog_logs(
  query="service:<service> env:<env> status:(error OR warn)",
  use_log_patterns=true,
  time_window=<window>,
  limit=50
)
```

Pattern mode clusters similar messages (e.g. `"timeout connecting to %s after %d ms"`) so you don't drown in noise. Capture:

- Top 10 patterns by count.
- Representative message per pattern.
- Any pattern that accounts for > 30% of the volume → mark as "dominant".

If the user gave a specific pattern (e.g. `"OOMKilled"`), skip to Step 3.

### Step 2 — Attribute discovery (raw sample)

Pick the top 2–3 patterns from Step 1 and run, per pattern:

```
search_datadog_logs(
  query="service:<service> env:<env> \"<pattern snippet>\"",
  extra_fields=[<candidate attributes: @http.status_code, @user.id, @error.type, @duration, etc.>],
  time_window=<window>,
  limit=20
)
```

The goal is to discover which custom attributes (`@foo`) exist on these logs, so you can aggregate by them in Step 3.

Record discovered attributes in the audit trail.

### Step 3 — Aggregate with DDSQL

Build targeted aggregations. Typical starter queries:

**Counts by status over time:**

```sql
SELECT
  DATE_TRUNC('minute', timestamp) AS bucket,
  status,
  count(*) AS n
FROM logs
GROUP BY DATE_TRUNC('minute', timestamp), status
ORDER BY bucket
```

Via: `analyze_datadog_logs(query="service:<service> env:<env>", sql=<above>, time_window=<window>)`.

**Top offenders by endpoint:**

```sql
SELECT
  "@http.path" AS path,
  count(*) AS errors
FROM logs
GROUP BY "@http.path"
ORDER BY errors DESC
LIMIT 20
```

**Error rate by customer / tenant:**

```sql
SELECT
  "@user.id" AS user_id,
  count(*) AS errors
FROM logs
GROUP BY "@user.id"
HAVING count(*) > 10
ORDER BY errors DESC
LIMIT 20
```

**Timeline of the dominant pattern:**

```sql
SELECT
  DATE_TRUNC('minute', timestamp) AS bucket,
  count(*) AS n
FROM logs
GROUP BY DATE_TRUNC('minute', timestamp)
ORDER BY bucket
```

With `query="service:<service> env:<env> \"<dominant pattern>\""` as the filter.

**Declare any `@` attributes used as `extra_columns`** in the `analyze_datadog_logs` call; otherwise the column will not resolve.

### Step 4 — Raw inspection of representative lines

For each dominant pattern, grab 3–5 raw log lines to include in the evidence (not the full payload — excerpt the useful fields):

```
search_datadog_logs(
  query="service:<service> env:<env> \"<dominant snippet>\"",
  limit=5,
  sort="desc"
)
```

Redact any PII / tokens / internal IDs that look sensitive before embedding in the report.

### Step 5 — Correlate with service & env

If the scope included a service, also run a quick Golden-Signals check via `aggregate_spans` to see whether the log surge correlates with an APM regression. If it does, cross-link to a `datadog-service-health` report (suggest running it if not already done).

### Step 6 — Synthesise findings

Payload for `datadog-report-publisher`:

- `scope`: `{ service, env, resource: <dominant-pattern-slug>, severity, incident_id }`
- `findings`:
  - `Executive Summary`: 3–5 lines. Top pattern(s), volume trend (surging / stable / decaying), suspected root cause class (downstream timeout / validation error / capacity / config), correlation with APM if checked.
  - `Evidence`: table (pattern → count → share → representative message → **Datadog Logs Explorer deep-link**). Every row must have a clickable URL (typically `https://app.datadoghq.com/logs?query=...&from_ts=...&to_ts=...`, with `&viz=pattern` for the patterns view, or `&storage=flex_tier` if you queried Flex). Knowledge lives in Obsidian, but the live data is one click away in Datadog.
  - `Timeline`: first/last occurrence, bucketed volume.
  - `Root Cause`: state if clear; otherwise "hypothesis only — see follow-ups".
  - `Recommendations`:
    - **P1**: mitigate the surge (rate-limit, rollback, circuit-break, increase capacity).
    - **P2**: fix the error at source, add log-based monitor if missing.
    - **P3**: log hygiene (reduce verbosity, structured fields), runbook promotion if recurring.
  - `Query Audit Trail`: every MCP call with DDSQL shown verbatim so another human can reproduce.
- `datadog_links`: 3–6 curated live URLs to surface in the MD header — typically the main Logs Explorer query, the patterns view, the Flex-tier view, and any related dashboard or monitor.

> Do **NOT** include `notebook_cells` in the payload. The publisher will silently drop it (per its Hard Constraints) and you will have wasted tokens.

### Step 7 — Publish

Delegate to `datadog-report-publisher`. The publisher writes a single Markdown artefact under `{{DATADOG_TRIAGE_DIR}}/` with all evidence rows linking back to the live Logs Explorer. **No Datadog notebook is created** — knowledge lives in the Obsidian vault only; the embedded UI deep-links keep the user one click away from live data.

Filename convention from publisher: `<YYYY-MM-DD>-<service>-<env>-<pattern-slug>.md` or `<YYYY-MM-DD>-logs-<pattern-slug>.md` when no service scope.

## Severity Guidance

| Severity | Trigger |
|----------|---------|
| `critical` | Dominant error pattern in prod is surging > 10× baseline or causes user-facing failures |
| `error` | Clear error pattern with non-trivial volume in prod, or surge in staging |
| `warn` | Non-dominant warnings, or healthy-but-noisy logs worth trimming |
| `info` | Scheduled logs review, nothing alarming found |

## Example Usage

User: "Find the top error patterns in `data-ai-mcp-business-ops` in staging over the last 4 hours"

Agent flow:

1. Confirm: `service=data-ai-mcp-business-ops`, `env=staging`, `time_window=4h`, `focus=errors`.
2. Step 1: pattern discovery → top 10 patterns.
3. Step 2: attribute discovery on top 3 → find `@http.status_code`, `@error.type`.
4. Step 3: aggregate by `@error.type` and by time bucket.
5. Step 4: grab 3 raw representative lines (redact PII).
6. Step 5: quick APM correlation → p95 also spiked? If yes, suggest `datadog-service-health`.
7. Step 6: build findings payload.
8. Step 7: publish.

Output filename example: `2026-04-21-data-ai-mcp-business-ops-staging-timeout-pattern.md`.

## Edge Cases

- **DDSQL timeout**: shorten `time_window` or tighten the `query` filter (e.g. add `status:error`). Retry once; if it still fails, report verbatim and fall back to `search_datadog_logs` with a smaller limit.
- **No logs match**: verify the service name and env, then report "no matching logs" without guessing.
- **Attribute not found**: discovered via `extra_fields` but missing in `analyze_datadog_logs`? You likely forgot `extra_columns=[...]`. Add the attribute there.
- **Logs are huge and raw sampling is slow**: prefer pattern mode (Step 1) first to cluster, then aggregate; avoid pulling thousands of raw lines.
- **PII leakage risk**: if patterns include emails, tokens, or customer IDs, redact them in the MD before publishing.

## Best Practices

1. **Patterns before aggregates before raw** — the three-step pattern/attribute/aggregation cascade is 3–10× faster than brute-force raw searches.
2. **Always state the DDSQL verbatim in the audit trail** — future-you must be able to paste-and-run it.
3. **Correlate with APM** — log surges without a matching APM regression are often noisy info-logs, not real incidents.
4. **Redact, redact, redact** — logs are the #1 source of secret leakage into reports.
5. **Suggest log-based monitors** when you had to find a surge manually.
6. **Frozen artefact** — do not mutate published triage notes; write a follow-up and cross-link if new evidence appears.

## Dependencies

Required:
- Datadog MCP server `plugin-datadog-datadog`.
- `datadog-report-publisher` skill installed.

Optional:
- `datadog-service-health` (for correlation when a service is in scope).
- `create-runbook` (to promote recurring patterns).
