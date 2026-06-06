---
name: run
description: Wrapper for your own prompts. Resolves the current local project to its matching Meridian project in the Obsidian PKM vault ({{OBSIDIAN_VAULT}}/meridian/<slug>/PROMPTS.md), reads the latest active prompt you wrote there, and executes it in the current session as if you had typed it in chat. Use when the user says "run", "ejecuta mi prompt", "run my prompt", or invokes /run.
---

# Run — execute my own prompt from the PKM

This skill lets you drive a session by writing in your Obsidian PKM instead of the
chat box. You keep a `PROMPTS.md` file inside each Meridian project; `run` finds the
one matching the current repo, reads the **latest active prompt**, and executes it in
the current session exactly as if you had typed it. After running, it strikes the
prompt through so the file becomes a conversational history.

## When to Use

Trigger when the user says `run`, `/run`, "ejecuta mi prompt", "run my prompt", or
similar. This is **manual-only**.

This is a different skill from `mdn-run` (Meridian task execution). `run` does not
touch tasks or plans — it only reads/executes free-form prompts from `PROMPTS.md`.

## PROMPTS.md format

Path: `{{OBSIDIAN_VAULT}}/meridian/<slug>/PROMPTS.md`

Each prompt is a `## <title>` section. The section **body** is the full prompt
(multi-line, code, anything). New prompts are appended at the **bottom**.

```markdown
---
project: data-charts
type: prompts
---

# PROMPTS - data-charts

> Write a new prompt as a `## <title>` section at the bottom.
> `run` executes the last ACTIVE section (no `<!-- run: -->` marker) and then strikes it.

## fix the date parser
Your full prompt here...
multiple lines, code, whatever.
```

- **Active prompt** = the last (bottom-most) `##` section whose heading does NOT
  contain a `<!-- run: ... -->` marker.
- An executed prompt's heading looks like:
  `## ~~fix the date parser~~ <!-- run: 2026-06-05 11:44 -->`
  The `<!-- run: -->` marker is the source of truth for "already executed"; the
  `~~...~~` strikethrough is for visual history.

## Workflow

### Step 0 — Resolve the vault and project slug

1. The vault is `{{OBSIDIAN_VAULT}}` (substituted at install time).
2. Determine the current project: take the **basename of the current workspace /
   working directory** (e.g. `/Users/me/projects/data-charts` -> `data-charts`).
   This basename is the `<slug>`. Match is **exact**.

### Step 1 — Locate the Meridian project

Check that `{{OBSIDIAN_VAULT}}/meridian/<slug>/` exists.

- If it does **not** exist -> **stop with an error**:
  ```
  No Meridian project found for "<slug>".
  Create it first, e.g.  /mdn-init name:<slug>
  ```
  Do nothing else.

### Step 2 — Locate PROMPTS.md

Look for `{{OBSIDIAN_VAULT}}/meridian/<slug>/PROMPTS.md`.

- If the project folder exists but `PROMPTS.md` is **missing**, create it from the
  template below, then tell the user "Created PROMPTS.md for `<slug>` — write your
  first prompt as a `## <title>` section and run again." and **stop**.

Template:
```markdown
---
project: <slug>
type: prompts
---

# PROMPTS - <slug>

> Write a new prompt as a `## <title>` section at the bottom.
> `run` executes the last ACTIVE section (no `<!-- run: -->` marker) and then strikes it.
```

### Step 3 — Extract the active prompt

Read `PROMPTS.md`. Find the **last** `##` section whose heading line does NOT contain
`<!-- run:`. That section's body (everything between its heading and the next `##`
heading or end of file, excluding the frontmatter and the `#` title) is the prompt.

- If there is no active section -> tell the user "No pending prompts in `<slug>`."
  and **stop**.

### Step 4 — Execute

Treat the extracted body as a **new user instruction** and execute it directly in the
current session, with full access to the current context, exactly as if the user had
typed it in chat. Do not summarize it back first — just do it.

### Step 5 — Strike through / history

After execution, edit `PROMPTS.md` so the executed section's heading becomes:

```
## ~~<original title>~~ <!-- run: YYYY-MM-DD HH:MM -->
```

Use the current local date/time. Leave the section **body untouched** so the prompt
stays readable in history. Write the file back, preserving frontmatter and all other
sections exactly.

### Step 6 — Confirm

Report a one-line summary: which prompt was executed (its title) and what it did.

## Anti-Patterns

- Never guess the slug from anything other than the current directory basename.
- Never auto-create the Meridian project folder — error out instead (Step 1).
- Never execute a section that already has a `<!-- run: -->` marker.
- Never modify, reorder, or delete other sections or the frontmatter.
- Never strip or rewrite the prompt body when striking it through.
