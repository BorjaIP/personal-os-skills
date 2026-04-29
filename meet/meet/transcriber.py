"""mlx-whisper transcription wrapper."""

from __future__ import annotations

from pathlib import Path

# Default model: small enough to be fast on Apple Silicon, good enough for meetings.
# Swap for "mlx-community/whisper-large-v3-turbo" if accuracy is more important than speed.
DEFAULT_MODEL = "mlx-community/whisper-small"


def transcribe(wav_path: Path, model: str = DEFAULT_MODEL) -> str:
    """Transcribe a WAV file using mlx-whisper. Returns the full transcript text."""
    try:
        import mlx_whisper  # type: ignore[import-untyped]
    except ImportError as exc:
        raise RuntimeError(
            "mlx-whisper is not installed. Run: uv pip install mlx-whisper"
        ) from exc

    result = mlx_whisper.transcribe(str(wav_path), path_or_hf_repo=model)
    return result["text"].strip()
