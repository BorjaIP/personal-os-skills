---
name: meeting-notes-enhance
description: Enhance raw Obsidian meeting notes with AI — transforms sparse bullet points into a structured note with Summary, Decisions, Action Items, Open Questions, and preserves Raw Notes verbatim. Optionally incorporates a Whisper transcription from the paired file. Use when the user says "enhance my meeting notes", "structure this meeting", or invokes the skill on a .md file in meetings/notes/.
---

# Meeting Notes Enhance

Turns sparse bullet-point meeting notes (optionally combined with a Whisper transcript) into a clean, structured Obsidian note. The enhancement runs in-place: the original file is overwritten with the structured version, preserving all YAML frontmatter.

## When to Use

Apply this skill when **any** of the following is true:

1. The user asks to "enhance", "structure", or "clean up" meeting notes.
2. A `.md` file under `meetings/notes/` has been provided and contains freeform notes.
3. The user just stopped a recording (`meet-stop`) and the note was auto-created with raw content.
4. The user explicitly invokes `meeting-notes-enhance` with a file path.

## Inputs

Collect from the user or infer from context:

1. **Note path** (required): path to the `.md` meeting note to enhance. Typically `{{OBSIDIAN_VAULT}}/meetings/notes/YYYY-MM-DD-slug.md`.
2. **Transcription path** (optional, auto-detected): path to the paired transcription `.md` at `{{OBSIDIAN_VAULT}}/meetings/transcriptions/YYYY-MM-DD-slug.md`. If the note contains a wikilink like `[[meetings/transcriptions/YYYY-MM-DD-slug]]`, derive the transcription path from it.

If the note path is not provided and the user has not specified a file, ask for it.

## Workflow

### Step 1 — Read the note

Read the note file in full. Identify:
- **YAML frontmatter** (between `---` delimiters at the top) — must be preserved exactly, character-for-character.
- **Body** — everything after the closing `---`. This is the raw input.

Check if the body already has the enhanced sections (`## Summary`, `## Decisions`, `## Action Items`, `## Open Questions`, `## Raw Notes`). If all five sections are present, warn the user and ask whether to re-enhance or abort.

### Step 2 — Read the transcription (if available)

Check whether `{{OBSIDIAN_VAULT}}/meetings/transcriptions/YYYY-MM-DD-slug.md` exists (derive the slug from the note filename). If it exists, read it in full.

If the note body contains a wikilink `[[meetings/transcriptions/...]]`, use that to locate the transcription.

### Step 3 — Produce the structured output

Using the raw notes and (optionally) the transcription text, produce a structured markdown document with exactly these sections in this order:

---

**Section order and rules:**

#### `## Summary`
2–4 sentences capturing the meeting's purpose, key discussion points, and outcome. Be concrete — mention names, systems, or projects if present. Do not invent information not in the notes or transcript.

#### `## Decisions`
Bullet list of firm decisions made during the meeting. Each bullet starts with the decision in the past tense.
- If no decisions are recorded, write: `None recorded.`

#### `## Action Items`
Bullet list of tasks that need to be done after the meeting. Format each as:
```
- [ ] <action verb> <specific task> — <owner if mentioned>
```
Use `— @name` if an owner is named, omit if unknown.
- If none, write: `None recorded.`

#### `## Open Questions`
Bullet list of unresolved questions, deferred topics, or things that need follow-up. These are things NOT decided.
- If none, write: `None.`

#### `## Raw Notes`
The original body content verbatim, unchanged. Copy it exactly as it appeared in the input — do not edit, reformat, or summarize. This is the source of truth.

---

**Language rule:** Write in English unless the original notes are in another language, in which case match that language throughout all sections.

**Accuracy rule:** Never invent information not present in the notes or transcript. If the transcript fills in a name or detail that the notes omit, you may use it. If neither source has it, leave it out.

**Wikilinks rule:** Do not modify or remove any `[[wikilinks]]` present in the raw notes — they must appear verbatim in the `## Raw Notes` section.

### Step 4 — Write the enhanced note

Reconstruct the file as: original YAML frontmatter + newline + structured content.

The final file format:
```
---
<original frontmatter unchanged>
---

## Summary
...

## Decisions
...

## Action Items
...

## Open Questions
...

## Raw Notes
<original body verbatim>
```

Overwrite the original note file with this content.

### Step 5 — Report to the user

Output:
- Confirmation that the note was enhanced and the path where it was saved.
- A one-line summary of what was found (e.g. "3 action items, 1 decision, 2 open questions").
- If the note was already enhanced, mention that it was re-enhanced.

## Example

**Input note** (`meetings/notes/2026-04-27-standup.md`):
```markdown
---
date: 2026-04-27
attendees: [borja, alice, rob]
tags: [meeting]
project: infra
---

[[meetings/transcriptions/2026-04-27-standup]]

Discussed k8s cost spike. Rob will check PerfectScale. Alice to open ticket for node pool review. Still unclear if staging is affected.
```

**Output** (same file, overwritten):
```markdown
---
date: 2026-04-27
attendees: [borja, alice, rob]
tags: [meeting]
project: infra
---

[[meetings/transcriptions/2026-04-27-standup]]

## Summary

The standup focused on an unexpected cost spike in the k8s cluster. Rob will investigate whether PerfectScale is over-shrinking node pools, and Alice will open a ticket to review the node pool configuration. Staging impact remains unclear.

## Decisions

- Rob owns the PerfectScale investigation before the next standup.
- A ticket will be opened for node pool review.

## Action Items

- [ ] Investigate PerfectScale cost impact on k8s cluster — @rob
- [ ] Open ticket for node pool review — @alice

## Open Questions

- Is the cost spike also present in the staging environment?

## Raw Notes

[[meetings/transcriptions/2026-04-27-standup]]

Discussed k8s cost spike. Rob will check PerfectScale. Alice to open ticket for node pool review. Still unclear if staging is affected.
```

## Anti-Patterns

- ❌ Modifying the YAML frontmatter in any way.
- ❌ Inventing action items, decisions, or owners not mentioned in the source material.
- ❌ Omitting the `## Raw Notes` section — it must always be present.
- ❌ Putting `[[wikilinks]]` in frontmatter — they belong in the body only.
- ❌ Re-summarizing the transcript verbatim — extract meaning, not words.
- ❌ Skipping the transcription if it exists and was auto-detected — always incorporate it.
