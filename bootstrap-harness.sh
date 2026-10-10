#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# Bootstrap for T3 Code, agent CLIs, Gentle AI and Engram.
# The default Gentle AI preset (full-gentleman) includes Engram, Context7, GGA,
# skills, permissions, persona and theme. Graphify, CodeGraph and project-local
# configuration are outside this bootstrap by design. Authentication is never automated.

readonly SCRIPT_NAME="$(basename "$0")"
readonly HARNESS_HOME="${HOME:?HOME is not set}"
readonly HARNESS_BIN_DIR="${HARNESS_HOME}/.local/bin"

COMMAND="all"
AGENT_TARGETS="${HARNESS_AGENTS:-claude-code,codex,cursor}"
AGENTS_EXPLICIT=0
[[ -n "${HARNESS_AGENTS:-}" ]] && AGENTS_EXPLICIT=1
ONLY_COMPONENTS=""
GENTLE_PRESET="${HARNESS_GENTLE_PRESET:-full-gentleman}"
DRY_RUN=0
ASSUME_YES=0
UPDATE_REQUESTED=0
INSTALL_T3=1
INSTALL_PI=1

export PATH="${HARNESS_BIN_DIR}:${PATH}"

info() {
  printf '[info] %s\n' "$*"
}

ok() {
  printf '[ ok ] %s\n' "$*"
}

warn() {
  printf '[warn] %s\n' "$*" >&2
}

die() {
  printf '[fail] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./bootstrap-harness.sh [all|install|configure|doctor|list] [options]

Commands:
  all              Install, configure and verify everything. Default.
  install          Install missing T3, agent CLIs, Gentle AI and Engram.
  configure        Configure Gentle AI globally for the selected agents.
  doctor           Run read-only checks and Gentle AI diagnostics.
  list             Print components and whether each is installed (tab-separated).

Options:
  --agents LIST    Gentle AI agent IDs, comma-separated.
                   Default: claude-code,codex,cursor
  --only LIST      Act only on these components, comma-separated:
                   t3, claude-code, codex, cursor, gentle-ai, engram, pi.
                   Without it, the default set is t3, gentle-ai, engram and
                   the CLIs listed in --agents.
  --preset NAME    Gentle AI preset. Default: full-gentleman
                   (Engram, Context7, GGA, skills, permissions, persona, theme.
                   Other presets: minimal, ecosystem-only.)
  --update         Ask whether to update each installed tool.
                   Without this flag, installed tools are left unchanged.
  --without-t3     Skip T3 installation.
  --without-pi     Skip Pi installation.
  --yes, -y        Do not ask before installing or updating packages.
  --dry-run        Print planned actions without changing the machine.
  --help, -h       Show this help.

Examples:
  ./bootstrap-harness.sh --dry-run
  ./bootstrap-harness.sh all
  ./bootstrap-harness.sh all --update
  ./bootstrap-harness.sh all --update --yes
  HARNESS_AGENTS=claude-code,codex ./bootstrap-harness.sh configure
  ./bootstrap-harness.sh install --only claude-code,gentle-ai
  ./bootstrap-harness.sh list
EOF
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

ALL_COMPONENTS="t3 claude-code codex cursor gentle-ai engram pi"

in_csv() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Whether a component is part of this run (--only wins; otherwise the default set).
component_enabled() {
  if [[ -n "$ONLY_COMPONENTS" ]]; then
    in_csv "$1" "$ONLY_COMPONENTS"
    return
  fi
  case "$1" in
    t3) (( INSTALL_T3 == 1 )) ;;
    pi) (( INSTALL_PI == 1 )) ;;
    gentle-ai|engram) return 0 ;;
    *) in_csv "$1" "$AGENT_TARGETS" ;;
  esac
}

print_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_cmd() {
  print_command "$@"
  if (( DRY_RUN == 0 )); then
    "$@"
  fi
}

confirm_install() {
  if (( ASSUME_YES == 1 || DRY_RUN == 1 )); then
    return 0
  fi

  printf 'The script will install missing tools and configure the harness. Continue? [y/N] '
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

should_update() {
  local label="$1"

  (( UPDATE_REQUESTED == 1 )) || return 1

  if (( DRY_RUN == 1 )); then
    info "Dry-run would plan an update for ${label}."
    return 0
  fi

  if (( ASSUME_YES == 1 )); then
    info "Updating ${label} because --yes was supplied."
    return 0
  fi

  printf 'Update %s? [y/N] ' "$label"
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

platform_name() {
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
}

readonly PLATFORM="$(platform_name)"

brew_formula_installed() {
  has_command brew && brew list --formula "$1" >/dev/null 2>&1
}

brew_cask_installed() {
  has_command brew && brew list --cask "$1" >/dev/null 2>&1
}

ensure_homebrew() {
  if ! has_command brew; then
    die "Homebrew is not installed. Install it from https://brew.sh and run this script again."
  fi
}

ensure_brew_tap() {
  local tap="Gentleman-Programming/homebrew-tap"
  if ! brew tap | grep -Fqx "gentleman-programming/homebrew-tap"; then
    run_cmd brew tap "$tap"
  else
    info "Gentleman Programming tap is already configured."
  fi

  run_cmd brew trust gentleman-programming/tap
}

ensure_formula() {
  local formula="$1"
  local installed_name="${formula##*/}"

  if brew_formula_installed "$installed_name"; then
    if should_update "$installed_name"; then
      run_cmd brew upgrade "$formula"
    else
      ok "$installed_name is already installed; leaving it unchanged."
    fi
  else
    run_cmd brew install "$formula"
  fi
}

ensure_cask() {
  local cask="$1"

  if brew_cask_installed "$cask"; then
    if should_update "$cask"; then
      run_cmd brew upgrade --cask "$cask"
    else
      ok "$cask is already installed; leaving it unchanged."
    fi
  else
    run_cmd brew install --cask "$cask"
  fi
}

node_meets_t3_requirement() {
  has_command node || return 1
  node <<'NODE'
const [major, minor] = process.versions.node.split('.').map(Number);
const supported = major > 24 ||
  (major === 24 && minor >= 10) ||
  (major === 23 && minor >= 11) ||
  (major === 22 && minor >= 16);
process.exit(supported ? 0 : 1);
NODE
}

ensure_base_dependencies() {
  info "Checking base dependencies (${PLATFORM})."

  has_command git || die "Git is required. On macOS install Xcode Command Line Tools with: xcode-select --install"
  has_command curl || die "curl is required to install the official CLIs."

  if ! component_enabled t3 && ! component_enabled codex; then
    ok "Git and curl are available; Node.js is not needed for the selected components."
    return 0
  fi

  if ! has_command node || ! node_meets_t3_requirement; then
    if [[ "$PLATFORM" == "macos" ]]; then
      ensure_homebrew
      info "Node.js does not meet the T3 Code requirement."
      ensure_formula node
      export PATH="$(brew --prefix node)/bin:${HARNESS_BIN_DIR}:${PATH}"
    else
      die "Node.js does not meet the T3 requirement. Install Node.js 22.16+, 23.11+ or 24.10+ and run the script again."
    fi
  elif [[ "$PLATFORM" == "macos" ]] && brew_formula_installed node; then
    if should_update "Node.js"; then
      run_cmd brew upgrade node
      export PATH="$(brew --prefix node)/bin:${HARNESS_BIN_DIR}:${PATH}"
    else
      ok "Node.js $(node --version) is available; leaving it unchanged."
    fi
  fi

  has_command npm || die "npm is not available with Node.js."
  ok "Git, curl, Node.js $(node --version) and npm are available."
}

download_and_run_official_installer() {
  local url="$1"
  local label="$2"
  local temporary_file

  if (( DRY_RUN == 1 )); then
    info "Would download and run the official ${label} installer: ${url}"
    return 0
  fi

  temporary_file="$(mktemp "${TMPDIR:-/tmp}/harness-installer.XXXXXX")"
  trap 'rm -f "${temporary_file}"' RETURN
  curl -fsSL "$url" -o "$temporary_file"
  bash "$temporary_file"
  rm -f "$temporary_file"
  trap - RETURN
}

install_t3() {
  (( INSTALL_T3 == 1 )) || { info "Skipping T3 Code because --without-t3 was supplied."; return 0; }

  if [[ "$PLATFORM" == "macos" ]]; then
    ensure_homebrew
    if brew_cask_installed t3-code; then
      ensure_cask t3-code
    elif [[ -d "/Applications/T3 Code.app" || -d "${HARNESS_HOME}/Applications/T3 Code.app" ]]; then
      if should_update "T3 Code"; then
        warn "T3 Code is installed outside Homebrew. Update it from the application itself."
      else
        ok "T3 Code is installed outside Homebrew; leaving it unchanged."
      fi
    else
      ensure_cask t3-code
    fi
    return 0
  fi

  info "On Linux, T3 Code runs through npx; no native application is installed."
  info "Launch command: npx --yes t3@latest"
}

claude_supports_update() {
  has_command claude && claude --help 2>&1 | grep -Eq '(^|[[:space:]])update([[:space:]]|$)'
}

install_claude() {
  if has_command claude; then
    if should_update "Claude Code"; then
      if claude_supports_update; then
        run_cmd claude update
      else
        warn "The native Claude Code installation does not expose an update command; it may update automatically."
      fi
    else
      ok "Claude Code is already installed; leaving it unchanged."
    fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    ensure_homebrew
    ensure_cask claude-code
  else
    download_and_run_official_installer "https://claude.ai/install.sh" "Claude Code"
  fi
}

install_codex() {
  if has_command codex; then
    if should_update "Codex CLI"; then
      run_cmd codex --upgrade
    else
      ok "Codex CLI is already installed; leaving it unchanged."
    fi
  else
    # Use the official OpenAI installation path. Authentication is handled by the user with codex --login.
    run_cmd npm install -g @openai/codex
  fi
}

install_cursor() {
  if has_command cursor-agent; then
    if should_update "Cursor CLI"; then
      run_cmd cursor-agent update
    else
      ok "Cursor CLI is already installed; leaving it unchanged."
    fi
  else
    download_and_run_official_installer "https://cursor.com/install" "Cursor CLI"
    export PATH="${HARNESS_BIN_DIR}:${PATH}"
  fi
}

install_gentle_ai() {
  if [[ "$PLATFORM" == "macos" ]] && brew_formula_installed gentle-ai; then
    ensure_homebrew
    ensure_brew_tap
    ensure_formula gentle-ai
  elif has_command gentle-ai; then
    if should_update "Gentle AI"; then
      run_cmd gentle-ai upgrade
    else
      ok "Gentle AI is already installed; leaving it unchanged."
    fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    ensure_homebrew
    ensure_brew_tap
    ensure_formula gentle-ai
  else
    download_and_run_official_installer \
      "https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh" \
      "Gentle AI"
    export PATH="${HARNESS_BIN_DIR}:${PATH}"
  fi
}

install_pi() {
  if has_command pi; then
    ok "Pi is already installed ($(pi --version 2>/dev/null || echo 'unknown version'))."
    return 0
  fi
  info "Installing Pi (https://pi.dev)..."
  if [[ "$PLATFORM" == "macos" ]] && has_command brew; then
    # Pi distributes via its own installer; brew is not available yet.
    run_cmd curl -fsSL https://pi.dev/install.sh \| sh
  else
    run_cmd curl -fsSL https://pi.dev/install.sh \| sh
  fi
  ok "Pi installed."
}

install_engram() {
  if [[ "$PLATFORM" == "macos" ]] && brew_formula_installed engram; then
    ensure_homebrew
    ensure_brew_tap
    ensure_formula gentleman-programming/tap/engram
  elif has_command engram; then
    if should_update "Engram"; then
      if has_command go; then
        run_cmd go install github.com/Gentleman-Programming/engram/cmd/engram@latest
        export PATH="$(go env GOPATH)/bin:${HARNESS_BIN_DIR}:${PATH}"
      else
        warn "Engram is not managed by Homebrew and Go is not available; update it manually."
      fi
    else
      ok "Engram is already installed; leaving it unchanged."
    fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    ensure_homebrew
    ensure_brew_tap
    ensure_formula gentleman-programming/tap/engram
  elif has_command go; then
    run_cmd go install github.com/Gentleman-Programming/engram/cmd/engram@latest
    export PATH="$(go env GOPATH)/bin:${HARNESS_BIN_DIR}:${PATH}"
  else
    die "Engram requires Homebrew on macOS or Go on Linux."
  fi
}

install_all() {
  confirm_install || die "Installation cancelled."
  ensure_base_dependencies
  component_enabled t3 && install_t3
  component_enabled claude-code && install_claude
  component_enabled codex && install_codex
  component_enabled cursor && install_cursor
  component_enabled gentle-ai && install_gentle_ai
  component_enabled engram && install_engram
  component_enabled pi && install_pi
  ok "Tool installation completed."
}

agent_cli_name() {
  case "$1" in
    claude-code) printf 'claude' ;;
    cursor) printf 'cursor-agent' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Keep only agents whose CLI is installed; report the rest without installing them.
filter_installed_agents() {
  local agent present=() missing=()
  local -a requested
  IFS=',' read -r -a requested <<< "$AGENT_TARGETS"

  for agent in "${requested[@]}"; do
    if has_command "$(agent_cli_name "$agent")"; then
      present+=("$agent")
    else
      missing+=("$agent")
    fi
  done

  (( ${#missing[@]} == 0 )) || info "Not installed, skipping: $(IFS=,; echo "${missing[*]}")"
  (( ${#present[@]} > 0 )) || die "None of the requested agents is installed (${AGENT_TARGETS})."
  AGENT_TARGETS="$(IFS=,; echo "${present[*]}")"
}

configure_gentle_ai() {
  if ! component_enabled gentle-ai; then
    info "Gentle AI is not selected; skipping configuration."
    return 0
  fi

  if ! has_command gentle-ai && (( DRY_RUN == 0 )); then
    die "Gentle AI is not installed. Run first: $SCRIPT_NAME install"
  fi

  if (( DRY_RUN == 0 )); then
    filter_installed_agents
  fi

  info "Configuring Gentle AI globally for: ${AGENT_TARGETS}"
  info "Preset: ${GENTLE_PRESET}"
  info "This configuration is global and does not modify repositories."

  run_cmd gentle-ai install \
    --agent "$AGENT_TARGETS" \
    --preset "$GENTLE_PRESET" \
    --scope global

  run_cmd gentle-ai sync --agent "$AGENT_TARGETS"

  # RDD is user-controlled and reversible. Keep failures visible if a future release changes this command.
  if (( DRY_RUN == 1 )); then
    info "Would enable RDD globally: gentle-ai review mode enable --scope global"
  elif ! gentle-ai review mode enable --scope global; then
    warn "Could not enable RDD automatically. Run manually:"
    warn "  gentle-ai review mode enable --scope global"
  else
    ok "RDD enabled globally."
  fi

  ok "Gentle AI configured."
}

show_version() {
  local command_name="$1"
  if has_command "$command_name"; then
    case "$command_name" in
      gentle-ai) gentle-ai version 2>&1 | head -n 1 || true ;;
      engram) engram version 2>&1 | head -n 1 || true ;;
      *) "$command_name" --version 2>&1 | head -n 1 || true ;;
    esac
  else
    printf 'missing\n'
  fi
}

doctor() {
  info "Harness bootstrap diagnostics."
  printf 'Platform: %s\n' "$PLATFORM"
  printf 'Agents:   %s\n' "$AGENT_TARGETS"
  printf 'Preset:   %s\n' "$GENTLE_PRESET"
  if (( UPDATE_REQUESTED == 1 )); then
    printf 'Update:   enabled\n'
  else
    printf 'Update:   disabled\n'
  fi
  printf '\n'

  local command_name
  for command_name in node npm git gentle-ai engram claude codex cursor-agent; do
    printf '%-14s %s\n' "$command_name" "$(show_version "$command_name")"
  done

  if [[ "$PLATFORM" == "macos" ]] && has_command brew; then
    if brew_cask_installed t3-code; then
      printf '%-14s %s\n' "t3-code" "installed (Homebrew cask)"
    elif [[ -d "/Applications/T3 Code.app" || -d "${HARNESS_HOME}/Applications/T3 Code.app" ]]; then
      printf '%-14s %s\n' "t3-code" "installed (application bundle)"
    else
      printf '%-14s %s\n' "t3-code" "missing"
    fi
  else
    printf '%-14s %s\n' "t3-code" "run with npx --yes t3@latest"
  fi

  if has_command gentle-ai; then
    printf '\nGentle AI doctor:\n'
    if (( DRY_RUN == 1 )); then
      info "Would run: gentle-ai doctor"
    else
      gentle-ai doctor || warn "Gentle AI doctor reported warnings or errors."
    fi
  fi

  if has_command engram; then
    printf '\nEngram projects:\n'
    if (( DRY_RUN == 1 )); then
      info "Would run: engram projects list"
    else
      engram projects list || warn "Could not list Engram projects; check the installation."
    fi
  fi
}

component_status() {
  case "$1" in
    t3)
      if [[ "$PLATFORM" == "macos" ]] && { brew_cask_installed t3-code || [[ -d "/Applications/T3 Code.app" ]]; }; then
        printf 'installed'
      elif [[ "$PLATFORM" == "macos" ]]; then printf 'missing'
      else printf 'npx'; fi ;;
    pi)
      if has_command pi; then printf 'installed'; else printf 'missing'; fi ;;
    *)
      if has_command "$(agent_cli_name "$1")"; then printf 'installed'; else printf 'missing'; fi ;;
  esac
}

component_label() {
  case "$1" in
    t3) printf 'T3 Code (macOS app; on Linux runs through npx)' ;;
    claude-code) printf 'Claude Code CLI' ;;
    codex) printf 'Codex CLI' ;;
    cursor) printf 'Cursor CLI (cursor-agent)' ;;
    gentle-ai) printf 'Gentle AI (configured with the selected preset)' ;;
    engram) printf 'Engram persistent memory' ;;
    pi) printf 'Pi coding agent harness' ;;
  esac
}

list_components() {
  local id IFS=' '
  for id in $ALL_COMPONENTS; do
    printf '%s\t%s\t%s\n' "$id" "$(component_status "$id")" "$(component_label "$id")"
  done
}

parse_args() {
  if [[ $# -gt 0 && "$1" != --* ]]; then
    COMMAND="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agents|--agent)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        AGENT_TARGETS="$2"
        AGENTS_EXPLICIT=1
        shift 2
        ;;
      --only)
        [[ $# -ge 2 ]] || die "Missing value for --only"
        ONLY_COMPONENTS="$2"
        shift 2
        ;;
      --preset)
        [[ $# -ge 2 ]] || die "Missing value for --preset"
        GENTLE_PRESET="$2"
        shift 2
        ;;
      --update)
        UPDATE_REQUESTED=1
        shift
        ;;
      --without-t3)
        INSTALL_T3=0
        ;;
      --without-pi)
        INSTALL_PI=0
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  case "$COMMAND" in
    all|install|configure|doctor|list) ;;
    *) die "Unknown command: $COMMAND" ;;
  esac

  local item items=()
  IFS=',' read -r -a items <<< "$ONLY_COMPONENTS"
  for item in "${items[@]:-}"; do
    [[ -n "$item" ]] || continue
    [[ " $ALL_COMPONENTS " == *" $item "* ]] || die "Unknown component '$item'. Available: ${ALL_COMPONENTS// /, }"
  done

  # With --only and no explicit --agents, configure exactly the selected agent CLIs.
  if [[ -n "$ONLY_COMPONENTS" ]] && (( AGENTS_EXPLICIT == 0 )); then
    local agents=()
    for item in claude-code codex cursor; do
      in_csv "$item" "$ONLY_COMPONENTS" && agents+=("$item")
    done
    AGENT_TARGETS="$(IFS=,; echo "${agents[*]:-}")"
  fi
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    all)
      install_all
      configure_gentle_ai
      doctor
      ;;
    install)
      install_all
      ;;
    configure)
      configure_gentle_ai
      ;;
    doctor)
      doctor
      ;;
    list)
      list_components
      exit 0
      ;;
  esac

  ok "Bootstrap finished."
}

main "$@"
