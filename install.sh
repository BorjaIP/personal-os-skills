#!/usr/bin/env bash
# Install personal skills into Claude Code and/or Cursor user-level skill directories.
#
# Skills can contain {{PLACEHOLDER}} tokens. When any file inside a skill contains
# placeholders, the whole skill directory is rendered (copied with substitutions)
# into the destination instead of being symlinked, so the shipped SKILL.md is
# customised for this machine (e.g. Obsidian paths).
#
# Usage:
#   ./install.sh                       # interactive install, prompts for Obsidian paths
#   ./install.sh --claude-only         # only install into ~/.claude/skills
#   ./install.sh --cursor-only         # only install into ~/.cursor/skills-cursor
#   ./install.sh --copy                # copy instead of symlink (even when no placeholders)
#   ./install.sh --uninstall           # remove entries installed by this script
#   ./install.sh --dry-run             # show actions without performing them
#   ./install.sh --force               # overwrite existing entries without prompting
#   ./install.sh --no-prompt           # never prompt (use existing config or defaults)
#   ./install.sh --reconfigure         # re-run the config prompt even if config exists
#   ./install.sh --vault <path>        # set Obsidian vault path non-interactively
#   ./install.sh --ops-dir <path>      # set Obsidian ops dir non-interactively

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"

CLAUDE_DEST="$HOME/.claude/skills"
# Personal Cursor skills live under ~/.cursor/skills/ (user scope).
# NEVER use ~/.cursor/skills-cursor/ — that path is managed by Cursor for
# built-in skills and user-placed files there can be clobbered.
CURSOR_DEST="$HOME/.cursor/skills"

CONFIG_DIR="$HOME/.config/personal-os-skills"
CONFIG_FILE="$CONFIG_DIR/config.env"

INSTALL_CLAUDE=1
INSTALL_CURSOR=1
MODE="symlink"     # symlink | copy
ACTION="install"   # install | uninstall
DRY_RUN=0
FORCE=0
PROMPT=1
RECONFIGURE=0

CLI_VAULT=""
CLI_OPS_DIR=""

color() { if [[ -t 1 ]]; then printf "\033[%sm%s\033[0m" "$1" "$2"; else printf "%s" "$2"; fi; }
info() { echo "$(color "1;34" "==>") $*"; }
warn() { echo "$(color "1;33" "!! ") $*" >&2; }
err()  { echo "$(color "1;31" "xx ") $*" >&2; }

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude-only) INSTALL_CURSOR=0 ;;
    --cursor-only) INSTALL_CLAUDE=0 ;;
    --copy)        MODE="copy" ;;
    --uninstall)   ACTION="uninstall" ;;
    --dry-run)     DRY_RUN=1 ;;
    --force)       FORCE=1 ;;
    --no-prompt)   PROMPT=0 ;;
    --reconfigure) RECONFIGURE=1 ;;
    --vault)       shift; CLI_VAULT="${1:-}" ;;
    --ops-dir)     shift; CLI_OPS_DIR="${1:-}" ;;
    -h|--help)     usage 0 ;;
    *)             err "Unknown argument: $1"; usage 1 ;;
  esac
  shift
done

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "    [dry-run] $*"
  else
    eval "$@"
  fi
}

# ---------------------------------------------------------------------------
# Configuration (Obsidian paths)
# ---------------------------------------------------------------------------

OBSIDIAN_VAULT=""
OBSIDIAN_OPS_DIR=""
K8S_ANALYSES_DIR=""
K8S_COST_ANALYSES_DIR=""
DATADOG_ANALYSES_DIR=""
DATADOG_TRIAGE_DIR=""
SENTRY_ANALYSES_DIR=""
INCIDENTS_DIR=""
RUNBOOKS_DIR=""
MEETINGS_DIR=""
TRANSCRIPTIONS_DIR=""
RAYCAST_SCRIPTS_DIR=""

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
}

save_config() {
  run "mkdir -p \"$CONFIG_DIR\""
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "    [dry-run] write config to $CONFIG_FILE"
    return
  fi
  cat > "$CONFIG_FILE" <<EOF
# Managed by personal-os-skills/install.sh
# Regenerate with: ./install.sh --reconfigure
OBSIDIAN_VAULT="$OBSIDIAN_VAULT"
OBSIDIAN_OPS_DIR="$OBSIDIAN_OPS_DIR"
K8S_ANALYSES_DIR="$K8S_ANALYSES_DIR"
K8S_COST_ANALYSES_DIR="$K8S_COST_ANALYSES_DIR"
DATADOG_ANALYSES_DIR="$DATADOG_ANALYSES_DIR"
DATADOG_TRIAGE_DIR="$DATADOG_TRIAGE_DIR"
SENTRY_ANALYSES_DIR="$SENTRY_ANALYSES_DIR"
INCIDENTS_DIR="$INCIDENTS_DIR"
RUNBOOKS_DIR="$RUNBOOKS_DIR"
MEETINGS_DIR="$MEETINGS_DIR"
TRANSCRIPTIONS_DIR="$TRANSCRIPTIONS_DIR"
RAYCAST_SCRIPTS_DIR="$RAYCAST_SCRIPTS_DIR"
EOF
  info "Saved config to $CONFIG_FILE"
}

derive_paths() {
  if [[ -n "$OBSIDIAN_VAULT" && -z "$OBSIDIAN_OPS_DIR" ]]; then
    OBSIDIAN_OPS_DIR="$OBSIDIAN_VAULT/ops"
  fi
  if [[ -n "$OBSIDIAN_OPS_DIR" ]]; then
    K8S_ANALYSES_DIR="${K8S_ANALYSES_DIR:-$OBSIDIAN_OPS_DIR/k8s}"
    K8S_COST_ANALYSES_DIR="${K8S_COST_ANALYSES_DIR:-$OBSIDIAN_OPS_DIR/k8s-cost}"
    DATADOG_ANALYSES_DIR="${DATADOG_ANALYSES_DIR:-$OBSIDIAN_OPS_DIR/datadog}"
    DATADOG_TRIAGE_DIR="${DATADOG_TRIAGE_DIR:-$OBSIDIAN_OPS_DIR/datadog/triage}"
    SENTRY_ANALYSES_DIR="${SENTRY_ANALYSES_DIR:-$OBSIDIAN_OPS_DIR/sentry}"
    INCIDENTS_DIR="${INCIDENTS_DIR:-$OBSIDIAN_OPS_DIR/incidents}"
    RUNBOOKS_DIR="${RUNBOOKS_DIR:-$OBSIDIAN_OPS_DIR/runbooks}"
  fi
  if [[ -n "$OBSIDIAN_VAULT" ]]; then
    MEETINGS_DIR="${MEETINGS_DIR:-$OBSIDIAN_VAULT/meetings/notes}"
    TRANSCRIPTIONS_DIR="${TRANSCRIPTIONS_DIR:-$OBSIDIAN_VAULT/meetings/transcriptions}"
  fi
  # Default Raycast scripts dir (macOS)
  if [[ -z "$RAYCAST_SCRIPTS_DIR" ]]; then
    local raycast_default="$HOME/Library/Application Support/Raycast/scripts"
    if [[ -d "$raycast_default" ]]; then
      RAYCAST_SCRIPTS_DIR="$raycast_default"
    fi
  fi
}

prompt_config() {
  echo
  info "Obsidian integration (optional — press Enter to skip)"
  echo "    Skills that generate analyses will write into \$OBSIDIAN_OPS_DIR/<source>"
  echo "    instead of a local ./docs/error_analyses/ folder."
  echo

  local default_vault="${OBSIDIAN_VAULT:-$HOME/pkm/pkm}"
  local prompt_vault
  read -rp "  Obsidian vault path [$default_vault] (empty = skip Obsidian): " prompt_vault
  if [[ -z "$prompt_vault" && -z "$OBSIDIAN_VAULT" ]]; then
    prompt_vault="$default_vault"
  elif [[ -z "$prompt_vault" ]]; then
    prompt_vault="$OBSIDIAN_VAULT"
  fi

  if [[ "$prompt_vault" == "-" || "$prompt_vault" == "none" || "$prompt_vault" == "skip" ]]; then
    OBSIDIAN_VAULT=""
    OBSIDIAN_OPS_DIR=""
    info "Skipping Obsidian integration"
    return
  fi

  if [[ ! -d "$prompt_vault" ]]; then
    warn "Vault dir '$prompt_vault' does not exist yet — it will be created on demand."
  fi
  OBSIDIAN_VAULT="$prompt_vault"

  local default_ops="${OBSIDIAN_OPS_DIR:-$OBSIDIAN_VAULT/ops}"
  local prompt_ops
  read -rp "  Obsidian ops dir  [$default_ops]: " prompt_ops
  OBSIDIAN_OPS_DIR="${prompt_ops:-$default_ops}"
}

configure() {
  load_config

  [[ -n "$CLI_VAULT"   ]] && OBSIDIAN_VAULT="$CLI_VAULT"
  [[ -n "$CLI_OPS_DIR" ]] && OBSIDIAN_OPS_DIR="$CLI_OPS_DIR"

  local has_any_config=0
  [[ -n "$OBSIDIAN_VAULT" || -n "$OBSIDIAN_OPS_DIR" ]] && has_any_config=1

  if [[ "$PROMPT" -eq 1 && ( "$has_any_config" -eq 0 || "$RECONFIGURE" -eq 1 ) ]]; then
    prompt_config
  fi

  derive_paths

  if [[ -n "$OBSIDIAN_VAULT" ]]; then
    info "Obsidian vault:    $OBSIDIAN_VAULT"
    info "Obsidian ops dir:  $OBSIDIAN_OPS_DIR"
    save_config
  else
    warn "No Obsidian vault configured. Placeholders will fall back to ./docs/error_analyses"
    K8S_ANALYSES_DIR="${K8S_ANALYSES_DIR:-./docs/error_analyses}"
    K8S_COST_ANALYSES_DIR="${K8S_COST_ANALYSES_DIR:-./docs/cost_analyses}"
    DATADOG_ANALYSES_DIR="${DATADOG_ANALYSES_DIR:-./docs/datadog_analyses}"
    DATADOG_TRIAGE_DIR="${DATADOG_TRIAGE_DIR:-./docs/datadog_analyses/triage}"
    SENTRY_ANALYSES_DIR="${SENTRY_ANALYSES_DIR:-./docs/sentry_analyses}"
    INCIDENTS_DIR="${INCIDENTS_DIR:-./docs/incidents}"
    RUNBOOKS_DIR="${RUNBOOKS_DIR:-./docs/runbooks}"
  fi
}

# ---------------------------------------------------------------------------
# Placeholder rendering
# ---------------------------------------------------------------------------

# Variables to expose as placeholders. Add new ones here + in save_config().
PLACEHOLDER_VARS=(
  OBSIDIAN_VAULT
  OBSIDIAN_OPS_DIR
  K8S_ANALYSES_DIR
  K8S_COST_ANALYSES_DIR
  DATADOG_ANALYSES_DIR
  DATADOG_TRIAGE_DIR
  SENTRY_ANALYSES_DIR
  INCIDENTS_DIR
  RUNBOOKS_DIR
  MEETINGS_DIR
  TRANSCRIPTIONS_DIR
  RAYCAST_SCRIPTS_DIR
)

dir_has_placeholders() { # $1=dir
  local dir="$1"
  grep -rlE '\{\{[A-Z0-9_]+\}\}' "$dir" >/dev/null 2>&1
}

render_file() { # $1=src $2=dst
  local src="$1" dst="$2"
  local tmp
  tmp="$(mktemp)"
  cp "$src" "$tmp"
  local var val
  for var in "${PLACEHOLDER_VARS[@]}"; do
    val="${!var:-}"
    # escape for sed replacement
    local esc="${val//\\/\\\\}"
    esc="${esc//|/\\|}"
    esc="${esc//&/\\&}"
    sed "s|{{${var}}}|${esc}|g" "$tmp" > "$tmp.out"
    mv "$tmp.out" "$tmp"
  done
  mv "$tmp" "$dst"
}

render_skill_dir() { # $1=src_dir $2=dst_dir
  local src="$1" dst="$2"
  run "mkdir -p \"$dst\""
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "    [dry-run] render-copy $src -> $dst (with placeholder substitution)"
    return
  fi
  # Copy structure first
  (cd "$src" && find . -type d) | while read -r d; do
    mkdir -p "$dst/$d"
  done
  # Copy/render files
  (cd "$src" && find . -type f) | while read -r f; do
    local rel="${f#./}"
    # Substitute text-ish files; skip binaries
    if file "$src/$rel" | grep -qE 'text|ASCII|UTF-8|Unicode|empty'; then
      render_file "$src/$rel" "$dst/$rel"
      # Preserve executable bit
      if [[ -x "$src/$rel" ]]; then chmod +x "$dst/$rel"; fi
    else
      cp -p "$src/$rel" "$dst/$rel"
    fi
  done
}

# ---------------------------------------------------------------------------
# Install / uninstall single skill
# ---------------------------------------------------------------------------

install_skill() { # $1=src_dir $2=dest_root $3=skill_name
  local src="$1" dest_root="$2" name="$3"
  local dest="$dest_root/$name"
  local needs_render=0
  dir_has_placeholders "$src" && needs_render=1

  run "mkdir -p \"$dest_root\""

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      run "rm -rf \"$dest\""
    else
      # A rendered copy must always be refreshed (re-run is the user's intent)
      if [[ "$needs_render" -eq 1 && ! -L "$dest" ]]; then
        run "rm -rf \"$dest\""
      elif [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
        info "  - $name already linked, skipping"
        return
      else
        warn "  - $dest exists; use --force to overwrite"
        return
      fi
    fi
  fi

  if [[ "$needs_render" -eq 1 ]]; then
    render_skill_dir "$src" "$dest"
    info "  + rendered   $name -> $dest (placeholders substituted)"
  elif [[ "$MODE" == "symlink" ]]; then
    run "ln -s \"$src\" \"$dest\""
    info "  + symlinked  $name -> $dest"
  else
    run "cp -R \"$src\" \"$dest\""
    info "  + copied     $name -> $dest"
  fi
}

uninstall_skill() { # $1=dest_root $2=skill_name $3=expected_src
  local dest_root="$1" name="$2" expected_src="$3"
  local dest="$dest_root/$name"

  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    return
  fi

  if [[ -L "$dest" ]]; then
    local target
    target="$(readlink "$dest")"
    if [[ "$target" == "$expected_src" || "$FORCE" -eq 1 ]]; then
      run "rm \"$dest\""
      info "  - removed symlink $dest"
    else
      warn "  - $dest is a symlink pointing elsewhere ($target); use --force to remove"
    fi
  else
    if [[ "$FORCE" -eq 1 ]]; then
      run "rm -rf \"$dest\""
      info "  - removed directory $dest"
    else
      warn "  - $dest is not a symlink (probably a rendered copy); use --force to remove"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Materialise Obsidian ops tree (only during install, when vault configured)
# ---------------------------------------------------------------------------

bootstrap_meetings_tree() {
  [[ -z "$OBSIDIAN_VAULT" ]] && return 0
  [[ "$ACTION" == "uninstall" ]] && return 0

  run "mkdir -p \"$MEETINGS_DIR\""
  run "mkdir -p \"$TRANSCRIPTIONS_DIR\""

  # Install Obsidian Templater template for meetings
  local template_src="$SKILLS_SRC/meet/vault/templates/meeting.md"
  local templates_dir="$OBSIDIAN_VAULT/templates"
  if [[ -f "$template_src" ]]; then
    run "mkdir -p \"$templates_dir\""
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "    [dry-run] install meeting template -> $templates_dir/meeting.md"
    else
      cp "$template_src" "$templates_dir/meeting.md"
      info "Installed meeting template -> $templates_dir/meeting.md"
    fi
  fi

  # Install Raycast scripts if Raycast dir is configured
  if [[ -n "$RAYCAST_SCRIPTS_DIR" ]]; then
    local raycast_src="$SKILLS_SRC/meet/raycast"
    if [[ -d "$raycast_src" ]]; then
      run "mkdir -p \"$RAYCAST_SCRIPTS_DIR\""
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "    [dry-run] install Raycast scripts -> $RAYCAST_SCRIPTS_DIR"
      else
        for script in "$raycast_src"/*.sh; do
          [[ -f "$script" ]] || continue
          local dest_script="$RAYCAST_SCRIPTS_DIR/$(basename "$script")"
          render_file "$script" "$dest_script"
          chmod +x "$dest_script"
          info "Installed Raycast script -> $dest_script"
        done
      fi
    fi
  else
    warn "Raycast scripts dir not found — skipping Raycast integration."
    warn "Set RAYCAST_SCRIPTS_DIR in $CONFIG_FILE or in your Raycast settings."
  fi
}

bootstrap_ops_tree() {
  [[ -z "$OBSIDIAN_OPS_DIR" ]] && return 0
  [[ "$ACTION" == "uninstall" ]] && return 0

  local dirs=(
    "$K8S_ANALYSES_DIR"
    "$K8S_COST_ANALYSES_DIR"
    "$DATADOG_ANALYSES_DIR"
    "$DATADOG_TRIAGE_DIR"
    "$SENTRY_ANALYSES_DIR"
    "$INCIDENTS_DIR"
    "$RUNBOOKS_DIR"
  )
  for d in "${dirs[@]}"; do
    run "mkdir -p \"$d\""
  done

  local index="$OBSIDIAN_OPS_DIR/_index.md"
  if [[ ! -e "$index" && "$DRY_RUN" -ne 1 ]]; then
    cat > "$index" <<'EOF'
---
title: Ops / Triage Index
tags: [ops, moc]
---

# Ops / Triage Index

Entry point for all ops artifacts (triage, analyses, incidents, runbooks).
See `personal-os-skills/docs/triage-architecture.md` for the full workflow.

## Recent analyses (Dataview)

```dataview
TABLE file.ctime AS Created, source, env, severity, status
FROM "ops"
WHERE source
SORT file.ctime DESC
LIMIT 20
```

## Open triage

```dataview
TABLE file.ctime AS Created, source, severity
FROM "ops"
WHERE status = "open"
SORT severity DESC, file.ctime DESC
```
EOF
    info "Created $index"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ ! -d "$SKILLS_SRC" ]]; then
  err "skills/ directory not found at $SKILLS_SRC"
  exit 1
fi

configure

bootstrap_ops_tree
bootstrap_meetings_tree

SKILLS=()
while IFS= read -r line; do
  SKILLS+=("$line")
done < <(find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  warn "No skills found in $SKILLS_SRC"
  exit 0
fi

info "Repo root: $REPO_ROOT"
info "Mode:      $MODE"
info "Action:    $ACTION"
[[ "$DRY_RUN" -eq 1 ]] && info "Dry run:   yes"

for skill_path in "${SKILLS[@]}"; do
  skill_name="$(basename "$skill_path")"

  if [[ ! -f "$skill_path/SKILL.md" ]]; then
    warn "Skipping '$skill_name' (no SKILL.md found)"
    continue
  fi

  if [[ "$ACTION" == "install" ]]; then
    info "Installing $skill_name"
    [[ "$INSTALL_CLAUDE" -eq 1 ]] && install_skill "$skill_path" "$CLAUDE_DEST" "$skill_name"
    [[ "$INSTALL_CURSOR" -eq 1 ]] && install_skill "$skill_path" "$CURSOR_DEST" "$skill_name"
  else
    info "Uninstalling $skill_name"
    [[ "$INSTALL_CLAUDE" -eq 1 ]] && uninstall_skill "$CLAUDE_DEST" "$skill_name" "$skill_path"
    [[ "$INSTALL_CURSOR" -eq 1 ]] && uninstall_skill "$CURSOR_DEST" "$skill_name" "$skill_path"
  fi
done

info "Done."
