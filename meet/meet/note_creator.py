"""Create Obsidian meeting notes and transcription files."""

from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path


def _vault() -> Path:
    """Resolve the Obsidian vault path from env or default."""
    vault = os.environ.get("OBSIDIAN_VAULT", "")
    if vault:
        return Path(vault).expanduser()
    # Fallback: try the default location
    default = Path.home() / "pkm" / "pkm"
    if default.exists():
        return default
    raise RuntimeError(
        "Obsidian vault not found. Set the OBSIDIAN_VAULT environment variable "
        "or ensure ~/pkm/pkm exists."
    )


def create_transcription(name: str, transcript_text: str) -> Path:
    """Write the Whisper transcript to meetings/transcriptions/<name>.md."""
    vault = _vault()
    transcriptions_dir = vault / "meetings" / "transcriptions"
    transcriptions_dir.mkdir(parents=True, exist_ok=True)

    date_str = name[:10]  # YYYY-MM-DD prefix
    path = transcriptions_dir / f"{name}.md"
    path.write_text(
        f"---\ndate: {date_str}\ntags: [transcript]\n---\n\n{transcript_text}\n",
        encoding="utf-8",
    )
    return path


def create_meeting_note(name: str, slug: str) -> Path:
    """Create a stub meeting note in meetings/notes/<name>.md with wikilink to transcript."""
    vault = _vault()
    notes_dir = vault / "meetings" / "notes"
    notes_dir.mkdir(parents=True, exist_ok=True)

    date_str = name[:10]  # YYYY-MM-DD prefix
    path = notes_dir / f"{name}.md"

    # Build frontmatter + wikilink stub
    content = (
        f"---\n"
        f"date: {date_str}\n"
        f"attendees: []\n"
        f"tags: [meeting]\n"
        f"project: \n"
        f"---\n"
        f"\n"
        f"[[meetings/transcriptions/{name}]]\n"
        f"\n"
        f"## Notes\n"
        f"\n"
        f"<!-- Add your notes here during the meeting -->\n"
    )
    path.write_text(content, encoding="utf-8")
    return path
