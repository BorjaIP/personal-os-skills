"""sox-based audio recorder with PID-file state management."""

from __future__ import annotations

import json
import subprocess
from datetime import datetime
from pathlib import Path

_STATE_FILE = Path.home() / ".meet" / "current.json"
_RECORDINGS_DIR = Path.home() / ".meet" / "recordings"


def _state_path() -> Path:
    return _STATE_FILE


def is_recording() -> bool:
    return _STATE_FILE.exists()


def current_state() -> dict | None:
    if not _STATE_FILE.exists():
        return None
    return json.loads(_STATE_FILE.read_text())


def start(slug: str) -> dict:
    """Start sox recording. Returns state dict. Raises RuntimeError if already recording."""
    if is_recording():
        state = current_state()
        raise RuntimeError(
            f"Already recording '{state['name']}' (PID {state['pid']}). "
            "Run `meet stop` first."
        )

    date_str = datetime.now().strftime("%Y-%m-%d")
    name = f"{date_str}-{slug}"
    _RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
    wav_path = _RECORDINGS_DIR / f"{name}.wav"

    # rec is the sox front-end for recording; -c 1 = mono, -r 16000 = 16kHz (Whisper-optimal)
    proc = subprocess.Popen(
        ["rec", "-c", "1", "-r", "16000", str(wav_path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    state = {
        "name": name,
        "slug": slug,
        "pid": proc.pid,
        "wav_path": str(wav_path),
        "started_at": datetime.now().isoformat(),
    }
    _STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    _STATE_FILE.write_text(json.dumps(state, indent=2))
    return state


def stop() -> dict:
    """Stop the current recording. Returns the state dict. Raises RuntimeError if not recording."""
    state = current_state()
    if state is None:
        raise RuntimeError("No active recording. Start one with `meet start <slug>`.")

    pid = state["pid"]
    try:
        import signal
        import os
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass  # already died

    _STATE_FILE.unlink(missing_ok=True)
    return state
