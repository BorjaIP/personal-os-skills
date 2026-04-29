# k8s-optimizer-cost — usage guide

This skill analyzes cost and right-sizing of the workloads inside a Kubernetes namespace and produces a Markdown report with actionable recommendations. **It never modifies the cluster**: it only reads (`kubectl get/describe`) and queries historical metrics via the Datadog MCP. A human decides what to apply (Helm chart PR, `kubectl set resources`, etc.).

It is heavily inspired by the **[PerfectScale Podfit](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing)** methodology (vertical pod right-sizing). The core idea is the same: look at real usage percentiles (p90 / p95 / p99 / max) over a long-enough window, apply an **optimization policy** chosen by the user based on the service profile, and emit `requests` / `limits` recommendations that balance cost and resiliency.

> For installation, output paths and the general triage → runbook architecture, see [triage-architecture.md](triage-architecture.md).

---

## 1. When to use this skill

Use it when you want to answer any of these questions about a specific namespace:

- How much am I overspending on CPU/memory in `<namespace>`?
- Which workloads are over-sized (waste) and which are under-sized (risk / OOM / throttling)?
- Are my HPA/KEDA targets healthy? Is `averageUtilization` in a reasonable range?
- How much would I save per month if I cut requests on deployment X?
- Which Jobs/CronJobs are asking for far more resources than they actually use?

Do **not** use it if:

- You only have a snapshot and no 24h+ of metrics (percentiles would not be reliable).
- You want to optimize at the node / node-group level (that is *Infrafit* in PerfectScale terminology and is out of scope for this skill).
- You want something to apply the changes automatically (use VPA or PerfectScale Automation; this skill is read-only).

---

## 2. Inputs

| Parameter | Required | Default | Values |
|-----------|----------|---------|--------|
| `namespace` | yes | — | any namespace reachable by `kubectl` |
| `selector` | no | whole NS | label selector, e.g. `app=checkout-api,tier=backend` |
| `lookback` | no | `7d` | `1d`, `7d`, `14d`, `30d` |
| `policy` | no | `Balanced` | `MaxSavings`, `Balanced`, `ExtraHeadroom`, `MaxHeadroom` |
| `cluster` / `env` | no | inferred | free text (used in the report frontmatter) |

Two optional environment variables control the pricing used to estimate savings:

| Env var | Default | Meaning |
|---------|---------|---------|
| `K8S_COST_CPU_EUR_PER_VCPU_MONTH` | `25` | € per vCPU per month |
| `K8S_COST_MEM_EUR_PER_GIB_MONTH` | `3` | € per GiB per month |

Defaults are a rough approximation for AWS EKS `eu-west-1` on-demand. Override them if you run on a different region / cloud, Savings Plans, or Spot instances before invoking the skill.

---

## 3. The 4 optimization policies (PerfectScale inspiration)

PerfectScale encapsulates the *cost vs. resiliency* trade-off in a single variable: the **optimization policy**. The same recommendation can come out with a very thin margin (more savings, more risk) or with a very generous headroom (less savings, more resilience) depending on the profile you pick. See the canonical definition at [PerfectScale — Optimization Policy customization](https://docs.perfectscale.io/customize-workflow/optimization-policy-customization).

The skill exposes the **same 4 policies** with the same semantics, but with its own implementation (percentiles + multipliers) so that it is reproducible without requiring PerfectScale itself.

### 3.1 Formulas

| Policy | CPU request | CPU limit | Memory request | Memory limit |
|---|---|---|---|---|
| `MaxSavings` | p90 × 1.05 | p99 × 1.15 | p90 × 1.10 | p99 × 1.20 |
| `Balanced` (default) | p95 × 1.15 | p99 × 1.25 | p95 × 1.20 | p99 × 1.30 |
| `ExtraHeadroom` | p99 × 1.20 | p99.9 × 1.40 | p99 × 1.25 | p99.9 × 1.50 |
| `MaxHeadroom` | p99.9 × 1.30 | max × 1.50 | p99.9 × 1.35 | max × 1.60 |

Values are rounded up to the nearest `5m` of CPU and `16Mi` of memory. Minimum floor: `10m` CPU, `32Mi` memory.

### 3.2 What each one means and when to use it

#### `MaxSavings` — maximum savings

- **PerfectScale profile**: "Low Resiliency — best for non-production environments".
- **What it does**: sizes `requests` practically at the p90 of real usage. Headroom is minimal (5–10%).
- **When to use it**:
  - `staging`, `dev`, `preview`, ephemeral environments.
  - Non-critical batch jobs and CronJobs.
  - Services with soft SLAs where a single OOM has no user-visible impact.
- **When NOT to use it**: production, latency-critical services, user-facing APIs, workloads with irregular spikes.

#### `Balanced` (default) — cost/resiliency balance

- **PerfectScale profile**: "Medium Resiliency — optimally balances cost and resiliency".
- **What it does**: `requests` at p95 with +15–20% margin; `limits` at p99 with +25–30%.
- **When to use it**:
  - Standard production, relatively predictable load.
  - It's the reasonable default when in doubt.
  - Most internal APIs, workers, data pipelines.
- **When NOT to use it**: services with sharp spikes, or where the cost of an OOM is very high (checkout / payments at peak hours, synchronous payment paths).

#### `ExtraHeadroom` — latency-critical

- **PerfectScale profile**: "High Resiliency — best fit for latency-sensitive environments".
- **What it does**: `requests` at p99 with +20–25%; `limits` at p99.9 with +40–50%.
- **When to use it**:
  - User-facing production APIs with a latency SLO (p99 < X ms).
  - Services that cannot tolerate GC pauses caused by memory pressure.
  - Gateways, auth, hot-path checkout services.
  - **The skill activates it automatically** if it detects OOMKilled events or CPU throttling > 5% in the window.
- **When NOT to use it**: to save money — the goal here is stability, not cost.

#### `MaxHeadroom` — mission critical / spike-heavy

- **PerfectScale profile**: "Highest Resiliency — keeps the environment above the highest spikes".
- **What it does**: `requests` at p99.9 with +30–35%; `limits` at the **maximum observed value** with +50–60%.
- **When to use it**:
  - Mission-critical production services that cannot degrade.
  - Workloads with known spikes (campaigns, sales events, big releases).
  - Databases, queues, caches.
  - When the cost of an incident clearly outweighs any possible savings.
- **When NOT to use it**: anything that does not need the maximum buffer; usually it's pure over-provisioning.

### 3.3 Quick decision tree

```
Is it production?
├── No → MaxSavings
└── Yes
    ├── Does it have a strict p99/p99.9 latency SLO?
    │   ├── Yes → ExtraHeadroom
    │   └── No
    │       ├── Mission critical / unpredictable spikes?
    │       │   ├── Yes → MaxHeadroom
    │       │   └── No → Balanced (default)
```

### 3.4 Automatic risk overrides

Regardless of the policy you pick, the skill can **bump** the policy for a specific container if it finds evidence of under-provisioning:

- ≥1 `OOMKilled` event in the window → forces at least `ExtraHeadroom` for that container's memory. Marked as *risk mitigation (memory)* in the report.
- CPU throttling ratio > 5% (throttled_seconds / (periods × 0.1)) → forces at least `ExtraHeadroom` for CPU. Marked as *risk mitigation (cpu)*.

These overrides always **raise** cost (instead of lowering it) and the report surfaces them in a dedicated *Risk Mitigation* section, separate from the *Waste Leaderboard*.

### 3.5 Can I use different policies for CPU and memory?

PerfectScale supports independent policies for CPU and memory ([docs](https://docs.perfectscale.io/customize-workflow/optimization-policy-customization#independent-optimization-policies-for-cpu-and-memory)). Today the skill applies the same policy to both resources, with the exception of the automatic overrides (which can bump only CPU or only memory based on the evidence). If you need fine granularity, generate the report twice with different policies and cross the CPU/memory blocks manually.

---

## 4. Invocation examples

The skill is triggered automatically by the skill selector when the user asks about cost optimization, right-sizing, or resource analysis. Examples that activate it:

```
Optimize the cost of the payments-staging namespace.
```

```
Right-size the workloads in analytics-prod with ExtraHeadroom policy and a 14-day lookback.
```

```
Where am I spending too much in the checkout namespace? Only the ones labelled tier=backend.
```

```
Check whether the HPA for checkout-api-prod is configured correctly.
```

### 4.1 Typical execution flow

Example: *"Optimize the cost of payments-staging with Balanced policy"*.

1. The skill echoes back the resolved inputs:
   - `namespace = payments-staging`
   - `selector = <all>`
   - `lookback = 7d`
   - `policy = Balanced`
2. Verifies that `kubectl` and the Datadog MCP (`plugin-datadog-datadog`) are available.
3. **Step 1 — Inventory**:
   ```bash
   kubectl get deployments,statefulsets,daemonsets,cronjobs,jobs,hpa,scaledobjects,pdb \
     -n payments-staging -o wide
   ```
4. **Step 2 — Declared resources**: reads `requests` / `limits` + `LimitRange` / `ResourceQuota`.
5. **Step 3 — Datadog metrics** (7d):
   ```
   p95:kubernetes.memory.working_set{kube_namespace:payments-staging,kube_container_name:checkout-api} by {pod_name}
   p99:kubernetes.cpu.usage.total{kube_namespace:payments-staging,kube_container_name:checkout-api} by {pod_name}
   sum:kubernetes.containers.last_state.terminated{reason:oomkilled,kube_namespace:payments-staging}
   avg:kubernetes.cpu.cfs.throttled.seconds{kube_namespace:payments-staging}
   ```
6. **Steps 4–7**: computes recommendations per policy, classifies Waste / Risk / Balanced, analyzes HPAs, estimates €/month savings.
7. **Step 8**: writes the report to `{{K8S_COST_ANALYSES_DIR}}/2026-04-21-payments-staging.md` (typically `<vault>/ops/k8s-cost/...`).
8. Presents the report to the user with a verbal summary (top 3 wins, top 3 risks).

---

## 5. How to read the generated report

The report has 12 sections. You do not have to read them in order; this is the recommended reading order depending on what you are after:

| You want… | Start with |
|-----------|------------|
| How much can I save right now? | `Executive Summary` → `Waste Leaderboard` → `Actionable Patches` |
| What is about to blow up? | `Risk Mitigation` (containers with OOM / throttle) |
| Are my HPA/KEDA healthy? | `HPA / KEDA Analysis` |
| Detail of a specific workload | `Right-sizing Recommendations` (one subsection per workload) |
| Reproduce the analysis | `Command Audit Trail` + `Appendix` (full Datadog queries) |

### 5.1 Row classification

Every container-resource (CPU req, CPU lim, Mem req, Mem lim) is classified as:

- **`Waste`** — `recommended < current × 0.80` (>20% over-provisioned). Money you can save.
- **`Risk`** — `recommended > current` with OOM / throttle evidence. **Must** be raised.
- **`Balanced`** — within ±20% of the current value. Leave it alone.
- **`Insufficient data`** — <24h of metrics in the window (new deployment, ephemeral Job). No numeric recommendation emitted.

### 5.2 Example waste row

```
| Container | Resource | p90  | p95  | p99  | Max  | Current | Recommended | Δ%   | Class | €/mo saved |
|-----------|----------|------|------|------|------|---------|-------------|------|-------|------------|
| api       | CPU req  | 120m | 180m | 240m | 410m | 500m    | 210m        | -58% | Waste | +€7.25     |
```

Interpretation: container `api` requests 500m of CPU but its real p95 is 180m. With `Balanced` policy (p95 × 1.15) the recommendation is 210m. Applying this across every replica saves ~€7.25/month.

### 5.3 Example risk-mitigation row

```
| Workload / Container | Issue | Evidence           | Recommended action                            | Cost delta   |
|----------------------|-------|--------------------|-----------------------------------------------|--------------|
| checkout-api / api   | OOM   | 14 events in 7d    | Mem req 512Mi→768Mi, lim 1Gi→1.5Gi            | +€4.10/mo    |
```

Interpretation: 14 OOMKilled events in 7 days → the skill ignores your chosen policy (even if it was `MaxSavings`) and applies `ExtraHeadroom` for this container's memory. Cost rises by €4.10/month but it's required for stability.

### 5.4 Actionable Patches

For every workload with recommended changes, the report includes 2 copy-pasteable formats:

**Helm chart / `values.yaml` snippet:**

```yaml
resources:
  requests:
    cpu: 210m      # was 500m
    memory: 624Mi  # was 1Gi
  limits:
    cpu: 305m      # was 1000m
    memory: 832Mi  # was 2Gi
```

**Direct `kubectl` command (for quick tests without a PR):**

```bash
kubectl -n payments-staging set resources deployment/checkout-api \
  --containers=api \
  --requests=cpu=210m,memory=624Mi \
  --limits=cpu=305m,memory=832Mi
```

Remember: the skill does NOT execute these commands. It generates them so you can decide the deployment vehicle (chart PR, temporary `kubectl patch`, etc.).

---

## 6. How savings are computed

Per container:

```
cost_current     = max(cpu_request, p95_cpu_usage)  × CPU_PRICE
                 + max(mem_request, p95_mem_usage)  × MEM_PRICE
cost_recommended = cpu_request_reco × CPU_PRICE
                 + mem_request_reco × MEM_PRICE
savings          = (cost_current − cost_recommended) × replicas_avg
```

Where:

- `CPU_PRICE = K8S_COST_CPU_EUR_PER_VCPU_MONTH` (default `25`).
- `MEM_PRICE = K8S_COST_MEM_EUR_PER_GIB_MONTH` (default `3`).
- `replicas_avg`:
  - Deployments with no HPA → `spec.replicas`.
  - Deployments with HPA → observed average over the window.
  - DaemonSets → number of nodes in the scheduling set (multiplied at the end, not `spec.replicas`).

Savings are **aggregated per workload and per namespace** in the `Executive Summary` and `Waste Leaderboard`.

> Warning: the numbers are estimates. They are useful for prioritisation, not for finance reporting. Actual cost depends on cluster bin-packing, whether your cloud charges per reserved or used vCPU, Savings Plans / Spot, etc.

---

## 7. Edge cases and things NOT optimized automatically

| Case | Behaviour |
|------|-----------|
| Container with <24h of metrics | `Insufficient data` — no recommendation emitted |
| Job/CronJob with <3 runs in the window | `Insufficient data` — no recommendation emitted |
| DaemonSets | Per-node recommendation, multiplied by the number of nodes for savings |
| Init containers | Analyzed separately; warning if they consume >30% of the pod's total request |
| Sidecars (`istio-proxy`, `datadog-agent`, `vault-agent`, …) | Listed under *Managed Sidecars — review manually*, no automatic recommendation. See [PerfectScale Muted workload](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/muted-workload) for the equivalent concept |
| Missing `requests` or `limits` | Explicitly flagged (QoS `BestEffort` or unbounded) in the report |
| `LimitRange` / `ResourceQuota` in the namespace | Recommendations are **clamped** to those caps, with a `Limited by Rule` badge. See [PerfectScale LimitRange and ResourceQuota](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/limitrange-and-resourcequota) |
| Container with no Datadog metrics (recently renamed, etc.) | Fallback to a `kubectl top` snapshot with a warning |

---

## 8. Promotion: when to turn a report into a runbook

If you generate ≥2 cost reports for the same namespace within 14 days, the skill suggests promoting the recurring findings to a runbook using the [`create-runbook`](../skills/create-runbook/SKILL.md) skill. This is useful when you detect recurring patterns such as:

- "This namespace accumulates workloads with over-estimated `requests` because the chart template inherits them from `values.yaml` and no one reviews them per service".
- "Jobs from this CronJob are always 3× over-sized by default".

The resulting runbook lives in `ops/runbooks/` and documents the repeatable procedure (how to pick the policy, how to generate the PR, who approves). See [triage-architecture.md — promotion pipeline](triage-architecture.md#3-the-promotion-pipeline).

---

## 9. Further reading & inspiration

The skill does not implement PerfectScale — it just adopts its methodology and vocabulary so that anyone familiar with the product gets a short learning curve.

### PerfectScale documentation

- **[PerfectScale Podfit (vertical pod right-sizing)](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing)** — the conceptual foundation: recommendations table, Waste/Risk categories, Zoom-in view.
- **[Optimization Policy customization](https://docs.perfectscale.io/customize-workflow/optimization-policy-customization)** — formal definition of MaxSavings / Balanced / ExtraHeadroom / MaxHeadroom, independent CPU/memory policies, optional CRD.
- **[HPA view](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing#hpa-view)** — Red/Yellow/OK criteria for HPA thresholds (<60% / 60–80% / ≥80%).
- **[LimitRange and ResourceQuota](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/limitrange-and-resourcequota)** — how to respect namespace caps when generating recommendations.
- **[Muted workload](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/muted-workload)** — workloads that should be excluded from the analysis (local equivalent: use `selector` to filter them out).

### Official Kubernetes documentation

- **[Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)** — canonical reference for `requests` / `limits`, QoS classes, CPU throttling semantics.
- **[Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)** — HPA v2 behavior, stabilization window, scaling policies.
- **[Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)** — VPA reference; this skill does **not** replace VPA, it only emits offline recommendations.
- **[LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)** and **[ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)** — namespace-level policies the skill respects and clamps recommendations against.

---

## 10. Quick FAQ

**Does it modify the cluster?** No. It is read-only. It produces a Markdown report with recommendations and YAML snippets. You decide what to apply and how.

**Do I need PerfectScale installed?** No. The skill only borrows the methodology. Metrics come from Datadog via MCP.

**And if I don't have Datadog?** You can degrade to snapshot mode (`kubectl top`) with a warning, but recommendations will be unreliable because there is no time distribution. The skill marks the report `lookback: snapshot` and `severity: warn`.

**Why 7 days by default?** It is the minimum reasonable window to capture the weekly cycle (weekdays vs weekend, nightly batch jobs, etc.). For workloads with monthly spikes (e.g. month-end closings) raise it to `30d`.

**Is the savings number real?** It is an estimate. It's good for prioritisation. Actual savings depend on cluster bin-packing, cloud contracts, and whether you can consolidate nodes after lowering the aggregate requests.

**What if I have many workloads?** The report can get long. Use `selector` to narrow it down (e.g. `tier=backend`, `team=checkout`). Alternatively, generate one report per namespace and aggregate manually.

**Can I automate applying the recommendations?** Not with this skill. If you want that level of automation, look at PerfectScale Automation, VPA in-place updates (Kubernetes 1.33+), or a custom pipeline that takes the YAML snippets from the report and opens PRs automatically.
