"""Claude API integration for meeting note enhancement."""

import anthropic

SYSTEM_PROMPT = """\
You are an expert meeting facilitator and note-taker. Your job is to transform raw meeting notes \
(and optionally a transcript) into a clean, structured document.

Output ONLY the structured content — no preamble, no explanations, no markdown code fences.

Always produce exactly these sections in this order:

## Summary
2-4 sentences capturing the meeting's purpose and outcome.

## Decisions
Bullet list of decisions made. If none, write "None recorded."

## Action Items
Bullet list in the format: "- [ ] <action> — <owner if mentioned>"
If none, write "None recorded."

## Open Questions
Bullet list of unresolved questions or topics deferred. If none, write "None."

## Raw Notes
The original notes verbatim, unchanged.

Rules:
- Be concise and precise. Do not invent information not present in the notes.
- If a transcript is provided, use it to fill gaps and correct ambiguities in the raw notes.
- Preserve all original technical terms, names, and project names exactly.
- Write in English unless the original notes are in another language, in which case match that language.
"""


def enhance(raw_notes: str, transcript: str | None = None) -> str:
    """Call Claude to enhance meeting notes. Returns the structured markdown content."""
    client = anthropic.Anthropic()

    user_parts: list[str] = ["Here are the raw meeting notes:\n\n", raw_notes]

    if transcript:
        user_parts += [
            "\n\n---\n\nHere is the meeting transcript:\n\n",
            transcript,
        ]

    user_parts.append(
        "\n\n---\n\nPlease produce the structured meeting note now."
    )

    user_message = "".join(user_parts)

    result_chunks: list[str] = []

    with client.messages.stream(
        model="claude-opus-4-6",
        max_tokens=4096,
        system=[
            {
                "type": "text",
                "text": SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }
        ],
        messages=[{"role": "user", "content": user_message}],
    ) as stream:
        for text in stream.text_stream:
            print(text, end="", flush=True)
            result_chunks.append(text)

    print()  # newline after streaming
    return "".join(result_chunks)
