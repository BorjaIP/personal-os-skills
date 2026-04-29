"""meet — meeting recording and note creation CLI."""

from __future__ import annotations

import re
from pathlib import Path

import typer

app = typer.Typer(
    name="meet",
    help="Record meetings, transcribe audio, and create Obsidian notes.",
    add_completion=False,
    no_args_is_help=True,
)


@app.callback()
def _root() -> None:
    """meet — meeting recording and note creation CLI."""


# ---------------------------------------------------------------------------
# meet start
# ---------------------------------------------------------------------------

@app.command("start")
def cmd_start(
    slug: str = typer.Argument(
        ...,
        help="Short slug for the meeting, e.g. 'standup' or 'design-review'",
    ),
) -> None:
    """Start recording audio for a meeting. Creates a timestamped WAV file."""
    from meet.recorder import start  # lazy import — sox not required to import the module

    slug = re.sub(r"[^a-z0-9-]", "-", slug.lower()).strip("-")
    if not slug:
        typer.echo("Error: slug must contain at least one alphanumeric character.", err=True)
        raise typer.Exit(1)

    try:
        state = start(slug)
    except RuntimeError as exc:
        typer.echo(f"Error: {exc}", err=True)
        raise typer.Exit(1)

    typer.echo(f"Recording started  →  {state['name']}")
    typer.echo(f"WAV file           →  {state['wav_path']}")
    typer.echo(f"PID                →  {state['pid']}")
    typer.echo("\nTake notes in Obsidian. Run `meet stop` when the meeting ends.")


# ---------------------------------------------------------------------------
# meet stop
# ---------------------------------------------------------------------------

@app.command("stop")
def cmd_stop(
    model: str = typer.Option(
        "mlx-community/whisper-small",
        "--model",
        "-m",
        help="Whisper model repo (e.g. mlx-community/whisper-large-v3-turbo)",
    ),
    skip_transcription: bool = typer.Option(
        False,
        "--no-transcribe",
        help="Stop recording without running Whisper transcription",
    ),
) -> None:
    """Stop the active recording, transcribe audio, and create Obsidian notes."""
    from meet import recorder, transcriber, note_creator

    try:
        state = recorder.stop()
    except RuntimeError as exc:
        typer.echo(f"Error: {exc}", err=True)
        raise typer.Exit(1)

    name = state["name"]
    wav_path = Path(state["wav_path"])
    typer.echo(f"Recording stopped  →  {name}")

    transcript_text: str | None = None

    if not skip_transcription:
        if not wav_path.exists():
            typer.echo(f"Warning: WAV file not found at {wav_path}", err=True)
        else:
            typer.echo(f"Transcribing with {model} …")
            try:
                transcript_text = transcriber.transcribe(wav_path, model=model)
                typer.echo(f"Transcription done ({len(transcript_text)} chars)")
            except RuntimeError as exc:
                typer.echo(f"Warning: transcription failed — {exc}", err=True)
                typer.echo("Continuing without transcript.")

    # Create transcription note (even if empty, so the wikilink resolves)
    transcript_path = note_creator.create_transcription(
        name, transcript_text or "(no transcript — Whisper was skipped or failed)"
    )
    typer.echo(f"Transcript note    →  {transcript_path}")

    # Create meeting note stub
    note_path = note_creator.create_meeting_note(name, state["slug"])
    typer.echo(f"Meeting note       →  {note_path}")

    typer.echo(
        f"\nOpen {note_path.name} in Obsidian, add your notes, "
        "then ask Claude to run the `meeting-notes-enhance` skill."
    )


# ---------------------------------------------------------------------------
# meet status
# ---------------------------------------------------------------------------

@app.command("status")
def cmd_status() -> None:
    """Show whether a recording is active."""
    from meet.recorder import current_state

    state = current_state()
    if state is None:
        typer.echo("No active recording.")
    else:
        typer.echo(f"Recording active   →  {state['name']}")
        typer.echo(f"Started at         →  {state['started_at']}")
        typer.echo(f"WAV file           →  {state['wav_path']}")
        typer.echo(f"PID                →  {state['pid']}")


if __name__ == "__main__":
    app()
