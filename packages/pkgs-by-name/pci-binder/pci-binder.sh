#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# INIT
declare -A PCI_DATA          # PCI data; associative array with key = PCI bus ID, value = driver name
declare -a PCI_INPUT_DEVICES # Array to hold input PCI device identifiers
declare ACTION_FLAG          # Action flag to determine whether to bind or unbind
declare STATE_DIR=""
declare AUTO_DETECT=0 # Detect this guest's passthrough devices instead of taking ids

# Base PCI classes ghaf assigns to vfio-pci for passthrough (see extraVfioPciIds in the
# hardware definitions): 0x02 network, 0x03 display, 0x04 multimedia.
readonly PASSTHROUGH_CLASSES=(2 3 4)
# Virtio. A guest's own virtio-net is class 0x02 and must never be unbound.
readonly VIRTIO_VENDOR="0x1af4"

# Helpers for clearer logging
TAG="pci-binder"
log_error_exit() {
  systemd-cat -p err -t "$TAG" <<<"$1"
  usage
  exit 1
}
log_warning() {
  systemd-cat -p warning -t "$TAG" <<<"$1"
}
log_notice() {
  systemd-cat -p notice -t "$TAG" <<<"$1"
}
log_info() {
  systemd-cat -p info -t "$TAG" <<<"$1"
}
log_debug() {
  systemd-cat -p debug -t "$TAG" <<<"$1"
}

usage() {
  if [[ $- == *i* ]]; then
    cat <<EOF
Usage: $(basename "$0") [(-s|--state-dir) <state_directory>] (unbind (--auto | <pci_device> ...) | bind)

Options:
  unbind
    Unbind the drivers from the specified PCI devices. Requires at least one <pci_device>
    argument, or --auto.

  --auto
    Detect the passthrough devices in this guest instead of being given their ids: every PCI
    device whose base class is one of the classes ghaf assigns to vfio-pci (0x02 network,
    0x03 display, 0x04 multimedia), excluding virtio (0x1af4) so the guest's own virtio-net
    is never unbound. For boards whose passthrough is resolved dynamically by vhotplug there
    is no static id list to pass. Detecting nothing is success, not an error -- a guest with
    no passthrough PCI devices has nothing to unbind.

  bind
    Bind the previously unbound PCI devices to their drivers.

  -s | --state-dir <state_directory>
    Specify the directory to store the PCI device state file (unset by default).
    NOTE: Storing the state is only necessary if you want to manually run unbind and rebind.
    In this case, you must use the same state directory directory path for both commands.

  <pci_device>
    Specify the PCI device identifiers to bind or unbind. The format is "vendor_id:device_id" in hex
    without leading "0x", e.g., 8086:a7a1. Multiple devices can be specified by separating them with spaces.

Examples:
  $(basename "$0") --state-dir /run/pci-binding unbind 8086:a7a1 8086:51f1
  $(basename "$0") --state-dir /run/pci-binding bind

  $(basename "$0") unbind 8086:a7a1 8086:51f1
  $(basename "$0") unbind --auto
EOF
  fi
}

# Function to backup PCI_DATA to a JSON file
write_pci_data() {
  if [ -z "$STATE_DIR" ]; then
    # Ignore if no state directory is set
    return 0
  fi
  local args=()
  for key in "${!PCI_DATA[@]}"; do
    args+=(--arg "$key" "${PCI_DATA[$key]}")
  done
  jq -n '$ARGS.named' --args "${args[@]}" >"$STATE_DIR/pci-devices"
}

# Function to restore the PCI_DATA from a JSON file
read_pci_data() {
  if [ -z "$STATE_DIR" ]; then
    log_error_exit "No state directory set, cannot read PCI data."
  fi
  if [ ! -f "$STATE_DIR/pci-devices" ]; then
    log_error_exit "PCI device file not found: $STATE_DIR/pci-devices"
  fi
  while IFS=$'\t' read -r key value; do
    PCI_DATA["$key"]="$value"
  done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$STATE_DIR/pci-devices")
}

parse_input() {

  # Check that we are running in a guest with root privileges
  local guest
  guest=$(systemd-detect-virt)
  if [[ $guest == "none" ]]; then
    log_error_exit "This script should only be run in a guest, not the host. Detected guest type: $guest"
  fi
  if [[ $EUID -ne 0 ]]; then
    log_error_exit "Please run with root privileges."
  fi

  # Check minimum number of arguments
  if [[ $# -lt 1 ]]; then
    log_error_exit "Insufficient arguments provided."
  fi

  # Validate and/or create the state directory (optional input 1)
  case "$1" in
  -s | --state-dir)
    STATE_DIR="$2"
    if [[ ! -d $STATE_DIR ]]; then
      log_info "Creating state directory '$STATE_DIR' ..."
      if ! mkdir -p "$STATE_DIR"; then
        log_error_exit "Failed to create state directory '$STATE_DIR'."
      fi
    fi
    shift 2
    ;;
  *)
    log_info "Running without state directory, automatic rebind anticipated..."
    ;;
  esac

  # Validate the action flag (input 1/2)
  ACTION_FLAG="$1"
  if [[ $ACTION_FLAG != "bind" && $ACTION_FLAG != "unbind" ]]; then
    log_error_exit "The action argument must be 'bind' or 'unbind'. Received: '$ACTION_FLAG'"
  fi
  if [[ $ACTION_FLAG == "bind" && -z $STATE_DIR ]]; then
    log_error_exit "The action 'bind' requires a state directory input."
  fi
  shift 1

  # Validate the array of device identifiers
  if [[ $ACTION_FLAG == "unbind" ]]; then

    if [[ ${1:-} == "--auto" ]]; then
      AUTO_DETECT=1
      shift 1
      if [[ $# -ne 0 ]]; then
        log_error_exit "--auto takes no device identifiers, but received: $*"
      fi
      return 0
    fi

    if [[ $# -eq 0 ]]; then
      log_error_exit "No device identifiers found."
    fi

    # Check all remaining parameters (the hex pair pci identifiers)
    local pattern="^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$"
    read -r -a input_args <<<"$@"
    for arg in "${input_args[@]}"; do
      if [[ $arg =~ $pattern ]]; then
        PCI_INPUT_DEVICES+=("$arg")
      else
        log_error_exit "PCI identifier ('$arg') does not match the required '{vendor_id}:{product_id}' format."
      fi
    done
  else
    if [[ $# -ne 0 ]]; then
      log_warning "No device identifiers expected for 'bind' action, but received: $*"
    fi
  fi
}

# Detect this guest's passthrough devices by class, for boards where vhotplug resolves
# passthrough dynamically and there is no static id list to pass.
detect_passthrough_devices() {
  local -n out=$1
  local device_path class vendor base wanted

  for device_path in /sys/bus/pci/devices/*; do
    [ -r "$device_path/class" ] && [ -r "$device_path/vendor" ] || continue
    class=$(cat "$device_path/class")
    vendor=$(cat "$device_path/vendor")

    [[ $vendor == "$VIRTIO_VENDOR" ]] && continue

    base=$(((class >> 16) & 0xff))
    for wanted in "${PASSTHROUGH_CLASSES[@]}"; do
      if [[ $base -eq $wanted ]]; then
        # No driver bound means nothing to unbind, not an error.
        if [ -e "$device_path/driver" ]; then
          out+=("$device_path")
        else
          log_debug "No driver bound to '$(basename "$device_path")', skipping..."
        fi
        break
      fi
    done
  done
}

# Function to determine suitable devices and populate the PCI_DATA array
init_pci_unbind() {

  # Add all PCI devices that are passed through to this guest
  declare -a pci_device_paths=()

  if [[ $AUTO_DETECT -eq 1 ]]; then
    detect_passthrough_devices pci_device_paths
    if [ ${#pci_device_paths[@]} -eq 0 ]; then
      # A guest with no passthrough PCI devices -- an app VM, say -- has nothing to do.
      log_info "No passthrough PCI devices detected, nothing to unbind."
      return 0
    fi
  else
    for device in "${PCI_INPUT_DEVICES[@]}"; do
      if guest_pci_id=$(lspci -n | grep -i "${device}" | awk '{print $1}'); then
        pci_device_paths+=("/sys/bus/pci/devices/0000:$guest_pci_id")
      else
        log_debug "No matching PCI device '${device}', skipping..."
      fi
    done
    if [ ${#pci_device_paths[@]} -eq 0 ]; then
      log_error_exit "No PCI devices found to unbind."
    fi
  fi
  log_info "Detected PCI device paths: ${pci_device_paths[*]}"

  # Initialize the PCI_DATA associative array
  for device_path in "${pci_device_paths[@]}"; do
    if [ ! -d "$device_path" ]; then
      log_warning "PCI device path '$device_path' not found, skipping..."
    fi

    # Extract the PCI device ID from the path
    local pci_id
    pci_id=$(basename "$device_path")
    if [ -z "$pci_id" ]; then
      log_warning "Could not determine ID of the PCI device based path: $device_path"
      continue
    fi

    # Determine the driver for the PCI device
    local driver
    driver=$(basename "$(readlink "$device_path/driver")")
    if [ -z "$driver" ]; then
      log_warning "Could not determine driver for the PCI device: $pci_id"
      continue
    fi

    # Add the PCI device ID and driver to PCI_DATA
    PCI_DATA["$pci_id"]="$driver"
  done
}

# Function to unbind PCI drivers
unbind_pci_drivers() {

  log_info "Attempting to unbind PCI devices..."

  # Find devices and drivers (PCI_DATA)
  init_pci_unbind

  # (Optional) Write the PCI_DATA to a state file
  write_pci_data

  for pci_id in "${!PCI_DATA[@]}"; do
    local driver
    driver="${PCI_DATA["$pci_id"]}"
    log_notice "Unbinding driver '$driver' from device '$pci_id'..."
    echo "$pci_id" >"/sys/bus/pci/drivers/$driver/unbind"
  done

  log_info "PCI devices unbound successfully."
}

# Function to rebind PCI drivers
bind_pci_drivers() {

  if [ ! -f "$STATE_DIR/pci-devices" ]; then
    log_warning "No PCI device state file found, did you run unbind first and provided a state directory?"
    log_error_exit "PCI device state file not found: $STATE_DIR/pci-devices"
  fi

  log_info "Attempting to bind PCI devices..."

  # Read the PCI_DATA from the state file
  read_pci_data

  # Check if pci_data is empty
  if [ "${#PCI_DATA[@]}" -eq 0 ]; then
    log_warning "No PCI devices found in state file found: $STATE_DIR/pci-devices"
    log_error_exit "No PCI devices found to rebind."
  fi

  for pci_id in "${!PCI_DATA[@]}"; do

    # Rebind the driver to the device
    local driver
    driver="${PCI_DATA["$pci_id"]}"
    log_notice "Rebinding driver '$driver' to device '$pci_id'..."
    echo "$pci_id" >"/sys/bus/pci/drivers/$driver/bind"
  done

  # Remove the state file after rebinding
  rm -f "$STATE_DIR/pci-devices"
  log_info "PCI device drivers bound successfully."
}

main() {
  parse_input "$@"
  case "$ACTION_FLAG" in
  unbind)
    unbind_pci_drivers
    ;;
  bind)
    bind_pci_drivers
    ;;
  *)
    echo "You managed to somehow reach unreachable code!"
    usage
    ;;
  esac
  exit 0
}

# Main
main "$@"
