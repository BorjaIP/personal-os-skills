#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start Meeting Recording
# @raycast.mode compact
# @raycast.argument1 { "type": "text", "placeholder": "Meeting slug (e.g. standup)", "optional": false }

# Optional parameters:
# @raycast.icon 🎙
# @raycast.packageName Meeting Notes

# uv tool installs binaries to ~/.local/bin — Raycast doesn't inherit shell PATH
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

meet start "$1"
