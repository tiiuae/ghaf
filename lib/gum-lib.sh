#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf GUM shell library - colour scheme and UI helpers shared across scripts.
# Prepend to any writeShellApplication text via builtins.readFile:
#
#   text = builtins.readFile ../../../lib/gum-lib.sh + ''
#     # your script here
#   '';
#
# The caller is responsible for adding pkgs.gum to runtimeInputs.

# ---------------------------------------------------------------------------
# Colour scheme
# ---------------------------------------------------------------------------
GHAF_PRIMARY="#5AC379"
GHAF_SECONDARY="#3D8252"
GHAF_ERROR="#FF0000"

COLOR_SUCCESS="$GHAF_PRIMARY"
COLOR_ERROR="$GHAF_ERROR"
COLOR_WARNING="#FFA500"
COLOR_INFO="#FFFFFF"

# ---------------------------------------------------------------------------
# Spacing constants
# ---------------------------------------------------------------------------
SPACING_MARGIN="0 0"
SPACING_PADDING="0 1"
SPACING_HEADER_BOTTOM="1 0"
SPACING_INFO_BOTTOM="0"

# ---------------------------------------------------------------------------
# Header styling constants
# ---------------------------------------------------------------------------
HEADER_WIDTH=70
HEADER_HEIGHT=3
HEADER_PADDING="1 2"

# ---------------------------------------------------------------------------
# GUM environment - applied to all gum subcommands
# ---------------------------------------------------------------------------
export GUM_INPUT_CURSOR_FOREGROUND="$GHAF_PRIMARY"
export GUM_INPUT_HEADER_FOREGROUND="$GHAF_PRIMARY"
export GUM_INPUT_PROMPT_FOREGROUND="$COLOR_INFO"
export GUM_CHOOSE_HEADER_FOREGROUND="$GHAF_PRIMARY"
export GUM_CHOOSE_CURSOR_FOREGROUND="$GHAF_PRIMARY"
export GUM_CHOOSE_SELECTED_FOREGROUND="$GHAF_SECONDARY"
export GUM_SPIN_SPINNER_FOREGROUND="$COLOR_INFO"
export GUM_SPIN_SPINNER_BACKGROUND=
export GUM_SPIN_TITLE_FOREGROUND="$COLOR_INFO"
export GUM_CONFIRM_SELECTED_BACKGROUND="$GHAF_PRIMARY"
export GUM_CONFIRM_SELECTED_FOREGROUND="#000000"
export GUM_CONFIRM_PROMPT_FOREGROUND="$GHAF_PRIMARY"

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329
show_header() {
  gum style \
    --foreground="$GHAF_PRIMARY" \
    --bold \
    --border="double" \
    --border-foreground="$GHAF_SECONDARY" \
    --align="center" \
    --width="$HEADER_WIDTH" \
    --height="$HEADER_HEIGHT" \
    --margin="$SPACING_HEADER_BOTTOM" \
    --padding="$HEADER_PADDING" \
    -- "$@"
}

# shellcheck disable=SC2329
show_section() {
  gum style \
    --border="rounded" \
    --border-foreground="$GHAF_SECONDARY" \
    --padding="$SPACING_PADDING" \
    --margin="$SPACING_MARGIN" \
    -- "$@"
}

# shellcheck disable=SC2329
show_success() { gum style --foreground="$COLOR_SUCCESS" -- "$@"; }
# shellcheck disable=SC2329
show_error() { gum style --foreground="$COLOR_ERROR" -- "$@"; }
# shellcheck disable=SC2329
show_info() { gum style --foreground="$COLOR_INFO" --margin="$SPACING_INFO_BOTTOM" -- "$@"; }
# shellcheck disable=SC2329
show_warning() { gum style --foreground="$COLOR_WARNING" -- "$@"; }

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329
prompt_confirm() {
  local message="$1"
  local affirmative="${2:-Yes}"
  local negative="${3}"
  local default=${4:-true}
  gum confirm \
    --affirmative="$affirmative" \
    --negative="$negative" \
    --default="$default" \
    "$message"
}

# shellcheck disable=SC2329
prompt_choice() {
  local header="$1"
  shift
  header="$(gum style --bold "$header")"
  gum choose \
    --header="$header" \
    -- "$@"
}

# shellcheck disable=SC2329
prompt_input() {
  local header="${1:-}"
  local placeholder="${2:-}"
  gum input \
    --header "$header" \
    --placeholder "$placeholder" \
    --prompt.bold
}

# shellcheck disable=SC2329
prompt_password() {
  local header="${1:-}"
  local placeholder="${2:-}"
  gum input \
    --password \
    --header "$header" \
    --placeholder "$placeholder" \
    --prompt.bold
}

# shellcheck disable=SC2329
wait_for_user() {
  local message="${1:-Press any key to continue...}"
  echo ""
  gum style --foreground="$COLOR_INFO" --italic "$message"
  read -n 1 -s -r
}

# shellcheck disable=SC2329
run_spin() {
  local show_status=true
  local -a gum_flags=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -q | --quiet) show_status=false ;;
    --show-output) gum_flags+=(--show-output) ;;
    --show-error) gum_flags+=(--show-error) ;;
    --show-stdout) gum_flags+=(--show-stdout) ;;
    --show-stderr) gum_flags+=(--show-stderr) ;;
    *) break ;;
    esac
    shift
  done
  local title="$1"
  shift
  gum spin \
    --spinner="line" \
    --title="$title" \
    "${gum_flags[@]}" \
    -- "$@"
  local exit_code=$?
  if $show_status; then
    if [[ $exit_code -eq 0 ]]; then
      show_success "$title Done!"
    else
      show_error "$title Failed!"
    fi
  fi
  return $exit_code
}

# shellcheck disable=SC2329
show_progress() { run_spin "$@"; }

# shellcheck disable=SC2329
countdown() {
  local message="$1"
  local delay="${2:-5}"
  local suffix
  for ((i = delay; i > 0; i--)); do
    ((i == 1)) && suffix="second..." || suffix="seconds..."
    printf "\033[2K\r%s" "$(gum style --foreground="$COLOR_WARNING" "$message $i $suffix")"
    sleep 1.1
  done
  printf "\033[2K\r"
}
