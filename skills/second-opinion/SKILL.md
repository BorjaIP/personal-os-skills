---
name: second-opinion
description: >
  Independent second opinion on work done by another agent. Reviews local changes (git diff),
  commit ranges, or Pull Requests to detect bugs, misalignment with the original goal, and
  CLAUDE.md violations. Can invoke the Claude Code /code-review command as a sub-agent (for PRs)
  and generates a correction plan if findings warrant it. Use when an agent just made changes
  and you want to validate them before continuing: "review what the agent did", "second opinion
  on these commits", "validate agent work", "review agent changes", /second-opinion.
---

# Agent Reviewer

Independent QA layer over agent-produced work. Spawns parallel review sub-agents to audit
changes across four dimensions, scores findings, and optionally enters Plan Mode to produce
a correction plan.

## When to Use

Trigger when the user asks any of:

- "Review what the agent just did"
- "Second opinion on these commits / this PR"
- "Validate the agent's work before I merge"
- "Check if agent changes are correct"
- "Did the agent do what I asked?"

Do **NOT** use this skill when:

- The user wants a standard PR review without agent context → call `/code-review` directly.
- The user wants to execute or plan new work → use `mdn-run` or `mdn-plan`.

## Inputs

Gather from context or ask one clarifying question:

1. **scope** (required, infer from context):
   - `local` — no scope given; auto-detect via `git status` + `git diff HEAD`.
   - `commits:<sha1>..<sha2>` — user specifies a commit range.
   - `pr:<number>` — user provides a Pull Request number.
2. **intent** (required): what the agent was supposed to do. If not stated, ask before proceeding.
3. **create_plan** (`yes` / `no` / `ask`, default `ask`): whether to enter Plan Mode if significant issues are found.

---

## Step 0 — Detect Scope and Load Context

1. If the user passed `pr:<N>` → scope = PR.
2. If a commit range is mentioned → scope = commits.
3. Otherwise → run `git status` and `git diff HEAD`; scope = local.
4. Read the root `CLAUDE.md` (if it exists) for compliance checks in Step 2.
5. Restate scope and intent to the user before proceeding (cheap sanity check).

---

## Step 1 — Collect the Diff

Depending on scope:

- **PR**: `gh pr diff <N>` + `gh pr view <N>` (title, description, body, changed files).
- **Commits**: `git log <range> --oneline` + `git diff <range>` + commit messages.
- **Local**: `git diff HEAD` (staged + unstaged) + `git status`.

Extract and store: list of changed files, full diff, associated commit messages.

---

## Step 2 — Parallel Multi-Agent Review

Launch **4 Sonnet agents in parallel** (single message, 4 Agent tool calls):

| Agent | Focus |
|---|---|
| #1 — Intent Alignment | Does the change do what the stated intent asked? Is anything missing or added beyond scope? |
| #2 — Bug Scan | Shallow scan for obvious bugs in the diff. Skip pre-existing issues and pedantic nitpicks. |
| #3 — CLAUDE.md Compliance | Does the code follow the instructions in the relevant CLAUDE.md files? |
| #4 — Historical Context | Run `git blame` on modified files; flag conflicts with prior invariants or recent related changes. |

Each agent returns a list of findings with: description, estimated severity (low / medium / high), and justification.

**False positive guidelines for all agents** (identical to the built-in code-review plugin):
- Pre-existing issues not touched by this diff.
- Something that looks like a bug but is not.
- Pedantic nitpicks a senior engineer would not call out.
- Issues a linter or type-checker would catch — assume CI handles those.
- General quality concerns (test coverage, documentation) unless CLAUDE.md explicitly requires them.

---

## Step 3 — Score Findings

For each finding from Step 2, launch a **parallel Haiku agent** that scores it 0–100 (give this rubric verbatim):

- **0**: False positive. Does not survive light scrutiny or is a pre-existing issue.
- **25**: Possible issue, unverified. May be a false positive.
- **50**: Real issue, but minor or unlikely to be hit in practice.
- **75**: Important issue, well-verified, likely to occur in practice.
- **100**: Critical and confirmed. Will definitely occur frequently.

Filter out findings with score < 75. If no findings remain, the agent work is clean — report that and stop.

---

## Step 4 — Optional: Invoke `/code-review` as Sub-Agent (PR scope only)

If scope = PR **and** `create_plan != no`:

1. Launch an agent that runs the built-in `code-review` command on the PR.
2. Merge its findings into the consolidated report, labelled `[code-review]` as source.
3. Apply the same ≥ 75 filter before merging.

This step is **additive** — it supplements Steps 2–3, does not replace them.

---

## Step 5 — Consolidate and Report

Generate a Markdown report in the conversation:

```
## Agent Review — <scope>

### Intent
<what the agent was supposed to do>

### Verdict
✓ Aligned | ⚠ Minor issues | ✗ Significant issues

### Findings (<N> issues)

1. [HIGH] <brief description> — score: 85
   File: path/to/file.py:42
   Reason: <justification>

2. [MEDIUM] <brief description> — score: 77
   File: path/to/other.ts:10
   Reason: <justification>

### Clean Dimensions
- Intent alignment ✓  (or listed here if no issues found for that agent)
- CLAUDE.md compliance ✓

### Recommendation
<free text: merge / fix before merge / requires correction plan>
```

Rules:
- Keep descriptions brief. Link to file and line for every finding.
- Do not emit emojis beyond the verdict line.
- If zero findings survive the filter, report "No issues found" and stop.

---

## Step 6 — Correction Plan (Conditional)

If findings with score ≥ 75 exist:

- **`create_plan=yes`** — Enter Plan Mode automatically (`EnterPlanMode`) with findings as requirements context.
- **`create_plan=ask`** — Ask the user: "Do you want me to generate a correction plan for these findings?" Proceed only on explicit confirmation.
- **`create_plan=no`** — Skip.

The correction plan uses the findings as requirements and follows the standard Claude Code plan structure. Reference the specific files and line numbers from the findings.

---

## Hard Constraints

- **Read-only against git and GitHub** — never commit, push, or merge as part of this review.
- **No fabricated findings** — if an agent finds nothing, record "no issues" and continue. Do not invent issues to fill the report.
- **No build steps** — do not run tests, linters, or type-checkers. Assume CI handles those.
- **Cite everything** — every finding must include a file path and line reference.
