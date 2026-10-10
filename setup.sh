#!/usr/bin/env bash
# Single entry point: choose harness tools, skill families and external (third-party) skills,
# then delegate to bootstrap-harness.sh, install.sh and install-external.sh. All still work on their own.
#
# Usage:
#   ./setup.sh                                  # interactive menu
#   ./setup.sh --list [tools|external|families] # print the catalog (or one section), then exit
#   ./setup.sh --only claude-code,gentle-ai,ops # non-interactive: tool ids and/or family names
#   ./setup.sh --only harness --dry-run         # preview without changing anything
#   ./setup.sh --only diagram-design            # third-party skill from external/catalog.tsv
#   ./setup.sh --only gentle-ai --preset minimal --yes
#
# Options:
#   --only LIST    tool ids, skill family names and external skill ids, comma-separated
#   --preset NAME  Gentle AI preset (default: full-gentleman)
#   --yes, -y      do not ask for confirmation
#   --dry-run      show actions without performing them
#   --list         list tools, external skills and families
#   -h, --help     show this help

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$ROOT/bootstrap-harness.sh"
INSTALLER="$ROOT/install.sh"
EXTERNAL="$ROOT/install-external.sh"

ONLY=""
PRESET=""
ASSUME_YES=0
DRY_RUN=0
LIST_ONLY=0
LIST_SECTION=all

err()  { printf 'xx %s\n' "$*" >&2; }
info() { printf '==> %s\n' "$*"; }

usage() {
  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)    [[ $# -ge 2 ]] || { err "Missing value for --only"; exit 1; }; ONLY="$2"; shift ;;
    --preset)  [[ $# -ge 2 ]] || { err "Missing value for --preset"; exit 1; }; PRESET="$2"; shift ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --list)    LIST_ONLY=1
               if [[ $# -ge 2 && "$2" != -* ]]; then LIST_SECTION="$2"; shift; fi ;;
    -h|--help) usage 0 ;;
    *)         err "Unknown argument: $1"; usage 1 ;;
  esac
  shift
done

# --- catalog -----------------------------------------------------------------

TOOL_IDS=(); TOOL_STATUS=(); TOOL_LABEL=()
while IFS=$'\t' read -r id status label; do
  TOOL_IDS+=("$id"); TOOL_STATUS+=("$status"); TOOL_LABEL+=("$label")
done < <("$BOOTSTRAP" list)

EXT_IDS=(); EXT_STATUS=(); EXT_LABEL=()
while IFS=$'\t' read -r id status license source desc; do
  EXT_IDS+=("$id"); EXT_STATUS+=("$status"); EXT_LABEL+=("$desc [$license, $source]")
done < <("$EXTERNAL" list)

FAMILY_IDS=(); FAMILY_SKILLS=()
while IFS= read -r line; do
  if [[ "$line" =~ ^\ \ ([a-z][a-z-]*)$ ]]; then
    FAMILY_IDS+=("${BASH_REMATCH[1]}"); FAMILY_SKILLS+=("")
  elif [[ "$line" =~ ^\ \ \ \ -\ (.+)$ ]]; then
    last=$(( ${#FAMILY_IDS[@]} - 1 ))
    FAMILY_SKILLS[$last]="${FAMILY_SKILLS[$last]}${BASH_REMATCH[1]} "
  fi
done < <("$INSTALLER" --list)

print_catalog() { # $1 = all | tools | external | families (numbers match the interactive menu)
  local want="${1:-all}" i n=1 show
  show() { [[ "$want" == all || "$want" == "$1" ]]; }

  show tools && echo "Tools"
  for i in "${!TOOL_IDS[@]}"; do
    show tools && printf '  %2d) %-12s %-10s %s\n' "$n" "${TOOL_IDS[$i]}" "${TOOL_STATUS[$i]}" "${TOOL_LABEL[$i]}"
    n=$((n + 1))
  done
  show external && echo "External skills (third-party)"
  for i in ${EXT_IDS[@]+"${!EXT_IDS[@]}"}; do
    show external && printf '  %2d) %-16s %-10s %s\n' "$n" "${EXT_IDS[$i]}" "${EXT_STATUS[$i]}" "${EXT_LABEL[$i]}"
    n=$((n + 1))
  done
  show families && echo "Skill families"
  for i in "${!FAMILY_IDS[@]}"; do
    show families && printf '  %2d) %-12s %s\n' "$n" "${FAMILY_IDS[$i]}" "${FAMILY_SKILLS[$i]}"
    n=$((n + 1))
  done
  return 0
}

# Map one token (number or name) to a canonical tool id or family name.
resolve_token() {
  local token="$1" all=("${TOOL_IDS[@]}" ${EXT_IDS[@]+"${EXT_IDS[@]}"} "${FAMILY_IDS[@]}") t
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    (( token >= 1 && token <= ${#all[@]} )) || return 1
    printf '%s' "${all[$((token - 1))]}"
    return 0
  fi
  for t in "${all[@]}"; do [[ "$t" == "$token" ]] && { printf '%s' "$t"; return 0; }; done
  return 1
}

if (( LIST_ONLY == 1 )); then
  case "$LIST_SECTION" in
    all|tools|external|families) ;;
    *) err "Unknown list section '$LIST_SECTION'. Use: tools, external or families."; exit 1 ;;
  esac
  print_catalog "$LIST_SECTION"
  exit 0
fi

# --- selection ---------------------------------------------------------------

if [[ -z "$ONLY" ]]; then
  if [[ -t 0 ]]; then
    echo
    print_catalog
    echo
    read -rp "Numbers or names, comma-separated (Enter = cancel): " ONLY
    [[ -n "$ONLY" ]] || { info "Nothing selected."; exit 0; }
  else
    err "No selection. Choose with --only (tool ids and/or family names)."
    echo "    See: ./setup.sh --list" >&2
    exit 2
  fi
fi

SEL_TOOLS=(); SEL_EXTERNAL=(); SEL_FAMILIES=()
IFS=',' read -r -a TOKENS <<< "$ONLY"
for token in "${TOKENS[@]}"; do
  token="${token// /}"
  [[ -n "$token" ]] || continue
  name="$(resolve_token "$token")" || { err "Unknown selection '$token'. Run ./setup.sh --list"; exit 1; }
  kind=family
  for t in "${TOOL_IDS[@]}"; do [[ "$t" == "$name" ]] && kind=tool; done
  for t in ${EXT_IDS[@]+"${EXT_IDS[@]}"}; do [[ "$t" == "$name" && "$kind" == family ]] && kind=external; done
  case "$kind" in
    tool)     SEL_TOOLS+=("$name") ;;
    external) SEL_EXTERNAL+=("$name") ;;
    *)        SEL_FAMILIES+=("$name") ;;
  esac
done

join() { local IFS=,; echo "$*"; }

if (( ${#SEL_TOOLS[@]} == 0 && ${#SEL_EXTERNAL[@]} == 0 && ${#SEL_FAMILIES[@]} == 0 )); then
  info "Nothing selected."
  exit 0
fi

echo
info "Selected tools:    ${SEL_TOOLS[*]:-none}"
info "Selected families: ${SEL_FAMILIES[*]:-none}"
info "Selected external:  ${SEL_EXTERNAL[*]:-none}"

if (( ASSUME_YES == 0 && DRY_RUN == 0 )); then
  if [[ -t 0 ]]; then
    read -rp "Proceed? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { info "Cancelled."; exit 0; }
  else
    err "Confirmation required without a terminal: pass --yes."
    exit 2
  fi
fi

# --- delegate ----------------------------------------------------------------

common=(); (( DRY_RUN == 1 )) && common+=(--dry-run)

if (( ${#SEL_TOOLS[@]} > 0 )); then
  tool_args=(--only "$(join "${SEL_TOOLS[@]}")" --yes ${common[@]+"${common[@]}"})
  [[ -n "$PRESET" ]] && tool_args+=(--preset "$PRESET")
  info "Tools"
  "$BOOTSTRAP" install ${tool_args[@]+"${tool_args[@]}"}
  for t in "${SEL_TOOLS[@]}"; do
    [[ "$t" == "gentle-ai" ]] && { "$BOOTSTRAP" configure ${tool_args[@]+"${tool_args[@]}"}; break; }
  done
fi

if (( ${#SEL_FAMILIES[@]} > 0 )); then
  skill_args=(--family "$(join "${SEL_FAMILIES[@]}")" ${common[@]+"${common[@]}"})
  [[ -t 0 ]] || skill_args+=(--no-prompt)
  info "Skills"
  "$INSTALLER" ${skill_args[@]+"${skill_args[@]}"}
fi

if (( ${#SEL_EXTERNAL[@]} > 0 )); then
  info "External skills"
  "$EXTERNAL" install --only "$(join "${SEL_EXTERNAL[@]}")" --yes ${common[@]+"${common[@]}"}
fi

info "Done."
