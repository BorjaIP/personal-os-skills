# Datadog Skills

A suite of four skills plus a shared publisher that cover end-to-end Datadog triage. Instead of switching between APM, logs, and metrics dashboards manually, the orchestrator plans the investigation, delegates to specialised sub-skills, and consolidates everything into a single report with a linked Datadog Notebook.

## How they fit together

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

Every sub-skill delegates final publication to `datadog-report-publisher`, which writes an Obsidian-compatible Markdown artefact AND creates a persistent Datadog Notebook with embedded widgets. Both are linked bidirectionally (notebook URL in MD header, MD path in notebook first cell).

Recurring triage notes can be promoted to a runbook via the [`create-runbook`](../skills/create-runbook/) skill.

---

## datadog-triage (orchestrator)

Entry point for incident / monitor / service / alert triage. Plans the investigation, delegates to the three sub-skills below, and consolidates findings into a master report + master Datadog Notebook.

### When to use it

- An incident just fired and you need to understand what happened across APM, logs, and metrics.
- You want a single consolidated report instead of checking three dashboards separately.

### Example invocation

```
Triage the checkout-api service — latency spiked in the last 2 hours
```

---

## datadog-service-health

APM-centric service health check. Covers:

- Latency p50/p95/p99
- Error rate and throughput
- Representative failing traces
- Dependency graph
- Monitor coverage
- Deploy correlation

### When to use it

- You want a quick health snapshot of a specific service.
- You need to correlate a deploy with a latency regression.

---

## datadog-logs-analyzer

Log investigation via pattern clustering + attribute discovery + DDSQL aggregation. Produces:

- Top patterns over time
- Top offenders by attribute

### When to use it

- You see a spike in error logs and need to understand the distribution.
- You want to identify which attributes (service, host, version) correlate with the errors.

---

## datadog-metrics-investigator

Metric spike / anomaly investigation. Capabilities:

- Resolves metric metadata
- Queries sliced timeseries
- Compares to baseline
- Reuses existing dashboards / monitors
- Supports Cloud Cost metrics

### When to use it

- A metric spiked or regressed and you need to understand which tags are driving it.
- You want to investigate a Cloud Cost anomaly.

---

## datadog-report-publisher (utility)

Shared publisher invoked by the other Datadog skills. You typically don't call it directly.

- Writes the Markdown artefact to `ops/datadog/triage/`
- Creates a Datadog Notebook with embedded widgets
- Links both bidirectionally (notebook URL in MD header, MD path in notebook first cell)

All output follows the [triage architecture](triage-architecture.md) promotion pipeline.
