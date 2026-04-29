---
name: k8s-error-analyzer
description: Analyze Kubernetes pod failures by reading logs from pods (supports label selectors), identifying errors and issues, and generating detailed error analysis reports. Use when users ask to troubleshoot pods, analyze Kubernetes errors, investigate pod failures, or understand what's wrong with their applications in k8s.
---

# Kubernetes Error Analyzer

A skill for analyzing failures in Kubernetes pods by reading pod logs, identifying issues, and generating comprehensive error analysis reports.

## When to Use This Skill

Use this skill when the user asks to:
- Analyze pod failures or errors
- Troubleshoot Kubernetes applications
- Investigate why pods are crashing or failing
- Understand what's happening in their k8s cluster
- Debug application issues in Kubernetes
- Review logs from multiple pods
- Create reports about k8s errors

## Required Tools

This skill requires access to `kubectl` command-line tool. Before starting, verify kubectl is available and configured:

```bash
kubectl version --client
kubectl config current-context
```

If kubectl is not available, inform the user and provide installation instructions.

## Input Parameters

The skill requires the following inputs from the user:

1. **Namespace** (required): The Kubernetes namespace where the pods are running
   - Can be obtained with: `kubectl get namespaces`
   - Default namespace is often "default"

2. **Pod Selector** (required): Either a pod name or label selector
   - Pod name: `my-app-pod-xyz123`
   - Label selector: `app=my-app` or `app=my-app,tier=backend`
   - Label selectors allow analyzing multiple pods with the same label

3. **Time Range** (optional): How far back to retrieve logs
   - Default: all available logs
   - Can specify: `--since=1h`, `--since=30m`, `--tail=1000`

## Analysis Workflow

### Important: Command Audit Tracking

**CRITICAL**: Throughout the entire analysis, maintain a comprehensive list of every kubectl command executed. This audit trail must be included in the final report under the "Command Audit Trail" section. Track each command with:
- The exact command executed
- Timestamp when it was run
- Brief description of why it was executed

Store commands in a list as you execute them:
```python
audit_trail = []

# Example when executing a command:
cmd = "kubectl get pods -n production -l app=web-frontend -o wide"
audit_trail.append({
    "command": cmd,
    "timestamp": "2025-02-13T14:30:22Z",
    "purpose": "Retrieve pod status and basic information for all web-frontend pods"
})
```

### Step 1: Gather Pod Information

First, collect information about the pods:

```bash
# If using pod name
kubectl get pod <pod-name> -n <namespace> -o wide

# If using label selector
kubectl get pods -n <namespace> -l <label-selector> -o wide
```

**Add to audit trail**: Document this command execution

Capture:
- Pod names
- Pod status (Running, CrashLoopBackOff, Error, etc.)
- Restart count
- Node placement
- Age
- Ready status

### Step 2: Check Pod Events

Events often reveal why pods are failing:

```bash
# For specific pod
kubectl describe pod <pod-name> -n <namespace>

# For all pods matching selector
for pod in $(kubectl get pods -n <namespace> -l <label-selector> -o name); do
  echo "=== Events for $pod ==="
  kubectl describe $pod -n <namespace> | grep -A 20 "Events:"
done
```

**Add to audit trail**: Document each describe command executed

Look for:
- ImagePullBackOff errors
- OOMKilled events
- Liveness/Readiness probe failures
- Resource constraints
- Scheduling issues

### Step 3: Retrieve Pod Logs

Collect logs from all pods:

```bash
# For a single pod
kubectl logs <pod-name> -n <namespace> --tail=500 --timestamps

# For all containers in a pod (if multi-container)
kubectl logs <pod-name> -n <namespace> --all-containers=true --tail=500 --timestamps

# For previous container instance (if pod restarted)
kubectl logs <pod-name> -n <namespace> --previous --tail=500 --timestamps

# For multiple pods with label selector
for pod in $(kubectl get pods -n <namespace> -l <label-selector> -o name | cut -d'/' -f2); do
  echo "=== Logs from $pod ==="
  kubectl logs $pod -n <namespace> --tail=500 --timestamps
done
```

**Add to audit trail**: Document each logs command executed (including --previous, --all-containers flags used)

### Step 4: Analyze Logs

Parse the logs to identify:

**Error Patterns:**
- Stack traces (Java, Python, Node.js, Go, etc.)
- Exception messages
- Error codes (HTTP 500, 404, connection errors)
- Database connection failures
- Memory/OOM errors
- Timeout errors
- Authentication/authorization failures
- Configuration errors

**Common Issues:**
- Application crashes
- Uncaught exceptions
- Resource exhaustion
- Network connectivity problems
- Missing environment variables
- Invalid configuration
- Dependency failures
- Health check failures

**Log Analysis Techniques:**
1. Group errors by type and frequency
2. Identify the timeline of errors (when did they start?)
3. Find correlation between events and errors
4. Detect patterns (e.g., errors every 30 seconds)
5. Extract relevant error messages and stack traces
6. Note any warnings that preceded errors

### Step 5: Check Resource Usage

If OOM or resource issues are suspected:

```bash
# Current resource usage
kubectl top pod <pod-name> -n <namespace>

# Resource requests and limits
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].resources}'
```

**Add to audit trail**: Document resource inspection commands

### Step 6: Generate Error Analysis Report

Create a comprehensive markdown report in the following structure:

## Report Structure

The report must be saved to `{{K8S_ANALYSES_DIR}}/<YYYY-MM-DD>-<namespace>-<pod-selector-sanitized>.md` (see "Report Storage" below).

The report MUST start with YAML frontmatter so it integrates with Obsidian / Dataview queries in `ops/_index.md`.

**IMPORTANT — wikilinks in frontmatter**: This vault does NOT put `[[wikilinks]]` inside YAML frontmatter. Obsidian's quoted form (`- "[[Foo]]"`) does not resolve as a link and unquoted form (`- [[Foo]]`) is invalid YAML. Keep the frontmatter as plain strings only, and put every wikilink in a dedicated `## Related` section at the **bottom of the body**.

```markdown
---
title: <namespace>/<pod-selector> pod failure analysis
created: <YYYY-MM-DD HH:mm>
source: k8s
cluster: <cluster-or-context>
env: <staging|prod|local|other>
namespace: <namespace>
project: <inferred-project>
resource: <pod-selector-or-resource>
severity: <info|warn|error|critical>
status: <open|mitigated|resolved|monitoring>
tags: [ops, k8s, triage]
---

# Kubernetes Error Analysis Report

**Namespace:** <namespace>
**Pod Selector:** <pod-selector>
**Analysis Date:** <timestamp>
**Analyst:** Claude

---

## Executive Summary

Brief overview of the primary issues found and their severity.

---

## Pod Status Overview

| Pod Name | Status | Restarts | Age | Node | Ready |
|----------|--------|----------|-----|------|-------|
| ...      | ...    | ...      | ... | ...  | ...   |

**Key Observations:**
- Highlight any pods in error states
- Note high restart counts
- Identify any pods that never reached ready state

---

## Critical Errors

### Error #1: [Error Type/Title]

**Severity:** Critical/High/Medium/Low
**Frequency:** X occurrences
**First Seen:** <timestamp>
**Last Seen:** <timestamp>
**Affected Pods:** pod-1, pod-2

**Error Message:**
```
[Relevant error message or stack trace]
```

**Root Cause Analysis:**
[Detailed explanation of what's causing this error]

**Impact:**
[How this error affects the application]

**Recommended Fix:**
[Step-by-step remediation steps]

---

### Error #2: [Next Error Type]

[Same structure as above]

---

## Warnings and Secondary Issues

### Warning #1: [Description]

**Details:**
[Explanation of the warning and potential future impact]

---

## Timeline Analysis

Chronological view of significant events:

- `HH:MM:SS` - Pod started
- `HH:MM:SS` - First error appeared: [brief description]
- `HH:MM:SS` - Pod restarted
- `HH:MM:SS` - New error pattern emerged: [brief description]

---

## Resource Analysis

**CPU Usage:**
- Current: X millicores
- Requested: Y millicores
- Limit: Z millicores
- Assessment: [Within limits / Approaching limit / Exceeding limit]

**Memory Usage:**
- Current: X Mi
- Requested: Y Mi
- Limit: Z Mi
- Assessment: [Within limits / Approaching limit / OOMKilled detected]

**Observations:**
[Any resource-related insights]

---

## Configuration Issues

List any configuration problems detected:
- Missing environment variables
- Invalid configuration values
- Incorrect secret/configmap references
- Volume mount issues

---

## Network and Connectivity Issues

List any network-related problems:
- DNS resolution failures
- Connection timeouts to external services
- Service discovery issues
- Certificate/TLS errors

---

## Recommendations

### Immediate Actions (Priority 1)
1. [Action item with specific command or change needed]
2. [Action item]

### Short-term Improvements (Priority 2)
1. [Suggestion for improving stability]
2. [Suggestion]

### Long-term Considerations (Priority 3)
1. [Architectural or design considerations]
2. [Monitoring and alerting improvements]

---

## Command Audit Trail

This section documents all Kubernetes commands executed during the analysis for reproducibility and audit purposes.

| # | Timestamp | Command | Purpose |
|---|-----------|---------|---------|
| 1 | HH:MM:SS | `kubectl get pods -n <namespace> -l <label> -o wide` | Retrieve initial pod status and information |
| 2 | HH:MM:SS | `kubectl describe pod <pod-name> -n <namespace>` | Get detailed pod events and configuration |
| 3 | HH:MM:SS | `kubectl logs <pod-name> -n <namespace> --tail=500 --timestamps` | Retrieve recent pod logs |
| 4 | HH:MM:SS | `kubectl logs <pod-name> -n <namespace> --previous --tail=500` | Check logs from previous container instance |
| 5 | HH:MM:SS | `kubectl top pod <pod-name> -n <namespace>` | Check current resource usage |
| ... | ... | ... | ... |

**Total Commands Executed:** X

**Commands by Category:**
- Pod Information: X commands
- Events & Describe: X commands
- Log Retrieval: X commands
- Resource Inspection: X commands

**Reproducibility:** All commands above can be re-run to reproduce this analysis.

---

## Related Logs

### Pod: <pod-name-1>

**Recent Logs (last 50 lines):**
```
[Most relevant log lines]
```

### Pod: <pod-name-2>

**Recent Logs (last 50 lines):**
```
[Most relevant log lines]
```

---

## Kubernetes Events

```
[Relevant events from kubectl describe]
```

---

## Appendix: Full Log Excerpts

[Include full logs or larger excerpts if needed for reference]

---

## Learning Points

**What went wrong:**
[Summary of the failure]

**Why it happened:**
[Technical explanation]

**How to prevent in future:**
[Preventive measures, monitoring, testing recommendations]

---

## Related

Every report MUST end with this section. Use unquoted body-wikilinks (these render correctly in Obsidian; do NOT put them in frontmatter):

- [[Kubernetes]]
- [[Observability]]
- [[<relevant project MOC if any, e.g. Data AI Agents>]]

---

**Report Generated by:** Claude K8s Error Analyzer
**Timestamp:** <ISO-8601 timestamp>
```

## Report Storage

All reports must be saved to the configured analyses directory. The default (injected at install time) is:

```
{{K8S_ANALYSES_DIR}}
```

This usually points at the `ops/k8s/` folder inside the user's Obsidian vault so reports become first-class notes. If the placeholder was not replaced at install time (i.e. Obsidian was not configured), fall back to `./docs/error_analyses/` relative to the current working directory and warn the user.

Filename format (date-first so Obsidian/Finder sort chronologically):

```
<YYYY-MM-DD>-<namespace>-<pod-selector-sanitized>.md
```

If multiple analyses are generated the same day, append time:

```
<YYYY-MM-DD>-<HHMM>-<namespace>-<pod-selector-sanitized>.md
```

Examples:
- `2026-04-20-payments-staging-checkout-web.md`
- `2026-04-20-1803-payments-staging-checkout-web.md`

Create the directory if it doesn't exist:
```bash
mkdir -p "{{K8S_ANALYSES_DIR}}"
```

## Best Practices

1. **Maintain Command Audit Trail**: Track every kubectl command executed during analysis with timestamp and purpose
2. **Be Thorough**: Analyze all pods matching the selector, not just one
3. **Look for Patterns**: Multiple pods with the same error indicate a systemic issue
4. **Check Previous Logs**: If a pod restarted, check `--previous` logs for the crash
5. **Consider Context**: Events often explain log errors
6. **Prioritize Issues**: Focus on critical errors that prevent pod startup or cause crashes
7. **Provide Actionable Fixes**: Don't just identify problems, suggest concrete solutions
8. **Include Evidence**: Show the actual error messages and logs
9. **Think Like an SRE**: Consider observability, monitoring, and prevention
10. **Document Everything**: The audit trail enables others to reproduce your analysis

## Error Classification

Classify errors by type:

- **Container Issues**: Image pull failures, entrypoint errors, missing dependencies
- **Application Errors**: Code exceptions, logic errors, unhandled errors
- **Resource Issues**: OOMKilled, CPU throttling, disk pressure
- **Configuration Issues**: Missing env vars, bad config values, secret not found
- **Network Issues**: DNS failures, connection timeouts, TLS errors
- **Health Check Failures**: Liveness/readiness probe failures
- **Dependency Issues**: Database connection failures, external API errors

## Common Kubernetes Error Patterns

Be aware of these common patterns:

1. **CrashLoopBackOff**: Container crashes immediately after starting
   - Check logs with `--previous` flag
   - Look for application startup errors

2. **ImagePullBackOff**: Cannot pull container image
   - Check image name and tag
   - Verify registry credentials
   - Check network connectivity to registry

3. **OOMKilled**: Container killed due to memory limit
   - Increase memory limits
   - Investigate memory leaks
   - Optimize application memory usage

4. **Pending**: Pod cannot be scheduled
   - Check resource requests vs node capacity
   - Look for node selectors or affinity rules
   - Check for PV binding issues

5. **Error / Failed**: Generic error state
   - Check events for specific reason
   - Review container logs for details

## Example Usage

User: "Analyze the failures in the api-server pods in the production namespace"

Response flow:
1. Confirm inputs: namespace=production, selector=api-server
2. Run kubectl commands to gather pod info
3. Collect logs from all api-server pods
4. Check events and resource usage
5. Analyze logs for error patterns
6. Generate comprehensive report (with YAML frontmatter)
7. Save to `{{K8S_ANALYSES_DIR}}/<YYYY-MM-DD>-production-api-server.md`
8. Present report to user and suggest promotion (triage → runbook → incident) if the issue warrants it

## Handling Edge Cases

- **No logs available**: Report this clearly and check if pod even started
- **Too many logs**: Focus on recent logs (last 1000 lines) and summarize
- **Multiple containers**: Analyze each container separately
- **Init containers**: Check init container logs if pod stuck in Init state
- **Sidecar containers**: Don't ignore sidecar logs (often service mesh issues)

## Final Output

After completing the analysis:

1. Create the markdown report
2. Save it to the error_analyses directory
3. Use the `present_files` tool to share the report with the user
4. Provide a brief verbal summary of key findings
5. Highlight the most critical issues requiring immediate attention

## Dependencies

Required:
- kubectl CLI tool
- Access to Kubernetes cluster (configured kubeconfig)
- Appropriate RBAC permissions to read pods and logs

Optional:
- jq (for JSON parsing)
- grep, awk, sed (for log analysis)

## Notes

- Always handle sensitive data appropriately (redact secrets, credentials)
- Be aware that log volumes can be large - use `--tail` to limit output
- Some errors may be transient - note if errors are ongoing vs historical
- Cross-reference pod events with log timestamps for complete picture
- Consider suggesting logging improvements if logs are insufficient
