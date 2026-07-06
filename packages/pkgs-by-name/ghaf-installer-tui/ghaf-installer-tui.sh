#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf-installer-tui.sh — interactive TUI for the Ghaf installer
# ghaf-installer-lib.sh is prepended by the Nix build and must be present.

# =============================================================================
# GLOBAL STATE VARIABLES
# =============================================================================

DEVICE_NAME=""
ENCRYPTED_INSTALL=false
SECUREBOOT_INSTALL=false
WIPE_ONLY=false

ENABLED_STATUS="$(gum style --bold --foreground="$COLOR_SUCCESS" "Enabled")"
DISABLED_STATUS="$(gum style --bold --foreground="$COLOR_ERROR" "Disabled")"

declare -A OPTION_TRUE_LABEL=(
  ["ENCRYPTED_INSTALL"]="$(gum join "Encryption:  " "$ENABLED_STATUS" " (deferred — activated on first boot)")"
  ["SECUREBOOT_INSTALL"]="$(gum join "Secure Boot: " "$ENABLED_STATUS")"
)
declare -A OPTION_FALSE_LABEL=(
  ["ENCRYPTED_INSTALL"]="$(gum join "Encryption:  " "$DISABLED_STATUS")"
  ["SECUREBOOT_INSTALL"]="$(gum join "Secure Boot: " "$DISABLED_STATUS")"
)

option_label() {
  local varname="$1"
  if ${!varname}; then
    echo "${OPTION_TRUE_LABEL[$varname]}"
  else
    echo "${OPTION_FALSE_LABEL[$varname]}"
  fi
}

action_label() {
  $WIPE_ONLY && echo "Erase disk" || echo "Ghaf installation"
}

show_install_summary() {
  local -a summary=(
    "Action:      $(action_label)"
    "Disk:        $DEVICE_NAME"
  )
  if ! $WIPE_ONLY; then
    summary+=("$(option_label ENCRYPTED_INSTALL)")
    summary+=("$(option_label SECUREBOOT_INSTALL)")
  fi
  show_section "${summary[@]}"
}

# =============================================================================
# STATE MACHINE
# =============================================================================

CURRENT_STATE=""

declare -A STATE_FUNCTIONS=(
  ["WELCOME"]="screen_welcome"
  ["DEVICE_SELECT"]="screen_device_select"
  ["INSTALL_OPTIONS"]="screen_install_options"
  ["CONFIRM"]="screen_confirm"
  ["RUNNING"]="screen_running"
  ["COMPLETE"]="screen_complete"
)

# shellcheck disable=SC2329
goto_state() {
  CURRENT_STATE="$1"
  debug "Transitioning to state: $CURRENT_STATE"
}

start_state_machine() {
  CURRENT_STATE="WELCOME"
  debug "Starting state machine at: $CURRENT_STATE"
  while [[ $CURRENT_STATE != "EXIT" ]]; do
    local screen_func="${STATE_FUNCTIONS[$CURRENT_STATE]}"
    if [[ -n $screen_func ]]; then
      $screen_func
    else
      debug "Error: No function defined for state: $CURRENT_STATE"
      break
    fi
  done
  debug "State machine exited with state: $CURRENT_STATE"
}

# shellcheck disable=SC2329
run_step() {
  local err_msg="$1"
  shift
  if ! "$@"; then
    show_error "$err_msg"
    wait_for_user
    goto_state "WELCOME"
    return 1
  fi
}

# =============================================================================
# SCREEN FUNCTIONS
# =============================================================================

# shellcheck disable=SC2329
screen_welcome() {
  clear
  show_header "Ghaf Installer"

  if [[ -z ${IMG_PATH:-} ]]; then
    show_error "IMG_PATH environment variable is not set."
    show_error "Please set IMG_PATH to the directory containing the .raw.zst image."
    wait_for_user
    goto_state "EXIT"
    return
  fi

  local choice
  choice=$(prompt_choice "What would you like to do?" \
    "Install Ghaf" \
    "Erase a disk" \
    "Shutdown" \
    "Reboot" \
    "Reboot into system firmware" \
    "Exit") || return

  case "$choice" in
  "Install Ghaf")
    WIPE_ONLY=false
    goto_state "DEVICE_SELECT"
    ;;
  "Erase a disk")
    WIPE_ONLY=true
    ENCRYPTED_INSTALL=false
    SECUREBOOT_INSTALL=false
    goto_state "DEVICE_SELECT"
    ;;
  "Shutdown")
    if prompt_confirm "Shut down the system?" "Yes" "Cancel" "false"; then
      systemctl poweroff
      exit 0
    fi
    ;;
  "Reboot")
    if prompt_confirm "Reboot the system?" "Yes" "Cancel" "false"; then
      systemctl reboot
      exit 0
    fi
    ;;
  "Reboot into system firmware")
    if prompt_confirm "Reboot into system firmware?" "Yes" "Cancel" "false"; then
      systemctl reboot --firmware-setup
      exit 0
    fi
    ;;
  "Exit")
    if prompt_confirm "Exit the installer and drop to shell?" "Yes, exit" "Cancel"; then
      goto_state "EXIT"
    fi
    ;;
  esac
}

# shellcheck disable=SC2329
screen_device_select() {
  clear
  if $WIPE_ONLY; then
    show_header "Select Disk to Erase"
  else
    show_header "Select Installation Disk"
  fi

  local -a device_choices=()
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    device_choices+=("$line")
  done < <(list_block_devices)

  if [[ ${#device_choices[@]} -eq 0 ]]; then
    show_error "No suitable disks found." "Make sure your installation disk is connected and try again."
    wait_for_user
    goto_state "WELCOME"
    return
  fi

  device_choices+=("Back")

  local choice
  choice=$(prompt_choice "Select a disk:" "${device_choices[@]}") || return

  if [[ $choice == "Back" ]]; then
    goto_state "WELCOME"
    return
  fi

  # Extract device path (first field of the choice line)
  DEVICE_NAME=$(awk '{print $1}' <<<"$choice")

  if ! validate_device "$DEVICE_NAME"; then
    wait_for_user
    goto_state "DEVICE_SELECT"
    return
  fi

  if is_removable "$DEVICE_NAME"; then
    echo ""
    show_warning "Warning: $DEVICE_NAME appears to be a removable drive." "This may be the installation media. Installing here will destroy the installer and may cause corruption."
    if ! prompt_confirm "Continue anyway?" "Yes, use this disk" "No, choose another disk" "false"; then
      goto_state "DEVICE_SELECT"
      return
    fi
  fi

  if $WIPE_ONLY; then
    goto_state "CONFIRM"
  else
    goto_state "INSTALL_OPTIONS"
  fi
}

# shellcheck disable=SC2329
screen_install_options() {
  # Reset to clean slate
  SECUREBOOT_INSTALL=false
  ENCRYPTED_INSTALL=false

  update_install_options() {
    clear
    show_header "Installation Options"
    show_install_summary
    echo ""

    show_info "Configure optional features:"
    echo ""
  }

  update_install_options

  if prompt_confirm "Enable disk encryption? (activated on first boot)" "Yes, enable" "No, skip" "false"; then
    ENCRYPTED_INSTALL=true
    update_install_options
  fi

  if system_in_setup_mode; then
    if prompt_confirm "Enroll Secure Boot keys?" "Yes, enroll" "No, skip" "false"; then
      SECUREBOOT_INSTALL=true
      update_install_options
    fi
  else
    show_warning "Secure Boot key enrollment is not available: firmware is not in Setup Mode." \
      "To enable Setup Mode, enter your firmware settings and clear the Secure Boot keys, then restart the installer."
    echo ""

    if prompt_confirm "Would you like to reboot into system firmware right now?" "Yes" "No, skip" "false"; then
      systemctl reboot --firmware-setup
      exit 0
    fi
  fi

  goto_state "CONFIRM"
}

# shellcheck disable=SC2329
screen_confirm() {
  clear

  if $WIPE_ONLY; then
    show_header "Confirm Disk Erasure"
  else
    show_header "Confirm Installation"
  fi

  show_info "Summary"
  show_install_summary

  if ! $WIPE_ONLY; then
    echo ""
    show_info "Ready to install"
  fi

  echo ""
  show_warning "WARNING: All data on $DEVICE_NAME will be permanently erased!"
  echo ""
  local confirm_msg="Erase $DEVICE_NAME and begin installation?"
  $WIPE_ONLY && confirm_msg="Erase $DEVICE_NAME ?"

  if ! prompt_confirm "$confirm_msg" "Yes" "Cancel" "false"; then
    goto_state "WELCOME"
    return
  fi

  if ! prompt_confirm "All data on $DEVICE_NAME will be permanently destroyed. Are you sure?" "Yes, I am sure" "Cancel" "false"; then
    goto_state "WELCOME"
    return
  fi

  goto_state "RUNNING"
}

# shellcheck disable=SC2329
screen_running() {
  clear
  if $WIPE_ONLY; then
    show_header "Erasing Disk"
  else
    show_header "Installing Ghaf"
  fi

  # Step: wipe
  run_step "Failed to erase disk." do_wipe "$DEVICE_NAME" || return 0

  if $WIPE_ONLY; then
    goto_state "COMPLETE"
    return
  fi

  show_success "Disk erased successfully."
  echo ""

  # Step: write image
  show_info "Starting installation..." ""
  run_step "Installation failed." do_install_image "$DEVICE_NAME" || return 0
  show_success "Ghaf installed successfully."
  echo ""

  # Step: deferred encryption marker
  if $ENCRYPTED_INSTALL; then
    show_info "Configuring disk encryption..."
    run_step "Failed to configure disk encryption." do_setup_encryption "$DEVICE_NAME" || return 0
    show_success "Encryption configured — you will be prompted to set a passphrase on first boot."
    echo ""
  fi

  # Step: Secure Boot enrollment
  if $SECUREBOOT_INSTALL; then
    show_info "Enrolling Secure Boot keys..."
    run_step "Secure Boot enrollment failed." do_enroll_secureboot "$DEVICE_NAME" || return 0
    show_success "Secure Boot keys enrolled."
    echo ""
  fi

  goto_state "COMPLETE"
}

# shellcheck disable=SC2329
screen_complete() {
  clear
  local action_complete
  if $WIPE_ONLY; then
    action_complete="Disk Erased"
  else
    action_complete="Installation Complete"
  fi
  show_header "${action_complete}"

  if $WIPE_ONLY; then
    show_success "Disk '$DEVICE_NAME' has been erased successfully."
    echo ""
    wait_for_user "Press any key to return to the main menu..."
    goto_state "WELCOME"
    return
  fi

  show_success "Ghaf has been installed successfully."
  echo ""

  local -a summary=("Disk:   $DEVICE_NAME")
  $ENCRYPTED_INSTALL && summary+=("You will be prompted to set an encryption passphrase on first boot.")
  $SECUREBOOT_INSTALL && summary+=("Secure Boot keys have been enrolled.")
  show_section "${summary[@]}"

  echo ""

  local next_action
  next_action=$(prompt_choice "What would you like to do next?" \
    "Reboot (recommended)" \
    "Shutdown" \
    "Return to the main menu") || return

  case "$next_action" in
  "Reboot (recommended)")
    if prompt_confirm "Reboot the system?" "Yes" "Cancel" "true"; then
      show_warning "Remove the installer media before the device reboots."
      echo ""
      local delay=10
      trap - TERM
      systemctl reboot --when="+${delay}s" >/dev/null 2>&1
      countdown "Rebooting in" $delay
      exit 0
    fi
    ;;
  "Shutdown")
    if prompt_confirm "Shut down the system?" "Yes" "Cancel" "false"; then
      systemctl poweroff
      exit 0
    fi
    ;;
  "Return to the main menu")
    goto_state "WELCOME"
    ;;
  esac
}

# =============================================================================
# MAIN ENTRY
# =============================================================================

main() {
  export TERM=linux

  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must run with root privileges." >&2
    exit 1
  fi

  if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    cat <<EOF
Usage: $(basename "$0") [-h]

Ghaf installation TUI. Set IMG_PATH to the directory containing the
.raw.zst image before running.

For non-interactive/scripted installs use ghaf-installer instead.

Options:
  -h, --help    Show this help message and exit
EOF
    exit 0
  fi

  cleanup_and_exit() {
    local exit_code=$?
    debug "Running cleanup with exit code: $exit_code"
    exit $exit_code
  }

  trap cleanup_and_exit EXIT
  trap '' INT TERM

  brightnessctl set 100% >/dev/null 2>&1 || true

  start_state_machine
}

main "$@"
