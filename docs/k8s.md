# Kubernetes Skills

Two skills cover the Kubernetes lifecycle: diagnosing pod failures and optimising resource costs.

## k8s-error-analyzer

Analyzes Kubernetes pod failures by reading logs (with label selector support), identifies errors, and generates a structured analysis report in `ops/k8s/`.

### What it does

1. Inspects pod status, events, and logs via `kubectl`.
2. Captures every command in an audit trail for reproducibility.
3. Writes a Markdown artefact to `ops/k8s/YYYY-MM-DD-<scope>-<resource>.md` with frontmatter, root cause analysis, and recommended actions.

### When to use it

- A pod is crash-looping and you need a structured diagnosis fast.
- You want a searchable record of the failure in your vault instead of a throwaway terminal session.
- You want to hand off the analysis to someone else with full context.

### Example invocation

```
Analyse the failures in the checkout-web pods in payments-staging
```

Output lands in `ops/k8s/` and follows the [triage architecture](triage-architecture.md) promotion pipeline.

---

## k8s-optimizer-cost

Right-sizes workloads using 7 days of Datadog metrics and PerfectScale's policy-driven methodology (MaxSavings / Balanced / ExtraHeadroom / MaxHeadroom).

For the full usage guide, optimization policies, report format, and FAQ see **[k8s-optimizer-cost.md](k8s-optimizer-cost.md)**.

### Quick summary

- Reads `kubectl` + Datadog metrics (read-only, never modifies the cluster).
- Applies one of 4 policies to compute `requests`/`limits` recommendations.
- Classifies each container as Waste / Risk / Balanced.
- Estimates €/month savings and generates copy-pasteable Helm and `kubectl` patches.
- Detects OOMKilled and CPU throttling and auto-bumps the policy for affected containers.

### Example invocation

```
Optimize the cost of the payments-staging namespace with Balanced policy
```

Output lands in `ops/k8s-cost/`.

---

## Further reading

- [PerfectScale — Podfit (vertical pod right-sizing)](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing)
- [PerfectScale — Optimization Policy customization](https://docs.perfectscale.io/customize-workflow/optimization-policy-customization)
- [PerfectScale — HPA view](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing#hpa-view)
- [PerfectScale — LimitRange and ResourceQuota](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/limitrange-and-resourcequota)
- [PerfectScale — Muted workload](https://docs.perfectscale.io/visibility-and-optimization/podfit-or-vertical-pod-right-sizing/muted-workload)
- [Kubernetes — Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes — Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Kubernetes — Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
