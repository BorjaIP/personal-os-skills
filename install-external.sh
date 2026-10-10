#!/usr/bin/env bash
# Install third-party skills from external/catalog.tsv into every harness detected on this
# machine, globally, by wrapping the cross-agent `skills` CLI (vercel-labs/skills) at a pinned version.
#
# Usage:
#   ./install-external.sh list                          # catalog as TSV: id, status, license, source, description
#   ./install-external.sh agents                        # harnesses detected on this machine
#   ./install-external.sh install --only diagram-design # install the selected catalog entries
#
# Options (install):
#   --only LIST    catalog ids, comma-separated (required)
#   --yes, -y      do not ask for confirmation
#   --dry-run      print the command without running it

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="$ROOT/external/catalog.tsv"
SKILLS_CLI_VERSION="1.7.2"   # pinned: npx fetches this package from npm on every run

err()  { printf 'xx %s\n' "$*" >&2; }
info() { printf '==> %s\n' "$*"; }

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Harnesses verified against the skills CLI README: agent id|cli binary|config dir|global skills dir
harness_table() {
  cat <<EOF
claude-code|claude|$HOME/.claude|$HOME/.claude/skills
cursor|cursor-agent|$HOME/.cursor|$HOME/.cursor/skills
gemini-cli|gemini|$HOME/.gemini|$HOME/.gemini/skills
opencode|opencode|$HOME/.config/opencode|$HOME/.config/opencode/skills
github-copilot|copilot|$HOME/.copilot|$HOME/.copilot/skills
codex|codex|$HOME/.codex|$HOME/.agents/skills
pi|pi|$HOME/.pi|$HOME/.agents/skills
windsurf|windsurf|$HOME/.codeium/windsurf|$HOME/.codeium/windsurf/skills
EOF
}

# Print "agent|skills dir" for each harness whose CLI or config dir exists.
detected_harnesses() {
  local id bin dir skills
  while IFS='|' read -r id bin dir skills; do
    if command -v "$bin" >/dev/null 2>&1 || [[ -d "$dir" ]]; then
      printf '%s|%s\n' "$id" "$skills"
    fi
  done < <(harness_table)
}

catalog_rows() {
  [[ -f "$CATALOG" ]] || { err "Catalog not found: $CATALOG"; exit 1; }
  grep -v -e '^#' -e '^[[:space:]]*$' "$CATALOG"
}

# installed | missing | unknown (for '*' entries) based on the skills directories of detected harnesses.
status_of() { # $1=skills column
  local first dirs=() id skills_dir
  [[ "$1" == "*" ]] && { printf 'unknown'; return; }
  first="${1%%,*}"
  # "Universal" agents (Cursor, Gemini CLI, Codex, ...) share ~/.agents/skills.
  [[ -e "$HOME/.agents/skills/$first" ]] && { printf 'installed'; return; }
  while IFS='|' read -r id skills_dir; do
    [[ -e "$skills_dir/$first" ]] && { printf 'installed'; return; }
  done < <(detected_harnesses)
  printf 'missing'
}

cmd_list() {
  local id source skills license desc
  while IFS=$'\t' read -r id source skills license desc; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$(status_of "$skills")" "$license" "$source" "$desc"
  done < <(catalog_rows)
}

cmd_agents() {
  local id skills_dir
  while IFS='|' read -r id skills_dir; do
    printf '%s\t%s\n' "$id" "$skills_dir"
  done < <(detected_harnesses)
}

cmd_install() {
  local only="" assume_yes=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only)    [[ $# -ge 2 ]] || { err "Missing value for --only"; exit 1; }; only="$2"; shift ;;
      --yes|-y)  assume_yes=1 ;;
      --dry-run) dry_run=1 ;;
      *)         err "Unknown argument: $1"; usage 1 ;;
    esac
    shift
  done

  if [[ -z "$only" ]]; then
    err "No selection. Choose with --only (see: ./install-external.sh list)."
    exit 2
  fi

  local agents=() id skills_dir
  while IFS='|' read -r id skills_dir; do agents+=("$id"); done < <(detected_harnesses)
  if (( ${#agents[@]} == 0 )); then
    info "No supported harness detected; nothing to install."
    exit 0
  fi

  local wanted=() item
  IFS=',' read -r -a wanted <<< "$only"

  # Validate every id before touching anything.
  for item in "${wanted[@]}"; do
    catalog_rows | cut -f1 | grep -qx -- "$item" || { err "Unknown external skill '$item'. Run ./install-external.sh list"; exit 1; }
  done

  local row source skills license desc cmd s names
  for item in "${wanted[@]}"; do
    row="$(catalog_rows | awk -F'\t' -v id="$item" '$1 == id')"
    IFS=$'\t' read -r id source skills license desc <<< "$row"

    info "$id  (third-party, $license)"
    echo "    source:  github.com/$source"
    echo "    skills:  $skills"
    echo "    targets: ${agents[*]}"

    cmd=(npx --yes "skills@$SKILLS_CLI_VERSION" add "$source")
    IFS=',' read -r -a names <<< "$skills"
    for s in "${names[@]}"; do cmd+=(--skill "$s"); done
    cmd+=(-g -y)
    for s in "${agents[@]}"; do cmd+=(-a "$s"); done

    if (( dry_run == 1 )); then
      printf '    [dry-run]'; printf ' %q' "${cmd[@]}"; printf '\n'
      continue
    fi

    if (( assume_yes == 0 )); then
      if [[ -t 0 ]]; then
        read -rp "    Install this third-party skill? It adds instructions (and possibly scripts) your agents will follow. [y/N] " answer
        [[ "$answer" == "y" || "$answer" == "Y" ]] || { info "Skipped $id"; continue; }
      else
        err "Confirmation required without a terminal: pass --yes."
        exit 2
      fi
    fi

    "${cmd[@]}"
  done
}

case "${1:-}" in
  list)    shift; cmd_list "$@" ;;
  agents)  shift; cmd_agents "$@" ;;
  install) shift; cmd_install "$@" ;;
  -h|--help|"") usage 0 ;;
  *)       err "Unknown command: $1"; usage 1 ;;
esac
