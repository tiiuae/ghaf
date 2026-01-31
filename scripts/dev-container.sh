#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Development Container
# Creates and manages a Docker container for Ghaf development on Ubuntu hosts.
#
# Usage: dev-container.sh [OPTIONS] [COMMAND]
#
# Commands:
#   create    Create a new development container (default)
#   start     Start an existing container
#   stop      Stop a running container
#   shell     Open a shell in the container
#   ssh       SSH into the container
#   remove    Remove the container
#   status    Show container status
#
# Options:
#   -n, --name NAME       Container name (default: ghaf-dev)
#   -m, --mount PATH      Mount local directory into container (default: current directory)
#   -c, --cpus NUM        Number of CPUs (default: 4)
#   -r, --ram SIZE        Memory limit (default: 8g)
#   -p, --ssh-port PORT   SSH port on host (default: 2222)
#   -P, --password PASS   SSH password (default: ghaf)
#   -i, --image IMAGE     Docker image (default: ubuntu:24.04)
#   --no-setup            Skip running ubuntu-setup.sh in container
#   --accept              Auto-accept all prompts during setup
#   -h, --help            Show this help message

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="ghaf-dev"
MOUNT_PATH=""
CPUS="4"
RAM="8g"
SSH_PORT="2222"
PASSWORD="ghaf"
IMAGE="ubuntu:24.04"
RUN_SETUP="true"
ACCEPT_ALL="false"
COMMAND="create"

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
Ghaf Development Container

Creates and manages a Docker container for Ghaf development on Ubuntu hosts.

USAGE:
    dev-container.sh [OPTIONS] [COMMAND]

COMMANDS:
    create    Create a new development container (default)
    start     Start an existing container
    stop      Stop a running container
    shell     Open a shell in the container
    ssh       SSH into the container
    remove    Remove the container
    status    Show container status

OPTIONS:
    -n, --name NAME       Container name (default: ghaf-dev)
    -m, --mount PATH      Mount local directory into container
                          (default: current directory if it contains flake.nix)
    -c, --cpus NUM        Number of CPUs (default: 4)
    -r, --ram SIZE        Memory limit (default: 8g)
    -p, --ssh-port PORT   SSH port on host (default: 2222)
    -P, --password PASS   SSH password for 'ghaf' user (default: ghaf)
    -i, --image IMAGE     Docker image (default: ubuntu:24.04)
    --no-setup            Skip running ubuntu-setup.sh in container
    --accept              Auto-accept all prompts during setup
    -h, --help            Show this help message

EXAMPLES:
    # Create container with defaults, mounting current directory
    dev-container.sh create

    # Create container with custom settings
    dev-container.sh -n my-ghaf -c 8 -r 16g -m ~/projects/ghaf create

    # SSH into running container
    dev-container.sh ssh

    # Open interactive shell
    dev-container.sh shell

    # Stop and remove container
    dev-container.sh stop
    dev-container.sh remove

NOTES:
    - The container runs with --privileged for Nix sandbox support
    - SSH is available on the specified port (default: 2222)
    - User 'ghaf' has sudo access without password
    - The Ghaf binary cache is pre-configured
EOF
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    # shellcheck disable=SC2016
    echo '  Ubuntu: sudo apt install docker.io && sudo usermod -aG docker $USER'
    exit 1
  fi

  if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running or you don't have permission."
    echo "  Try: sudo systemctl start docker"
    # shellcheck disable=SC2016
    echo '  Or add yourself to docker group: sudo usermod -aG docker $USER'
    exit 1
  fi
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

# =============================================================================
# Container Operations
# =============================================================================

create_container() {
  check_docker

  if container_exists; then
    log_warning "Container '${CONTAINER_NAME}' already exists."
    read -r -p "Remove and recreate? [y/N] " response
    if [[ $response =~ ^[Yy]$ ]]; then
      remove_container
    else
      log_info "Use 'dev-container.sh start' to start the existing container."
      exit 0
    fi
  fi

  # Determine mount path
  if [[ -z $MOUNT_PATH ]]; then
    if [[ -f "./flake.nix" ]]; then
      MOUNT_PATH="$(pwd)"
      log_info "Auto-detected Ghaf directory: ${MOUNT_PATH}"
    fi
  fi

  log_info "Creating container '${CONTAINER_NAME}'..."
  log_info "  Image: ${IMAGE}"
  log_info "  CPUs: ${CPUS}"
  log_info "  RAM: ${RAM}"
  log_info "  SSH Port: ${SSH_PORT}"
  log_info "  Password: ${PASSWORD}"
  [[ -n $MOUNT_PATH ]] && log_info "  Mount: ${MOUNT_PATH} -> /home/ghaf/ghaf"

  # Build docker run command
  local docker_args=(
    run -d
    --name "${CONTAINER_NAME}"
    --hostname "${CONTAINER_NAME}"
    --privileged
    --cpus "${CPUS}"
    --memory "${RAM}"
    -p "${SSH_PORT}:22"
    --network host
  )

  # Add mount if specified
  if [[ -n $MOUNT_PATH ]]; then
    docker_args+=(-v "${MOUNT_PATH}:/home/ghaf/ghaf")
  fi

  docker_args+=("${IMAGE}" sleep infinity)

  # Create container
  docker "${docker_args[@]}" >/dev/null

  log_success "Container created."

  # Initial setup
  log_info "Setting up container environment..."

  # Install basic packages and create user
  docker exec "${CONTAINER_NAME}" bash -c '
        apt-get update -qq
        apt-get install -y -qq curl git sudo openssh-server xz-utils > /dev/null 2>&1

        # Create ghaf user with sudo
        useradd -m -s /bin/bash ghaf 2>/dev/null || true
        echo "ghaf ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ghaf
        chmod 0440 /etc/sudoers.d/ghaf
    '

  # Set password
  docker exec "${CONTAINER_NAME}" bash -c "echo 'ghaf:${PASSWORD}' | chpasswd"

  # Configure and start SSH
  docker exec "${CONTAINER_NAME}" bash -c '
        mkdir -p /run/sshd
        sed -i "s/#PasswordAuthentication yes/PasswordAuthentication yes/" /etc/ssh/sshd_config
        sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
        /usr/sbin/sshd
    '

  log_success "SSH configured on port ${SSH_PORT}"
  log_info "  Connect with: ssh -p ${SSH_PORT} ghaf@localhost"

  # Run setup script if requested
  if [[ $RUN_SETUP == "true" ]]; then
    if [[ -f "${SCRIPT_DIR}/ubuntu-setup.sh" ]]; then
      log_info "Running Ghaf setup script..."

      # Copy setup script to container
      docker cp "${SCRIPT_DIR}/ubuntu-setup.sh" "${CONTAINER_NAME}:/tmp/ubuntu-setup.sh"
      docker exec "${CONTAINER_NAME}" chmod +x /tmp/ubuntu-setup.sh

      # Run setup as ghaf user
      local setup_args=""
      [[ $ACCEPT_ALL == "true" ]] && setup_args="--accept"

      docker exec -u ghaf "${CONTAINER_NAME}" bash -c "
                /tmp/ubuntu-setup.sh ${setup_args}
            " || {
        log_warning "Setup script had some issues, but container is usable."
      }

      log_success "Setup complete!"
    else
      log_warning "ubuntu-setup.sh not found in ${SCRIPT_DIR}"
      log_info "You can run it manually after connecting to the container."
    fi
  fi

  echo ""
  log_success "Container '${CONTAINER_NAME}' is ready!"
  echo ""
  echo "  SSH:    ssh -p ${SSH_PORT} ghaf@localhost"
  echo "  Shell:  dev-container.sh shell"
  echo "  Stop:   dev-container.sh stop"
  echo ""
  if [[ -n $MOUNT_PATH ]]; then
    echo "  Ghaf directory mounted at: /home/ghaf/ghaf"
    echo "  After connecting: cd /home/ghaf/ghaf && direnv allow"
  fi
}

start_container() {
  check_docker

  if ! container_exists; then
    log_error "Container '${CONTAINER_NAME}' does not exist."
    log_info "Create it with: dev-container.sh create"
    exit 1
  fi

  if container_running; then
    log_info "Container '${CONTAINER_NAME}' is already running."
    exit 0
  fi

  log_info "Starting container '${CONTAINER_NAME}'..."
  docker start "${CONTAINER_NAME}" >/dev/null

  # Restart SSH
  docker exec "${CONTAINER_NAME}" bash -c '/usr/sbin/sshd 2>/dev/null || true'

  log_success "Container started."
  echo "  SSH: ssh -p ${SSH_PORT} ghaf@localhost"
}

stop_container() {
  check_docker

  if ! container_exists; then
    log_error "Container '${CONTAINER_NAME}' does not exist."
    exit 1
  fi

  if ! container_running; then
    log_info "Container '${CONTAINER_NAME}' is not running."
    exit 0
  fi

  log_info "Stopping container '${CONTAINER_NAME}'..."
  docker stop "${CONTAINER_NAME}" >/dev/null
  log_success "Container stopped."
}

remove_container() {
  check_docker

  if ! container_exists; then
    log_info "Container '${CONTAINER_NAME}' does not exist."
    exit 0
  fi

  if container_running; then
    log_info "Stopping container first..."
    docker stop "${CONTAINER_NAME}" >/dev/null
  fi

  log_info "Removing container '${CONTAINER_NAME}'..."
  docker rm "${CONTAINER_NAME}" >/dev/null
  log_success "Container removed."
}

open_shell() {
  check_docker

  if ! container_running; then
    log_error "Container '${CONTAINER_NAME}' is not running."
    log_info "Start it with: dev-container.sh start"
    exit 1
  fi

  log_info "Opening shell in container '${CONTAINER_NAME}'..."
  docker exec -it -u ghaf -w /home/ghaf "${CONTAINER_NAME}" bash -l
}

ssh_container() {
  if ! container_running; then
    log_error "Container '${CONTAINER_NAME}' is not running."
    log_info "Start it with: dev-container.sh start"
    exit 1
  fi

  log_info "Connecting via SSH..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${SSH_PORT}" ghaf@localhost
}

show_status() {
  check_docker

  echo "Container: ${CONTAINER_NAME}"
  echo ""

  if ! container_exists; then
    echo "  Status: Does not exist"
    return
  fi

  if container_running; then
    echo "  Status: Running"

    # Get container info
    local info
    info=$(docker inspect "${CONTAINER_NAME}" 2>/dev/null)

    local cpus mem
    cpus=$(echo "$info" | jq -r '.[0].HostConfig.NanoCpus // 0' | awk '{printf "%.0f", $1/1000000000}')
    mem=$(echo "$info" | jq -r '.[0].HostConfig.Memory // 0' | numfmt --to=iec 2>/dev/null || echo "unlimited")

    echo "  CPUs: ${cpus:-unlimited}"
    echo "  Memory: ${mem}"
    echo "  SSH Port: ${SSH_PORT}"

    # Check if Nix is installed
    if docker exec "${CONTAINER_NAME}" which nix &>/dev/null; then
      local nix_version
      nix_version=$(docker exec "${CONTAINER_NAME}" nix --version 2>/dev/null || echo "unknown")
      echo "  Nix: ${nix_version}"
    else
      echo "  Nix: Not installed"
    fi
  else
    echo "  Status: Stopped"
  fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -n | --name)
      CONTAINER_NAME="$2"
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
    -p | --ssh-port)
      SSH_PORT="$2"
      shift 2
      ;;
    -P | --password)
      PASSWORD="$2"
      shift 2
      ;;
    -i | --image)
      IMAGE="$2"
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
    create | start | stop | shell | ssh | remove | status)
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
  create) create_container ;;
  start) start_container ;;
  stop) stop_container ;;
  shell) open_shell ;;
  ssh) ssh_container ;;
  remove) remove_container ;;
  status) show_status ;;
  *)
    log_error "Unknown command: $COMMAND"
    exit 1
    ;;
  esac
}

main "$@"
