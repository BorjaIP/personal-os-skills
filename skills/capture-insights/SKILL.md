---
name: capture-insights
description: Extract engineering insights from the current conversation and persist them to the Obsidian PKM vault at {{OBSIDIAN_VAULT}}/private/. Use when the user says "capture", "save this to obsidian", "remember this in my vault", or invokes /capture. Identifies technical knowledge (infra, CI/CD, debugging, architecture, patterns) and writes it to existing or new topic notes following the vault's conventions.
---

# Capture Insights to Obsidian PKM

Extracts actionable engineering knowledge from the current Claude Code conversation and persists it to topic-based notes in the Obsidian vault at `{{OBSIDIAN_VAULT}}/private/`.

## When to Use

Apply this skill when the user explicitly asks to capture, save, or persist insights from the conversation to their knowledge base. This is **manual-only** — never auto-trigger.

## What Counts as an Insight

Capture **durable engineering and data knowledge** — things that help understand how systems are built, why decisions were made, and how things work. Focus on:

- **Architecture and design**: how repos connect, deployment flows, service dependencies, system boundaries
- **Technical decisions and rationale**: why something was built a certain way, trade-offs considered, constraints that drove choices
- **Bugs with root cause analysis**: errors encountered, why they happen, what the underlying cause is (not just "we fixed it")
- **Pipeline and CI/CD structure**: how builds work, what stages exist, how deployments flow between repos
- **Data engineering patterns**: how data flows, CDC setup, warehouse loading strategies, scheduling
- **Functional requirements**: what a system does, what its inputs/outputs are, who uses it and why

**Skip — do NOT capture**:
- Service URLs, endpoints, or dashboard links (they change and belong in config, not knowledge)
- Tool installation steps, CLI setup, local dev environment config
- Conversation-specific actions (e.g., "we relaunched build #42")
- Wrapper scripts, browser extensions, personal tooling setup
- Things already documented in the vault
- Ephemeral conversation flow, greetings, troubleshooting steps that only apply once

## Workflow

### Step 1 — Extract insights from the conversation

Review the full conversation and extract discrete insights. For each one, note:
- **Topic**: the primary subject (e.g., "CI Pipeline", "Payment Gateway", "Kubernetes", "Datadog")
- **Content**: the actual knowledge to persist
- **Scope**: is it general (org/team-wide) or project-specific (e.g., my-api)?

### Step 2 — Discover existing notes

List all `.md` files in `{{OBSIDIAN_VAULT}}/private/` recursively using Glob (`**/*.md`). The vault is organized in category folders:

```
private/
├── business/    ← Business domain, KPIs, commercial frameworks
├── tools/       ← Tech stack (databases, orchestrators, monitoring, etc.)
├── projects/    ← Repos and products owned by the team
├── infra/       ← CI/CD, ops, on-call, deploy
├── reference/   ← Onboarding, queries, meeting notes
├── _index.md    ← MOC (Map of Content) — update when creating new notes
└── Tasks.md     ← Managed by /tasks skill, do not touch
```

For each insight, decide:
- **Match found** → append to the existing note under the right section
- **No match** → propose creating a new note in the correct category folder (e.g., `infra/CI Pipeline.md`)

**Category rules** for new notes:
- Business domain knowledge → `business/`
- A specific tool in the stack → `tools/`
- A repo or product → `projects/`
- CI/CD, deployment, ops, monitoring setup → `infra/`
- Everything else → `reference/`

### Step 3 — Present the capture plan to the user

Before writing anything, show a structured summary. Example:

```
Insights extracted from this conversation:

1. infra/CI Pipeline.md (NEW)
   - Monorepo builds 5 services in parallel, each with change detection
   - Known bug: serialization error on large merges
   - Deploy stage skips when any parallel stage fails

2. projects/Payment Gateway.md (APPEND)
   - Service boundary: handles checkout, refunds, webhook processing
   - Depends on events from order-service via message queue

Proceed? (confirm / edit / discard)
```

Use `AskUserQuestion` to get confirmation. The user may edit, remove items, or add context.

### Step 4 — Write to the vault

For each confirmed insight:

#### Appending to an existing note

1. Read the full note file.
2. Find the most relevant section (`##` header). If the insight is project-specific, look for a `## project-name` section.
3. If the section exists, append the content at the end of that section (before the next `##` or end of file).
4. If no matching section exists, create a new `## Section Name` at the end of the note (before any trailing whitespace).
5. Write the updated file, preserving YAML frontmatter exactly.

#### Creating a new note

Create the file at `{{OBSIDIAN_VAULT}}/private/<category>/<Topic Name>.md` (choosing the right category folder) with this structure:

```markdown
---
title: <Topic Name>
created: <current date in "dddd Do MMMM YYYY HH:mm" format, e.g., "Thursday 22nd May 2026 13:05">
aliases: 
tags: 
---

# <Topic Name>

## General
<insights that apply to the org/team broadly>

## <project-name>
<insights specific to a project, e.g., my-api>

### <subtopic>
<more granular info if needed>
```

Only include sections that have content. Do not create empty sections.

After creating a new note, update `{{OBSIDIAN_VAULT}}/private/_index.md` to add a link under the corresponding category section.

#### Content formatting rules

- Add a date comment at the start of each captured block: `<!-- captured: YYYY-MM-DD -->`
- Use bullet points for discrete facts
- Use code blocks (``` ```) for commands, SQL, config snippets, error messages
- Use `[[wikilinks]]` to link to other notes in the vault when referencing related topics (e.g., `[[Kubernetes]]`, `[[PostgreSQL]]`)
- Write in the same language the user used in the conversation (Spanish or English)
- Be concise — these are reference notes, not narratives

### Step 5 — Report results

After writing, confirm:
- Which notes were created or updated
- How many insights were captured
- One-line summary per note of what was added

## Note Organization — Hierarchy Within Notes

Each note in `private/` is a **topic hub**. Inside, organize by scope:

```
# Topic Name                         <- H1: the topic itself

## General                           <- Org/team-wide knowledge
- ...

## <project-name>                    <- Project-specific section
### <subtopic>                       <- Granular breakdown
- ...
### Known bugs                       <- Known issues for this project
- ...

## <another-project>
- ...
```

This way a note like `CI Pipeline.md` can hold:
- General CI patterns for all repos under `## General`
- Specific pipeline details under `## my-api`, `## my-frontend`, etc.

## Anti-Patterns

- Never write without user confirmation first.
- Never modify YAML frontmatter of existing notes.
- Never delete or overwrite existing content — only append.
- Never capture ephemeral info (tool installation steps, conversation logistics).
- Never create duplicate notes — always check existing files first.
- Never add module-level docstrings or emoji to the captured content.
- Never invent information not discussed in the conversation.

## Example

**Conversation context**: User debugged a CI build failure in a monorepo. The error was a `NotSerializableException` in one of the parallel build stages, caused by large merge changesets. The deploy stage was skipped because the CI system stops on first failure.

**Capture output** → New file `{{OBSIDIAN_VAULT}}/private/infra/CI Pipeline.md`:

```markdown
---
title: CI Pipeline
created: Thursday 22nd May 2026 13:05
aliases: 
tags: 
---

# CI Pipeline

## General
<!-- captured: 2026-05-22 -->
- When a parallel stage fails, the CI marks the build as Failed and **does not execute subsequent stages** (like Deploy), even if other parallel stages succeeded
- Rerun from the UI relaunches the entire build, not just the failed stage

## my-api
<!-- captured: 2026-05-22 -->
### Pipeline stages
- Parallel build of 5 services, each with its own `has*RelevantChanges()` function that uses `git diff` to decide whether to build
- Docker images are tagged as `<service-name>-<short-commit>` and pushed to the container registry
- Deploy stage writes the image tag to the [[Helm Charts]] repo for the CD system to pick up

### Known bugs
- `NotSerializableException` on the changeset object — happens when a merge brings many changesets (14+). It is a bug in the CI plugin's state serialization, not in the pipeline definition. Intermittent: rerunning usually works. Permanent fix: update the CI plugins
```
