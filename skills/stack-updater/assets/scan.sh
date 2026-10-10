#!/usr/bin/env bash
# Read-only scan of the stack this repo manages: bootstrap tools + repo skills.
# Rows are tab-separated: kind<TAB>name<TAB>detail...
# Never installs, upgrades, or writes anything. Missing tools are reported, not judged.

set -uo pipefail

has() { command -v "$1" >/dev/null 2>&1; }
row() { local IFS=$'\t'; printf '%s\n' "$*"; }

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO="${STACK_REPO:-$(cd "$(dirname "$SELF")/../../.." && pwd)}"

# --- OS / distro (informational; picks the system package manager) ---
os_id="unknown"
if [[ "$(uname -s)" == "Darwin" ]]; then
  os_id="macos"
elif [[ -r /etc/os-release ]]; then
  os_id="$(. /etc/os-release; echo "${ID:-unknown}")"
fi
pm="none"
for p in brew pacman apt dnf zypper apk; do has "$p" && { pm="$p"; break; }; done
row os "$os_id" "pm=$pm" "wsl=$(grep -qi microsoft /proc/version 2>/dev/null && echo 1 || echo 0)"

# --- who owns a binary (decides which updater applies) ---
source_of() {
  local real
  real="$(readlink -f "$1" 2>/dev/null || echo "$1")"
  case "$real" in */Cellar/*|*/linuxbrew/*|/opt/homebrew/*) echo brew; return ;; esac
  has pacman && pacman -Qo "$real" >/dev/null 2>&1 && { echo pacman; return; }
  has dpkg && dpkg -S "$real" >/dev/null 2>&1 && { echo apt; return; }
  has rpm && rpm -qf "$real" >/dev/null 2>&1 && { echo rpm; return; }
  case "$real" in
    */node_modules/*) echo npm-global ;;
    "$HOME"/go/bin/*) echo go-install ;;
    "$HOME"/.local/*|"$HOME"/.*) echo official-script ;;
    *) echo unknown ;;
  esac
}

version_of() {
  local out
  case "$1" in
    gentle-ai|engram) out="$(timeout 5 "$2" version 2>&1 | grep -m1 -E '[0-9]+\.[0-9]+')" ;;
    *) out="$(timeout 5 "$2" --version 2>&1 | grep -m1 -E '[0-9]+\.[0-9]+')" ;;
  esac
  printf '%s' "${out:--}"
}

# --- tools installed by bootstrap-harness.sh ---
for t in claude codex cursor-agent gentle-ai engram; do
  if bin="$(command -v "$t" 2>/dev/null)"; then
    row tool "$t" "$(version_of "$t" "$bin")" "$(source_of "$bin")"
  else
    row missing "$t"
  fi
done

# --- repo skills vs installed skills ---
if [[ -f "$REPO/install.sh" && -d "$REPO/skills" ]]; then
  row repo "$REPO" "behind=$(git -C "$REPO" fetch --quiet 2>/dev/null; git -C "$REPO" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo unknown)" \
    "dirty=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  state() { # dest skill
    local d="$1/$2"
    if [[ -L "$d" ]]; then [[ "$(readlink -f "$d")" == "$REPO/skills/$2" ]] && echo linked || echo foreign-link
    elif [[ -d "$d" ]]; then echo copy
    else echo missing; fi
  }
  for s in "$REPO"/skills/*/; do
    n="$(basename "$s")"
    [[ -f "$s/SKILL.md" ]] || continue
    ph=0; grep -rqE '\{\{[A-Z0-9_]+\}\}' "$s" 2>/dev/null && ph=1  # same rule as install.sh
    row skill "$n" "claude=$(state "$HOME/.claude/skills" "$n")" "cursor=$(state "$HOME/.cursor/skills" "$n")" "placeholders=$ph"
  done
fi
