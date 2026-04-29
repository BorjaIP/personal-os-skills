#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop Meeting Recording
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ⏹
# @raycast.packageName Meeting Notes

# uv tool installs binaries to ~/.local/bin — Raycast doesn't inherit shell PATH
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

meet stop
