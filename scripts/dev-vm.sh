#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Development VM
# Creates and manages a QEMU/KVM virtual machine for Ghaf development on Ubuntu hosts.
#
# Usage: dev-vm.sh [OPTIONS] [COMMAND]
#
# Commands:
#   create    Create a new development VM (default)
#   start     Start an existing VM
#   stop      Stop a running VM
#   ssh       SSH into the VM
#   remove    Remove the VM
#   status    Show VM status
#
# Options:
#   -n, --name NAME       VM name (default: ghaf-dev-vm)
#   -m, --mount PATH      Mount local directory via 9p (default: none)
#   -c, --cpus NUM        Number of CPUs (default: 4)
#   -r, --ram SIZE        Memory in GB (default: 16)
#   -d, --disk SIZE       Disk size in GB (default: 120)
#   -p, --ssh-port PORT   SSH port on host (default: 2223)
#   -P, --password PASS   SSH password (default: ghaf)
#   -D, --vm-dir DIR      Directory for VM files (default: ~/ghaf-vms)
#   --no-setup            Skip running ubuntu-setup.sh in VM
#   --accept              Auto-accept all prompts during setup
#   -h, --help            Show this help message

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="ghaf-dev-vm"
MOUNT_PATH=""
CPUS="4"
RAM="16"
DISK="120"
SSH_PORT="2223"
PASSWORD="ghaf"
VM_DIR="${HOME}/ghaf-vms"
RUN_SETUP="true"
ACCEPT_ALL="false"
COMMAND="create"

UBUNTU_VERSION="24.04"
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✔${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✖${NC} $1"; }

show_help() {
  cat <<'EOF'
Ghaf Development VM

Creates and manages a QEMU/KVM virtual machine for Ghaf development on Ubuntu hosts.

USAGE:
    dev-vm.sh [OPTIONS] [COMMAND]

COMMANDS:
    create    Create a new development VM (default)
    start     Start an existing VM
    stop      Stop a running VM (graceful shutdown via SSH)
    ssh       SSH into the VM
    remove    Remove the VM and all its files
    status    Show VM status

OPTIONS:
    -n, --name NAME       VM name (default: ghaf-dev-vm)
    -m, --mount PATH      Mount local directory via virtio-9p
                          (will be available at /mnt/host in VM)
    -c, --cpus NUM        Number of CPUs (default: 4)
    -r, --ram SIZE        Memory in GB (default: 16)
    -d, --disk SIZE       Disk size in GB (default: 120)
    -p, --ssh-port PORT   SSH port on host (default: 2223)
    -P, --password PASS   SSH password for 'ghaf' user (default: ghaf)
    -D, --vm-dir DIR      Directory for VM files (default: ~/ghaf-vms)
    --no-setup            Skip running ubuntu-setup.sh in VM
    --accept              Auto-accept all prompts during setup
    -h, --help            Show this help message

EXAMPLES:
    # Create VM with defaults (16GB RAM, 120GB disk)
    dev-vm.sh create

    # Create VM with custom settings for large builds
    dev-vm.sh -n my-ghaf -c 8 -r 32 -d 200 create

    # Create VM and mount local ghaf directory
    dev-vm.sh -m ~/projects/ghaf create

    # SSH into running VM
    dev-vm.sh ssh

    # Stop VM gracefully
    dev-vm.sh stop

REQUIREMENTS:
    - QEMU/KVM (install with: sudo apt install qemu-system-x86 qemu-utils)
    - KVM support (check with: kvm-ok or ls /dev/kvm)
    - cloud-image-utils (install with: sudo apt install cloud-image-utils)

DISK SPACE NOTES:
    - Documentation build: ~20GB
    - x86_64 targets: ~50GB
    - ARM64/Jetson targets with QEMU emulation: 100GB+

    For ARM64 builds, 120GB+ disk space is recommended.
EOF
}

check_dependencies() {
  local missing=()

  # Check for QEMU
  if ! command -v qemu-system-x86_64 &>/dev/null; then
    missing+=("qemu-system-x86")
  fi

  # Check for qemu-img
  if ! command -v qemu-img &>/dev/null; then
    missing+=("qemu-utils")
  fi

  # Check for cloud-localds (from cloud-image-utils)
  if ! command -v cloud-localds &>/dev/null; then
    missing+=("cloud-image-utils")
  fi

  # Check for KVM support
  if [[ ! -e /dev/kvm ]]; then
    log_warning "KVM is not available. VM will run slowly without hardware virtualization."
    log_info "Check if virtualization is enabled in BIOS/UEFI."
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing dependencies: ${missing[*]}"
    echo ""
    echo "Install with:"
    echo "  sudo apt install ${missing[*]}"
    exit 1
  fi
}

get_vm_dir() {
  echo "${VM_DIR}/${VM_NAME}"
}

vm_exists() {
  [[ -f "$(get_vm_dir)/disk.qcow2" ]]
}

get_vm_pid() {
  local pidfile
  pidfile="$(get_vm_dir)/vm.pid"
  if [[ -f $pidfile ]]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return 0
    fi
  fi
  return 1
}

vm_running() {
  get_vm_pid >/dev/null 2>&1
}

wait_for_ssh() {
  local timeout=120
  local elapsed=0

  log_info "Waiting for VM to boot (timeout: ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -p "${SSH_PORT}" ghaf@localhost exit 2>/dev/null; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
  done

  echo ""
  return 1
}

# =============================================================================
# VM Operations
# =============================================================================

create_vm() {
  check_dependencies

  local vm_dir
  vm_dir="$(get_vm_dir)"

  if vm_exists; then
    log_warning "VM '${VM_NAME}' already exists at ${vm_dir}"
    read -r -p "Remove and recreate? [y/N] " response
    if [[ $response =~ ^[Yy]$ ]]; then
      remove_vm
    else
      log_info "Use 'dev-vm.sh start' to start the existing VM."
      exit 0
    fi
  fi

  log_info "Creating VM '${VM_NAME}'..."
  log_info "  CPUs: ${CPUS}"
  log_info "  RAM: ${RAM}GB"
  log_info "  Disk: ${DISK}GB"
  log_info "  SSH Port: ${SSH_PORT}"
  log_info "  Password: ${PASSWORD}"
  log_info "  Directory: ${vm_dir}"
  [[ -n $MOUNT_PATH ]] && log_info "  Mount: ${MOUNT_PATH} -> /mnt/host"

  # Create VM directory
  mkdir -p "$vm_dir"

  # Download Ubuntu cloud image if needed
  local base_image="${VM_DIR}/ubuntu-${UBUNTU_VERSION}-cloudimg.img"
  if [[ ! -f $base_image ]]; then
    log_info "Downloading Ubuntu ${UBUNTU_VERSION} cloud image..."
    curl -L -o "$base_image" "$UBUNTU_IMAGE_URL"
    log_success "Downloaded cloud image."
  fi

  # Create disk from base image
  log_info "Creating ${DISK}GB disk..."
  qemu-img create -f qcow2 -F qcow2 -b "$base_image" "${vm_dir}/disk.qcow2" "${DISK}G"

  # Create cloud-init configuration
  log_info "Creating cloud-init configuration..."

  cat >"${vm_dir}/user-data" <<EOF
#cloud-config
users:
  - name: ghaf
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: ${PASSWORD}
ssh_pwauth: true
chpasswd:
  expire: false
package_update: true
packages:
  - curl
  - git
  - xz-utils
  - openssh-server
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
runcmd:
  - systemctl enable ssh
  - systemctl start ssh
EOF

  cat >"${vm_dir}/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

  # Create cloud-init ISO
  cloud-localds "${vm_dir}/seed.iso" "${vm_dir}/user-data" "${vm_dir}/meta-data"

  # Save VM configuration
  cat >"${vm_dir}/config" <<EOF
CPUS=${CPUS}
RAM=${RAM}
SSH_PORT=${SSH_PORT}
MOUNT_PATH=${MOUNT_PATH}
EOF

  log_success "VM created."

  # Start the VM
  start_vm

  # Wait for SSH
  if ! wait_for_ssh; then
    log_error "Timed out waiting for VM to boot."
    log_info "Check VM status with: dev-vm.sh status"
    exit 1
  fi

  echo ""
  log_success "VM is running and SSH is available!"

  # Run setup script if requested
  if [[ $RUN_SETUP == "true" ]]; then
    if [[ -f "${SCRIPT_DIR}/ubuntu-setup.sh" ]]; then
      log_info "Running Ghaf setup script in VM..."

      # Copy setup script to VM
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -P "${SSH_PORT}" "${SCRIPT_DIR}/ubuntu-setup.sh" ghaf@localhost:/tmp/

      # Run setup as ghaf user
      local setup_args=""
      [[ $ACCEPT_ALL == "true" ]] && setup_args="--accept"

      # Use sshpass if available, otherwise prompt
      if command -v sshpass &>/dev/null; then
        sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null -p "${SSH_PORT}" ghaf@localhost \
          "chmod +x /tmp/ubuntu-setup.sh && /tmp/ubuntu-setup.sh ${setup_args}" || {
          log_warning "Setup script had some issues, but VM is usable."
        }
      else
        log_info "Running setup (you may need to enter password: ${PASSWORD})..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -p "${SSH_PORT}" ghaf@localhost \
          "chmod +x /tmp/ubuntu-setup.sh && /tmp/ubuntu-setup.sh ${setup_args}" || {
          log_warning "Setup script had some issues, but VM is usable."
        }
      fi

      log_success "Setup complete!"
    else
      log_warning "ubuntu-setup.sh not found in ${SCRIPT_DIR}"
      log_info "You can run it manually after connecting to the VM."
    fi
  fi

  echo ""
  log_success "VM '${VM_NAME}' is ready!"
  echo ""
  echo "  SSH:    ssh -p ${SSH_PORT} ghaf@localhost"
  echo "  Stop:   dev-vm.sh stop"
  echo "  Status: dev-vm.sh status"
  echo ""
  if [[ -n $MOUNT_PATH ]]; then
    echo "  Host directory will be available at: /mnt/host"
    echo "  (Note: 9p mount requires manual mounting in VM)"
  fi
}

start_vm() {
  check_dependencies

  local vm_dir
  vm_dir="$(get_vm_dir)"

  if ! vm_exists; then
    log_error "VM '${VM_NAME}' does not exist."
    log_info "Create it with: dev-vm.sh create"
    exit 1
  fi

  if vm_running; then
    log_info "VM '${VM_NAME}' is already running."
    exit 0
  fi

  # Load configuration
  if [[ -f "${vm_dir}/config" ]]; then
    # shellcheck source=/dev/null
    source "${vm_dir}/config"
  fi

  log_info "Starting VM '${VM_NAME}'..."

  # Build QEMU command
  local qemu_args=(
    qemu-system-x86_64
    -m "${RAM}G"
    -smp "${CPUS}"
    -cpu host
    -hda "${vm_dir}/disk.qcow2"
    -cdrom "${vm_dir}/seed.iso"
    -net nic
    -net "user,hostfwd=tcp::${SSH_PORT}-:22"
    -display none
    -serial null
    -pidfile "${vm_dir}/vm.pid"
    -daemonize
  )

  # Enable KVM if available
  if [[ -e /dev/kvm ]]; then
    qemu_args+=(-enable-kvm)
  else
    log_warning "Running without KVM (slow)"
  fi

  # Add 9p mount if specified
  if [[ -n $MOUNT_PATH ]]; then
    qemu_args+=(
      -virtfs "local,path=${MOUNT_PATH},mount_tag=host_share,security_model=passthrough,id=host_share"
    )
  fi

  # Start QEMU
  "${qemu_args[@]}" 2>/dev/null || {
    # If daemonize fails, try without it for better error messages
    log_warning "Failed to start in background, trying foreground..."
    qemu_args=("${qemu_args[@]//-daemonize/}")
    "${qemu_args[@]}" &
    echo $! >"${vm_dir}/vm.pid"
    disown
  }

  sleep 2

  if vm_running; then
    log_success "VM started."
    log_info "SSH will be available on port ${SSH_PORT} after boot completes."
  else
    log_error "Failed to start VM."
    exit 1
  fi
}

stop_vm() {
  local vm_dir
  vm_dir="$(get_vm_dir)"

  if ! vm_running; then
    log_info "VM '${VM_NAME}' is not running."
    return 0
  fi

  log_info "Stopping VM '${VM_NAME}'..."

  # Try graceful shutdown via SSH first
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -p "${SSH_PORT}" ghaf@localhost \
    "sudo shutdown -h now" 2>/dev/null; then
    log_info "Shutdown command sent. Waiting..."

    # Wait for VM to stop
    local timeout=60
    local elapsed=0
    while vm_running && [[ $elapsed -lt $timeout ]]; do
      sleep 2
      elapsed=$((elapsed + 2))
    done
  fi

  # Force kill if still running
  if vm_running; then
    log_warning "VM didn't stop gracefully. Force killing..."
    local pid
    pid=$(get_vm_pid)
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "${vm_dir}/vm.pid"
  log_success "VM stopped."
}

remove_vm() {
  local vm_dir
  vm_dir="$(get_vm_dir)"

  if ! vm_exists; then
    log_info "VM '${VM_NAME}' does not exist."
    return 0
  fi

  if vm_running; then
    stop_vm
  fi

  log_info "Removing VM '${VM_NAME}'..."
  rm -rf "$vm_dir"
  log_success "VM removed."
}

ssh_vm() {
  if ! vm_running; then
    log_error "VM '${VM_NAME}' is not running."
    log_info "Start it with: dev-vm.sh start"
    exit 1
  fi

  log_info "Connecting via SSH..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${SSH_PORT}" ghaf@localhost
}

show_status() {
  local vm_dir
  vm_dir="$(get_vm_dir)"

  echo "VM: ${VM_NAME}"
  echo "Directory: ${vm_dir}"
  echo ""

  if ! vm_exists; then
    echo "  Status: Does not exist"
    return
  fi

  # Load configuration
  if [[ -f "${vm_dir}/config" ]]; then
    # shellcheck source=/dev/null
    source "${vm_dir}/config"
  fi

  if vm_running; then
    local pid
    pid=$(get_vm_pid)
    echo "  Status: Running (PID: ${pid})"
  else
    echo "  Status: Stopped"
  fi

  echo "  CPUs: ${CPUS}"
  echo "  RAM: ${RAM}GB"
  echo "  SSH Port: ${SSH_PORT}"

  # Get disk size
  if [[ -f "${vm_dir}/disk.qcow2" ]]; then
    local disk_info
    disk_info=$(qemu-img info "${vm_dir}/disk.qcow2" 2>/dev/null | grep "virtual size" | cut -d'(' -f2 | cut -d' ' -f1)
    echo "  Disk: ${disk_info:-unknown} bytes"
  fi

  [[ -n ${MOUNT_PATH:-} ]] && echo "  Mount: ${MOUNT_PATH} -> /mnt/host"

  # Check Nix if running
  if vm_running; then
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -p "${SSH_PORT}" ghaf@localhost \
      "which nix" &>/dev/null 2>&1; then
      local nix_version
      nix_version=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "${SSH_PORT}" ghaf@localhost "nix --version" 2>/dev/null || echo "unknown")
      echo "  Nix: ${nix_version}"
    fi
  fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -n | --name)
      VM_NAME="$2"
      shift 2
      ;;
    -m | --mount)
      MOUNT_PATH="$(realpath "$2")"
      shift 2
      ;;
    -c | --cpus)
      CPUS="$2"
      shift 2
      ;;
    -r | --ram)
      RAM="$2"
      shift 2
      ;;
    -d | --disk)
      DISK="$2"
      shift 2
      ;;
    -p | --ssh-port)
      SSH_PORT="$2"
      shift 2
      ;;
    -P | --password)
      PASSWORD="$2"
      shift 2
      ;;
    -D | --vm-dir)
      VM_DIR="$2"
      shift 2
      ;;
    --no-setup)
      RUN_SETUP="false"
      shift
      ;;
    --accept)
      ACCEPT_ALL="true"
      shift
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    create | start | stop | ssh | remove | status)
      COMMAND="$1"
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      echo "Use --help for usage information."
      exit 1
      ;;
    esac
  done
}

# =============================================================================
# Main
# =============================================================================

main() {
  parse_args "$@"

  case "$COMMAND" in
  create) create_vm ;;
  start) start_vm ;;
  stop) stop_vm ;;
  ssh) ssh_vm ;;
  remove) remove_vm ;;
  status) show_status ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 1
    ;;
  esac
}

main "$@"
