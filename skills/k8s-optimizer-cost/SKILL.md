---
name: k8s-optimizer-cost
description: Analyze cost efficiency and right-size Kubernetes workloads in a namespace using 7-day historical metrics from Datadog and PerfectScale-style policy-driven recommendations. Use when users ask to optimize cost, reduce waste, right-size pods/jobs, review over/under-provisioning, analyze resource requests/limits vs actual usage, or produce cost-savings reports for a namespace.
---

# Kubernetes Cost Optimizer

A skill for analyzing cost efficiency of Kubernetes workloads inside a namespace by combining declared resources (`requests`/`limits`), 7 days of historical CPU/memory metrics from Datadog, and the PerfectScale Podfit methodology to produce policy-driven right-sizing recommendations and a savings report.

This is the *cost* counterpart of [`k8s-error-analyzer`](../k8s-error-analyzer/SKILL.md): same inputs (namespace + selector), same audit-trail contract, same Obsidian-compatible report layout, but focused on `savings` / `waste` / `risk-mitigation` instead of errors.

> Human-facing usage guide with policy decision tree, worked examples, and report-reading tips: [`docs/k8s-optimizer-cost.md`](../../docs/k8s-optimizer-cost.md). Read it whenever the user asks *how* to use the skill or *which policy* to pick.

## When to Use This Skill

Use this skill when the user asks to:
- Optimize cost of a Kubernetes namespace
- Right-size pods / deployments / statefulsets / jobs
- Reduce waste from over-provisioned CPU or memory
- Identify under-provisioned workloads (OOMKilled, CPU throttling)
- Review CPU/memory requests vs actual usage over the last week
- Tune HPA / KEDA thresholds
- Produce a cost / savings report for a namespace

## Required Tools

This skill requires:

1. `kubectl` CLI configured against the target cluster:

   ```bash
   kubectl version --client
   kubectl config current-context
   ```

2. **Datadog MCP server** (`plugin-datadog-datadog`) for historical metrics over the `lookback` window (default 7d). Before starting:
   - Check that the MCP tools from `plugin-datadog-datadog` are available in your tool list.
   - If they are NOT available, follow the `ddsetup` skill first to initialize the server.
   - Always discover tool names/schema by reading the MCP descriptors at `~/.cursor/projects/*/mcps/plugin-datadog-datadog/tools/*.json` (or the Claude equivalent) before invoking any tool. Do not guess tool names.

3. Optional: `jq` (recommended for parsing `kubectl -o json`).

If `kubectl` is missing, instruct the user to install it and abort.
If the Datadog MCP is missing and the user declines to set it up, you may degrade to a **snapshot-only** mode using `kubectl top` — but you MUST warn the user that recommendations will be unreliable without a historical window, and mark the report `severity: warn` with `lookback: snapshot`.

## Input Parameters

1. **Namespace** (required): target Kubernetes namespace.
2. **Selector** (optional): label selector to narrow the scope (e.g. `app=my-app`). Default = entire namespace.
3. **Lookback** (optional): historical window for metrics. Default `7d`. Accepted: `1d`, `7d`, `14d`, `30d`.
4. **Policy** (optional): optimization policy. Default `Balanced`. One of:
   - `MaxSavings` — non-production, aggressive cost cutting.
   - `Balanced` — production default, cost/resiliency balance.
   - `ExtraHeadroom` — latency-sensitive production services.
   - `MaxHeadroom` — mission-critical, keep above worst observed spike.

   Semantics match [PerfectScale Podfit optimization policies](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing).
5. **Cluster / env** (optional): if not provided, infer from `kubectl config current-context` and namespace suffix (`*-staging`, `*-prod`, etc.).
6. **Pricing overrides** (optional): env vars `K8S_COST_CPU_EUR_PER_VCPU_MONTH` and `K8S_COST_MEM_EUR_PER_GIB_MONTH`. Defaults approximate AWS EKS `eu-west-1` on-demand: `~25 €/vCPU/month`, `~3 €/GiB/month`.

## Analysis Workflow

### Important: Command Audit Tracking

**CRITICAL**: Throughout the entire analysis, maintain a comprehensive list of every `kubectl` command AND every Datadog MCP call executed. This audit trail must be included in the final report under the "Command Audit Trail" section. Track each entry with:
- The exact command (or `server:tool` + arguments for MCP)
- Timestamp when it was run
- Brief description of why it was executed

```python
audit_trail = []

# kubectl example
audit_trail.append({
    "command": "kubectl get deployments -n payments-staging -o wide",
    "timestamp": "2026-04-21T12:30:22Z",
    "purpose": "Inventory deployments in the namespace"
})

# Datadog MCP example
audit_trail.append({
    "command": "plugin-datadog-datadog:metrics_query(query='p95:kubernetes.memory.working_set{kube_namespace:payments-staging,kube_container_name:checkout-api} by {pod_name}', from='now-7d', to='now')",
    "timestamp": "2026-04-21T12:31:05Z",
    "purpose": "P95 memory working_set over 7d for checkout-api"
})
```

### Step 1 — Namespace Inventory

Enumerate every workload and related object in the namespace:

```bash
kubectl get deployments,statefulsets,daemonsets,cronjobs,jobs,hpa,scaledobjects,pdb \
  -n <namespace> -l <selector> -o wide

kubectl get pods -n <namespace> -l <selector> -o wide
```

Capture per workload: kind, name, desired/ready replicas, owner refs, container names, image, age, whether it is targeted by an HPA or KEDA ScaledObject, QoS class of its pods.

**Add to audit trail**.

### Step 2 — Declared Resources

For each workload, read the container resource specs:

```bash
kubectl get <kind> <name> -n <namespace> -o json | \
  jq '.spec.template.spec.containers[] | {name, resources}'
```

For DaemonSets use `.spec.template`, for CronJobs use `.spec.jobTemplate.spec.template.spec.containers`. Always include `initContainers` separately.

Record for every container: `requests.cpu`, `limits.cpu`, `requests.memory`, `limits.memory`. Flag missing requests/limits explicitly — they are a significant risk/cost signal on their own.

Also read the namespace's `LimitRange` and `ResourceQuota`:

```bash
kubectl get limitrange,resourcequota -n <namespace> -o yaml
```

Recommendations MUST respect these caps (see [PerfectScale LimitRange docs](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/limitrange-and-resourcequota)). If a recommendation would violate a cap, clamp it and mark the row `Limited by Rule` with a tooltip in the report.

### Step 3 — Historical Metrics via Datadog MCP

Window = `lookback` (default 7d), tagged by `kube_namespace` and `kube_container_name`. Queries to execute (substitute `<ns>` and `<c>` per container):

| Purpose | Example query |
|---|---|
| CPU usage distribution | `p90:kubernetes.cpu.usage.total{kube_namespace:<ns>,kube_container_name:<c>} by {pod_name}` |
| CPU usage distribution | `p95:kubernetes.cpu.usage.total{kube_namespace:<ns>,kube_container_name:<c>} by {pod_name}` |
| CPU usage distribution | `p99:kubernetes.cpu.usage.total{kube_namespace:<ns>,kube_container_name:<c>} by {pod_name}` |
| CPU usage peak | `max:kubernetes.cpu.usage.total{kube_namespace:<ns>,kube_container_name:<c>}` |
| Memory distribution | `p90/p95/p99:kubernetes.memory.working_set{kube_namespace:<ns>,kube_container_name:<c>} by {pod_name}` |
| Memory peak | `max:kubernetes.memory.working_set{kube_namespace:<ns>,kube_container_name:<c>}` |
| Declared requests | `avg:kubernetes.cpu.requests{...}`, `avg:kubernetes.memory.requests{...}` |
| Declared limits | `avg:kubernetes.cpu.limits{...}`, `avg:kubernetes.memory.limits{...}` |
| Restart pressure | `sum:kubernetes.containers.restarts{...}` |
| OOM events | `sum:kubernetes.containers.last_state.terminated{reason:oomkilled,kube_namespace:<ns>,kube_container_name:<c>}` |
| CPU throttling | `avg:kubernetes.cpu.cfs.throttled.seconds{...}` and `avg:kubernetes.cpu.cfs.periods{...}` — compute `throttled_ratio = throttled_seconds / (periods * 0.1)` |
| Replicas observed | `avg/max:kubernetes_state.deployment.replicas_available{kube_namespace:<ns>,kube_deployment:<d>}` |

**Important**: Do NOT invent Datadog MCP tool names. Before the first call, read the descriptor files under `~/.cursor/projects/*/mcps/plugin-datadog-datadog/tools/` (or Claude's cache equivalent) and use the exact tool name and argument schema declared there. Call via `CallMcpTool` with `server: "plugin-datadog-datadog"`.

**Add every MCP call to the audit trail** (include the full query string and `from`/`to`).

### Step 4 — Policy-Driven Right-Sizing

For each container, compute recommended `requests` and `limits` per resource using the selected policy (PerfectScale Podfit-style):

| Policy | CPU request | CPU limit | Memory request | Memory limit |
|---|---|---|---|---|
| MaxSavings | p90 × 1.05 | p99 × 1.15 | p90 × 1.10 | p99 × 1.20 |
| Balanced (default) | p95 × 1.15 | p99 × 1.25 | p95 × 1.20 | p99 × 1.30 |
| ExtraHeadroom | p99 × 1.20 | p99.9 × 1.40 | p99 × 1.25 | p99.9 × 1.50 |
| MaxHeadroom | p99.9 × 1.30 | max × 1.50 | p99.9 × 1.35 | max × 1.60 |

**Rounding rules** (k8s-native units):
- CPU: round up to the nearest `5m` (so `137m` → `140m`).
- Memory: round up to the nearest `16Mi` (so `342Mi` → `352Mi`).
- Never recommend `0` — floor CPU at `10m`, memory at `32Mi`.

**Risk overrides** (regardless of chosen policy):
- If the container has ≥1 OOMKilled event in the window → bump the policy for that container to at least `ExtraHeadroom` for memory and mark it `risk mitigation (memory)` in the report.
- If `throttled_ratio > 0.05` (5%) → bump to at least `ExtraHeadroom` for CPU and mark as `risk mitigation (cpu)`.
- If the container has **no limits declared** and no throttling/OOM observed, keep limits unset in the recommendation but flag it in `Recommendations / Long-term` (guardrail question).

### Step 5 — Classification

Classify each container-resource row (CPU req, CPU lim, Mem req, Mem lim) into:

- `Waste` — `recommended < current × 0.80` (at least 20% over-provisioned).
- `Risk` — recommended strictly greater than current AND OOM/throttle/high-percentile evidence.
- `Balanced` — within ±20% of current.
- `Insufficient data` — container has <24h of metrics in the window (new deployments, ephemeral jobs). Do not emit a numeric recommendation; just note it.

### Step 6 — HPA / KEDA Analysis

For every HPA / ScaledObject targeting a workload in the namespace:

```bash
kubectl get hpa -n <namespace> -o yaml
kubectl get scaledobject -n <namespace> -o yaml    # if KEDA installed
```

From Datadog, retrieve observed CPU/memory utilization AS PERCENT OF REQUEST and compare to the configured `averageUtilization` target:

- Observed utilization `< 60%` → **red** (significant waste; HPA scaling too early OR requests over-sized).
- `60–80%` → **yellow** (moderate waste).
- `≥ 80%` → OK.

Also:
- Detect HPAs pinned at `maxReplicas` for more than 10% of the window → suggest raising `maxReplicas` or adding a scale-up metric.
- Detect HPAs stuck at `minReplicas` for 100% of the window on low utilization → suggest lowering `minReplicas`.

### Step 7 — Waste / Savings Estimate

Per container, approximate monthly cost:

```
cost_current     = max(cpu_request, p95_cpu_usage) * CPU_PRICE
                 + max(mem_request, p95_mem_usage) * MEM_PRICE
cost_recommended = cpu_request_reco * CPU_PRICE
                 + mem_request_reco * MEM_PRICE
savings          = (cost_current - cost_recommended) * replicas_avg
```

Where:
- `CPU_PRICE = K8S_COST_CPU_EUR_PER_VCPU_MONTH` (default `25`).
- `MEM_PRICE = K8S_COST_MEM_EUR_PER_GIB_MONTH` (default `3`).
- `replicas_avg` = average observed replicas in the window (1 for Deployments with no HPA; observed avg for HPA'd workloads; per-node count for DaemonSets).

Aggregate savings per workload and per namespace. Negative savings (risk mitigation) are shown as `+€/month` cost in their own section.

### Step 8 — Report Generation

Write the markdown report (see structure below) and save it to the configured analyses directory.

## Report Structure

The report MUST start with YAML frontmatter so it integrates with the Obsidian `ops/_index.md` Dataview queries.

**Wikilinks rule**: same contract as `k8s-error-analyzer` — never put `[[wikilinks]]` inside the YAML frontmatter. Keep frontmatter as plain strings; put every wikilink in a `## Related` section at the bottom of the body.

```markdown
---
title: <namespace> cost & right-sizing analysis
created: <YYYY-MM-DD HH:mm>
source: k8s-cost
cluster: <cluster-or-context>
env: <staging|prod|local|other>
namespace: <namespace>
project: <inferred-project>
selector: <selector-or-all>
policy: <MaxSavings|Balanced|ExtraHeadroom|MaxHeadroom>
lookback: <7d|14d|30d|snapshot>
severity: <info|warn>
status: open
tags: [ops, k8s, cost, optimization]
---

# Kubernetes Cost & Right-Sizing Report

**Namespace:** <namespace>
**Selector:** <selector or "all">
**Cluster:** <cluster>
**Policy:** <policy>
**Lookback:** <lookback>
**Analysis Date:** <timestamp>
**Analyst:** Claude (k8s-optimizer-cost skill)

---

## Executive Summary

- **Estimated monthly savings:** €X (€Y/day)
- **Estimated monthly risk-mitigation cost:** €Z (required to fix OOM/throttle)
- **Net impact:** €(X - Z)/month
- **Workloads analyzed:** N (D deployments, S statefulsets, DS daemonsets, CJ cronjobs, J jobs)
- **Containers over-provisioned:** A
- **Containers under-provisioned (risk):** B
- **HPAs / KEDA objects with waste:** C

Brief narrative of the top 3 optimization opportunities and top 3 risks.

---

## Workload Inventory

| Kind | Name | Replicas (avg) | Containers | HPA | KEDA | QoS |
|------|------|----------------|------------|-----|------|-----|
| ...  | ...  | ...            | ...        | ... | ...  | ... |

---

## Right-sizing Recommendations

One table per workload. Example:

### Deployment: `checkout-api`

| Container | Resource | p90 | p95 | p99 | Max | Current | Recommended | Δ% | Class | €/mo saved |
|-----------|----------|-----|-----|-----|-----|---------|-------------|-----|-------|------------|
| `api`     | CPU req  | 120m | 180m | 240m | 410m | 500m | 210m | -58% | Waste | +€7.25 |
| `api`     | CPU lim  | —    | —    | —    | 410m | 1000m | 305m | -69% | Waste | — |
| `api`     | Mem req  | 420Mi | 510Mi | 640Mi | 780Mi | 1Gi | 624Mi | -39% | Waste | +€1.12 |
| `api`     | Mem lim  | —    | —    | —    | 780Mi | 2Gi | 832Mi | -59% | Waste | — |

Add a single-line rationale per workload (e.g. "Steady low-utilisation service; safe to cut requests ~60%.").

---

## Waste Leaderboard (Top 10)

| # | Workload / Container | Waste €/mo | Dominant driver |
|---|----------------------|------------|-----------------|
| 1 | ...                  | ...        | CPU requests    |

---

## Risk Mitigation (Must-fix, Cost UP)

Containers with confirmed OOMKilled, CPU throttling, or memory climbing. These recommendations INCREASE cost but are required for stability.

| Workload / Container | Issue | Evidence (count/ratio) | Recommended action | Cost delta |
|----------------------|-------|------------------------|--------------------|-----------|
| ...                  | OOM   | 14 events in 7d         | Mem req 512Mi → 768Mi, lim 1Gi → 1.5Gi | +€4.10/mo |

---

## HPA / KEDA Analysis

| HPA / ScaledObject | Target | Observed p95 utilization | Status | Recommendation |
|--------------------|--------|--------------------------|--------|----------------|
| `checkout-api-hpa` | CPU 80% | 34% | Red (waste) | Drop CPU target to 65% OR cut requests -50% |
| ...                | ...    | ...                      | ...    | ...            |

Include replicas observed (min/avg/max) and whether `maxReplicas` was hit.

---

## Jobs & CronJobs

For each Job / CronJob with ≥3 successful runs in the window:

| Job | Runs observed | Peak CPU | Peak Mem | Current req/lim | Recommended req/lim |
|-----|---------------|----------|----------|-----------------|---------------------|
| ... | ...           | ...      | ...      | ...             | ...                 |

Jobs with <3 runs: list under `Insufficient data`, no recommendation.

---

## Actionable Patches

Ready-to-apply YAML snippets. Prefer Helm values patches when the source is a chart; otherwise `kubectl patch`.

```yaml
# Deployment: checkout-api
resources:
  requests:
    cpu: 210m      # was 500m
    memory: 624Mi  # was 1Gi
  limits:
    cpu: 305m      # was 1000m
    memory: 832Mi  # was 2Gi
```

```bash
kubectl -n <namespace> set resources deployment/checkout-api \
  --containers=api \
  --requests=cpu=210m,memory=624Mi \
  --limits=cpu=305m,memory=832Mi
```

---

## Managed Sidecars — review manually

Sidecars (e.g. `istio-proxy`, `datadog-agent`, `vault-agent`) are listed here without automatic recommendations. Owners of those integrations should right-size them centrally.

| Container | Present in # pods | Current CPU req/lim | Current Mem req/lim |
|-----------|------------------|---------------------|---------------------|

---

## Recommendations

### Priority 1 — Immediate savings (low risk)
1. [Specific workload + change + €/mo saved]

### Priority 2 — Short-term tuning
1. HPA threshold adjustments
2. Add missing requests on containers that currently have none

### Priority 3 — Long-term / architectural
1. Consolidate low-utilisation workloads
2. Review node groups (Infrafit) — out of scope of this skill
3. Set `LimitRange` defaults for the namespace

---

## Command Audit Trail

| # | Timestamp | Command / MCP call | Purpose |
|---|-----------|--------------------|---------|
| 1 | HH:MM:SS  | `kubectl get deployments,statefulsets,daemonsets,cronjobs,jobs,hpa,scaledobjects,pdb -n <ns> -o wide` | Namespace inventory |
| 2 | HH:MM:SS  | `kubectl get deployment <name> -n <ns> -o json` | Declared resources |
| 3 | HH:MM:SS  | `plugin-datadog-datadog:metrics_query(...)` | p95 memory working_set 7d |
| ... | ...     | ...                | ...   |

**Total commands executed:** X (kubectl: A, Datadog MCP: B)

**Reproducibility:** Every call above can be re-run to reproduce this analysis.

---

## Appendix: Full Datadog queries

```
# CPU usage p95 per pod, last 7d
p95:kubernetes.cpu.usage.total{kube_namespace:<ns>,kube_container_name:<c>} by {pod_name}

# Memory working_set p99 per pod, last 7d
p99:kubernetes.memory.working_set{kube_namespace:<ns>,kube_container_name:<c>} by {pod_name}

# CPU throttling ratio, last 7d
avg:kubernetes.cpu.cfs.throttled.seconds{kube_namespace:<ns>,kube_container_name:<c>}
  / (avg:kubernetes.cpu.cfs.periods{kube_namespace:<ns>,kube_container_name:<c>} * 0.1)
```

---

## Related

Every report MUST end with this section. Unquoted body-wikilinks (valid in Obsidian body, invalid in frontmatter):

- [[Kubernetes]]
- [[FinOps]]
- [[PerfectScale]]
- [[<relevant project MOC if any>]]

---

**Report Generated by:** Claude k8s-optimizer-cost skill
**Timestamp:** <ISO-8601 timestamp>
```

## Report Storage

All reports must be saved to the configured analyses directory. The default (injected at install time) is:

```
{{K8S_COST_ANALYSES_DIR}}
```

This normally points at `ops/k8s-cost/` inside the user's Obsidian vault. If the placeholder was not replaced at install time (Obsidian not configured), fall back to `./docs/cost_analyses/` relative to the current working directory and warn the user.

Filename format (date-first so Obsidian/Finder sort chronologically):

```
<YYYY-MM-DD>-<namespace>.md
<YYYY-MM-DD>-<namespace>-<selector-sanitized>.md       # when a selector was used
<YYYY-MM-DD>-<HHMM>-<namespace>[-<selector>].md        # when multiple reports per day
```

Examples:
- `2026-04-21-payments-staging.md`
- `2026-04-21-payments-staging-app-checkout-api.md`

Create the directory if it doesn't exist:

```bash
mkdir -p "{{K8S_COST_ANALYSES_DIR}}"
```

**Runbook promotion hint**: if the skill detects ≥2 existing cost reports for the same namespace in the last 14 days, suggest the user promote recurring findings to a reusable runbook via the `create-runbook` skill.

## Best Practices

1. **Audit everything**: every `kubectl` and every Datadog MCP call goes into the audit trail with timestamp + purpose.
2. **Percentiles over averages**: use p95 for requests and p99 for limits — averages hide bursts that cause throttling and OOM.
3. **Respect LimitRange/ResourceQuota**: clamp recommendations and mark `Limited by Rule`.
4. **Risk always beats savings**: if OOM or throttling is confirmed, bump the policy for that container and tolerate the cost increase.
5. **Actionable output**: every recommendation comes with a ready-to-apply YAML snippet or `kubectl` command.
6. **Evidence in the report**: include the observed percentiles alongside the recommendation so the reader can verify.
7. **One workload = one sub-section**: do not mix metrics across workloads in the same table.
8. **Savings are estimates**: always include the pricing assumptions used (`€/vCPU/month`, `€/GiB/month`) in the report footer.

## Edge Cases

- **Insufficient data** (<24h of metrics for a container): skip numeric recommendations, list under `Insufficient data` so the user knows to re-run later.
- **Jobs / CronJobs with <3 runs in the window**: same treatment as above.
- **DaemonSets**: cost multiplier is number of nodes in the scheduling set, not `spec.replicas`. Recommend per-node values and multiply by the observed node count for savings.
- **Init containers**: analyze separately; flag any init container whose request exceeds 30% of the pod total (blocks node packing for the whole pod lifetime while only running at startup).
- **Sidecars** (`istio-proxy`, `datadog-agent`, `vault-agent`, `linkerd-proxy`, …): list under `Managed Sidecars — review manually`, do not emit automated recommendations.
- **Missing requests / missing limits**: highlight explicitly — these are both a cost risk (unbounded) and a scheduling risk (BestEffort QoS).
- **Multi-container pods**: recommend per container; do not aggregate.
- **Datadog gaps**: if a container has no metrics in Datadog (e.g. recently renamed, no agent on the node), say so in the report and fall back to `kubectl top` snapshot for that container with a warning.
- **Sensitive data**: never copy env var values, secret contents, or volume mount paths that look like credentials. Redact.

## Example Usage

User: *"Optimize cost for namespace `payments-staging` with Balanced policy."*

Response flow:
1. Confirm inputs: `namespace=payments-staging`, `selector=<all>`, `lookback=7d`, `policy=Balanced`.
2. Verify `kubectl` context and that Datadog MCP tools are loaded.
3. Inventory namespace (Step 1) — record counts.
4. Read declared resources + LimitRange/ResourceQuota (Step 2).
5. Pull 7d metrics via Datadog MCP (Step 3).
6. Compute recommendations per policy (Step 4) with OOM/throttle overrides.
7. Classify, run HPA analysis, compute savings (Steps 5–7).
8. Write report with YAML frontmatter to `{{K8S_COST_ANALYSES_DIR}}/2026-04-21-payments-staging.md`.
9. Present the report to the user and surface top 3 wins and top 3 risks verbally.
10. If ≥2 reports already exist for this NS in 14d, suggest promotion to a runbook.

## Final Output

After completing the analysis:

1. Create the markdown report with frontmatter.
2. Save it to `{{K8S_COST_ANALYSES_DIR}}` (or fallback).
3. Share the report path with the user.
4. Provide a verbal summary: total estimated monthly savings, net impact, top 3 waste offenders, top 3 risks to fix first.

## Dependencies

Required:
- `kubectl` with cluster context and RBAC to read deployments, statefulsets, daemonsets, cronjobs, jobs, pods, hpa, scaledobjects, limitranges, resourcequotas.
- Datadog MCP server `plugin-datadog-datadog` configured and authenticated against an org that collects the target cluster.

Optional:
- `jq` for `-o json` parsing.
- KEDA installed in the cluster (for `scaledobject` inspection).

## Notes

- Pricing defaults are rough approximations for AWS EKS `eu-west-1` on-demand. Override via env vars for other clouds / regions / Savings Plans.
- The skill does NOT apply any changes automatically — it only produces recommendations, YAML snippets, and `kubectl` commands. Humans / PRs apply them.
- This skill covers workload right-sizing (PerfectScale Podfit equivalent). Node-level / cluster-level right-sizing (Infrafit equivalent) is out of scope.

## Further Reading & Inspiration

Methodology and vocabulary are borrowed from PerfectScale's Podfit. Canonical references:

- [PerfectScale — Podfit (vertical pod right-sizing)](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing) — recommendations table, Waste/Risk categories, Zoom-in view.
- [PerfectScale — Optimization Policy customization](https://docs.perfectscale.io/customize-workflow/optimization-policy-customization) — formal definition of the 4 policies, independent CPU/memory policies.
- [PerfectScale — HPA view](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing#hpa-view) — Red/Yellow/OK thresholds for HPA utilisation.
- [PerfectScale — LimitRange and ResourceQuota](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/limitrange-and-resourcequota) — how recommendations respect namespace caps.
- [PerfectScale — Muted workload](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/muted-workload) — workloads excluded from the analysis (use `selector` locally to achieve the same effect).

Official Kubernetes docs:

- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/) / [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

See [`docs/k8s-optimizer-cost.md`](../../docs/k8s-optimizer-cost.md) for the human-facing guide with policy decision tree and worked examples.
