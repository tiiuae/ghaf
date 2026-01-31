#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ubuntu/Debian Development Environment Setup for Ghaf Framework
#
# This script sets up a complete Nix-based development environment for Ghaf
# on Ubuntu/Debian systems. It installs Nix, configures binary caches,
# sets up direnv for automatic environment activation, and optionally
# configures VSCode.
#
# Usage:
#   ./ubuntu-setup.sh [OPTIONS]
#
# Options:
#   --accept    Accept all prompts automatically (non-interactive mode)
#   --help      Show this help message
#   --uninstall Remove Nix and related configurations
#
# For more information, see:
#   https://ghaf.tii.ae/ghaf/dev/ref/ubuntu-development-setup/

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHAF_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Flags
ACCEPT_ALL=false
UNINSTALL=false

# Nix configuration
NIX_CONF_DIR="${HOME}/.config/nix"
NIX_CONF_FILE="${NIX_CONF_DIR}/nix.conf"
DIRENV_CONF_DIR="${HOME}/.config/direnv"
DIRENV_CONF_FILE="${DIRENV_CONF_DIR}/direnvrc"

# Ghaf binary cache configuration
GHAF_CACHE_URL="https://ghaf-dev.cachix.org"
GHAF_CACHE_KEY="ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
NIXOS_CACHE_URL="https://cache.nixos.org"
NIXOS_CACHE_KEY="cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
  echo -e "\n${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}  $1${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}\n"
}

print_step() {
  echo -e "${CYAN}▶${NC} $1"
}

print_success() {
  echo -e "${GREEN}✔${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
  echo -e "${RED}✘${NC} $1"
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# Prompt user for confirmation
# Returns 0 if accepted, 1 if declined
confirm() {
  local prompt="$1"
  local default="${2:-n}"

  if [[ ${ACCEPT_ALL} == "true" ]]; then
    print_info "Auto-accepting: ${prompt}"
    return 0
  fi

  local yn_prompt
  if [[ ${default} == "y" ]]; then
    yn_prompt="[Y/n]"
  else
    yn_prompt="[y/N]"
  fi

  while true; do
    echo -en "${YELLOW}?${NC} ${prompt} ${yn_prompt} "
    read -r response
    response=${response:-${default}}
    case "${response}" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) echo "Please answer yes or no." ;;
    esac
  done
}

# Run a command with sudo, prompting if not in accept mode
run_sudo() {
  local description="$1"
  shift
  local cmd=("$@")

  echo ""
  print_step "The following command requires elevated privileges:"
  echo -e "   ${BOLD}sudo ${cmd[*]}${NC}"
  echo ""
  print_info "Reason: ${description}"
  echo ""

  if confirm "Execute this command with sudo?"; then
    sudo "${cmd[@]}"
    return $?
  else
    print_warning "Skipped: ${description}"
    return 1
  fi
}

# Check if a command exists
command_exists() {
  command -v "$1" &>/dev/null
}

# Detect shell configuration file
detect_shell_config() {
  local shell_name
  shell_name=$(basename "${SHELL}")

  case "${shell_name}" in
  bash)
    if [[ -f "${HOME}/.bashrc" ]]; then
      echo "${HOME}/.bashrc"
    elif [[ -f "${HOME}/.bash_profile" ]]; then
      echo "${HOME}/.bash_profile"
    else
      echo "${HOME}/.bashrc"
    fi
    ;;
  zsh)
    echo "${HOME}/.zshrc"
    ;;
  fish)
    echo "${HOME}/.config/fish/config.fish"
    ;;
  *)
    echo "${HOME}/.profile"
    ;;
  esac
}

# Get shell hook command for direnv
get_direnv_hook() {
  local shell_name
  shell_name=$(basename "${SHELL}")

  case "${shell_name}" in
  bash)
    # shellcheck disable=SC2016
    echo 'eval "$(direnv hook bash)"'
    ;;
  zsh)
    # shellcheck disable=SC2016
    echo 'eval "$(direnv hook zsh)"'
    ;;
  fish)
    echo 'direnv hook fish | source'
    ;;
  *)
    # shellcheck disable=SC2016
    echo 'eval "$(direnv hook bash)"'
    ;;
  esac
}

# =============================================================================
# Checks
# =============================================================================

check_os() {
  print_step "Checking operating system..."

  if [[ ! -f /etc/os-release ]]; then
    print_error "Cannot detect operating system. /etc/os-release not found."
    exit 1
  fi

  # shellcheck source=/dev/null
  source /etc/os-release

  if [[ ${ID} != "ubuntu" && ${ID} != "debian" && ${ID_LIKE:-} != *"debian"* && ${ID_LIKE:-} != *"ubuntu"* ]]; then
    print_error "This script is designed for Ubuntu/Debian systems."
    print_info "Detected: ${PRETTY_NAME:-Unknown}"
    exit 1
  fi

  print_success "Detected: ${PRETTY_NAME}"

  # Warn about Ubuntu 24.04 AppArmor
  if [[ ${ID} == "ubuntu" && ${VERSION_ID:-} == "24.04" ]]; then
    echo ""
    print_warning "Ubuntu 24.04 detected!"
    print_info "Ubuntu 24.04 has stricter AppArmor policies that may affect Nix sandboxing."
    print_info "If you encounter build issues, the script will provide troubleshooting steps."
    echo ""
  fi
}

check_architecture() {
  print_step "Checking system architecture..."

  local arch
  arch=$(uname -m)

  case "${arch}" in
  x86_64 | amd64)
    print_success "Architecture: x86_64 (fully supported)"
    ;;
  aarch64 | arm64)
    print_success "Architecture: aarch64 (supported)"
    ;;
  *)
    print_warning "Architecture: ${arch} (may have limited support)"
    ;;
  esac
}

check_existing_nix() {
  print_step "Checking for existing Nix installation..."

  if [[ -d /nix ]]; then
    if command_exists nix; then
      local nix_version
      nix_version=$(nix --version 2>/dev/null || echo "unknown")
      print_info "Nix is already installed: ${nix_version}"

      if ! confirm "Nix is already installed. Continue with configuration only?"; then
        print_info "Exiting. Your existing Nix installation was not modified."
        exit 0
      fi
      return 1 # Skip installation
    else
      print_warning "Found /nix directory but nix command not available."
      print_info "You may have a broken installation. Consider running with --uninstall first."
    fi
  else
    print_info "No existing Nix installation found."
  fi
  return 0 # Proceed with installation
}

# =============================================================================
# Installation Functions
# =============================================================================

install_system_dependencies() {
  print_header "Installing System Dependencies"

  local packages=(
    curl
    git
    xz-utils
  )

  # Check which packages need installation
  local to_install=()
  for pkg in "${packages[@]}"; do
    if ! dpkg -l "${pkg}" &>/dev/null; then
      to_install+=("${pkg}")
    fi
  done

  if [[ ${#to_install[@]} -eq 0 ]]; then
    print_success "All required system packages are already installed."
    return 0
  fi

  print_info "The following packages will be installed: ${to_install[*]}"

  if run_sudo "Install required system packages for Nix" \
    apt-get update; then
    if run_sudo "Install packages: ${to_install[*]}" \
      apt-get install -y "${to_install[@]}"; then
      print_success "System dependencies installed successfully."
    else
      print_error "Failed to install system dependencies."
      return 1
    fi
  else
    print_error "Failed to update package lists."
    return 1
  fi
}

install_nix() {
  print_header "Installing Nix Package Manager"

  print_info "This script uses the Determinate Systems Nix Installer."
  print_info "Benefits:"
  print_info "  • Flakes enabled by default"
  print_info "  • Clean uninstall support"
  print_info "  • Multi-user mode (more secure)"
  print_info "  • Better enterprise support"
  echo ""
  print_info "Installer URL: https://install.determinate.systems/nix"
  echo ""

  if ! confirm "Install Nix using the Determinate Systems installer?" "y"; then
    print_warning "Skipping Nix installation."
    print_info "You can install Nix manually later. See documentation for details."
    return 1
  fi

  print_step "Downloading and running Nix installer..."

  # Build installer arguments
  local installer_args=("install")

  # Check if systemd is available (containers often don't have it)
  if ! pidof systemd &>/dev/null && ! [[ -d /run/systemd/system ]]; then
    print_warning "Systemd not detected (possibly running in a container)."
    print_info "Using --init none mode for non-systemd environments."
    installer_args+=("linux" "--init" "none")
  fi

  if [[ ${ACCEPT_ALL} == "true" ]]; then
    installer_args+=("--no-confirm")
  fi

  # Run the installer
  if curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- "${installer_args[@]}"; then
    print_success "Nix installed successfully!"

    # Source Nix environment for current shell
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
      # shellcheck source=/dev/null
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
      # Single-user mode fallback (--init none)
      # shellcheck source=/dev/null
      . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
    fi

    return 0
  else
    print_error "Nix installation failed."
    print_info "Check the installer output above for details."
    return 1
  fi
}

configure_nix() {
  print_header "Configuring Nix"

  print_step "Setting up Nix configuration directory..."
  mkdir -p "${NIX_CONF_DIR}"

  # Check if config already exists
  local config_exists=false
  if [[ -f ${NIX_CONF_FILE} ]]; then
    config_exists=true
    print_info "Existing nix.conf found at ${NIX_CONF_FILE}"
  fi

  # Prepare configuration content
  local nix_config
  nix_config="# Ghaf development configuration
# Added by ubuntu-setup.sh on $(date -Iseconds)

# Enable flakes and new nix command
experimental-features = nix-command flakes

# Binary caches for faster builds
substituters = ${GHAF_CACHE_URL} ${NIXOS_CACHE_URL}
trusted-public-keys = ${GHAF_CACHE_KEY} ${NIXOS_CACHE_KEY}

# Trust the Ghaf binary cache
extra-trusted-substituters = ${GHAF_CACHE_URL}

# Recommended settings
keep-outputs = true
keep-derivations = true
"

  if [[ ${config_exists} == "true" ]]; then
    # Check if Ghaf cache is already configured
    if grep -q "ghaf-dev.cachix.org" "${NIX_CONF_FILE}" 2>/dev/null; then
      print_success "Ghaf binary cache already configured in nix.conf"
    else
      print_info "Adding Ghaf configuration to existing nix.conf..."
      echo ""
      echo "The following will be appended to ${NIX_CONF_FILE}:"
      echo "----------------------------------------"
      echo "${nix_config}"
      echo "----------------------------------------"

      if confirm "Append Ghaf configuration to nix.conf?"; then
        echo "" >>"${NIX_CONF_FILE}"
        echo "${nix_config}" >>"${NIX_CONF_FILE}"
        print_success "Configuration appended to nix.conf"
      else
        print_warning "Skipped nix.conf configuration."
        print_info "You'll need to configure binary caches manually for faster builds."
      fi
    fi
  else
    print_info "Creating new nix.conf with Ghaf configuration..."
    echo "${nix_config}" >"${NIX_CONF_FILE}"
    print_success "Created ${NIX_CONF_FILE}"
  fi

  # Restart nix-daemon if running
  if systemctl is-active --quiet nix-daemon 2>/dev/null; then
    print_info "Restarting nix-daemon to apply configuration changes..."
    if run_sudo "Restart nix-daemon service" systemctl restart nix-daemon; then
      print_success "nix-daemon restarted."
    fi
  fi

  # Configure trusted users in system nix.conf for multi-user mode
  local sys_nix_conf="/etc/nix/nix.conf"
  if [[ -f ${sys_nix_conf} ]]; then
    local current_user
    current_user=$(whoami)
    if ! grep -q "trusted-users.*${current_user}" "${sys_nix_conf}" 2>/dev/null; then
      print_info "Adding ${current_user} to trusted-users for binary cache access..."
      if run_sudo "Add ${current_user} to trusted-users in /etc/nix/nix.conf" \
        bash -c "echo 'trusted-users = root ${current_user}' >> ${sys_nix_conf}"; then
        print_success "Added ${current_user} to trusted-users."
        # Restart nix-daemon to apply changes
        if systemctl is-active --quiet nix-daemon 2>/dev/null; then
          if run_sudo "Restart nix-daemon to apply trusted-users" systemctl restart nix-daemon; then
            print_success "nix-daemon restarted."
          fi
        fi
      fi
    else
      print_success "User ${current_user} already in trusted-users."
    fi
  fi
}

install_direnv() {
  print_header "Installing direnv and nix-direnv"

  print_info "direnv automatically loads your Nix development environment"
  print_info "when you enter the Ghaf project directory."
  echo ""

  # Check if direnv is already installed
  if command_exists direnv; then
    local direnv_version
    direnv_version=$(direnv version 2>/dev/null || echo "unknown")
    print_info "direnv is already installed: v${direnv_version}"
  else
    print_step "Installing direnv..."

    # Try to install via Nix first (preferred)
    if command_exists nix; then
      print_info "Installing direnv via Nix..."
      if nix profile install nixpkgs#direnv; then
        print_success "direnv installed via Nix."
      else
        print_warning "Failed to install direnv via Nix. Trying apt..."
        if run_sudo "Install direnv via apt" apt-get install -y direnv; then
          print_success "direnv installed via apt."
        else
          print_error "Failed to install direnv."
          return 1
        fi
      fi
    else
      # Fallback to apt
      if run_sudo "Install direnv via apt" apt-get install -y direnv; then
        print_success "direnv installed via apt."
      else
        print_error "Failed to install direnv."
        return 1
      fi
    fi
  fi

  # Install nix-direnv
  print_step "Installing nix-direnv..."
  if command_exists nix; then
    if nix profile install nixpkgs#nix-direnv; then
      print_success "nix-direnv installed."
    else
      print_warning "Failed to install nix-direnv. direnv will still work but may be slower."
    fi
  fi

  # Configure direnv
  print_step "Configuring direnv..."
  mkdir -p "${DIRENV_CONF_DIR}"

  local direnv_config
  direnv_config="# Ghaf development configuration
# Added by ubuntu-setup.sh on $(date -Iseconds)

# Use nix-direnv for better caching and performance
if [ -f \"\${HOME}/.nix-profile/share/nix-direnv/direnvrc\" ]; then
    source \"\${HOME}/.nix-profile/share/nix-direnv/direnvrc\"
elif [ -f \"/nix/var/nix/profiles/default/share/nix-direnv/direnvrc\" ]; then
    source \"/nix/var/nix/profiles/default/share/nix-direnv/direnvrc\"
fi

# Increase timeout for Nix operations
export DIRENV_WARN_TIMEOUT=60s
"

  if [[ -f ${DIRENV_CONF_FILE} ]]; then
    if grep -q "nix-direnv" "${DIRENV_CONF_FILE}" 2>/dev/null; then
      print_success "nix-direnv already configured in direnvrc"
    else
      print_info "Adding nix-direnv configuration to existing direnvrc..."
      if confirm "Append nix-direnv configuration to direnvrc?"; then
        echo "" >>"${DIRENV_CONF_FILE}"
        echo "${direnv_config}" >>"${DIRENV_CONF_FILE}"
        print_success "Configuration appended to direnvrc"
      fi
    fi
  else
    echo "${direnv_config}" >"${DIRENV_CONF_FILE}"
    print_success "Created ${DIRENV_CONF_FILE}"
  fi

  # Add shell hook
  print_step "Configuring shell integration..."
  local shell_config
  shell_config=$(detect_shell_config)
  local hook_cmd
  hook_cmd=$(get_direnv_hook)

  if [[ -f ${shell_config} ]] && grep -q "direnv hook" "${shell_config}" 2>/dev/null; then
    print_success "direnv hook already configured in ${shell_config}"
  else
    print_info "Adding direnv hook to ${shell_config}..."
    echo ""
    echo "The following line will be added to ${shell_config}:"
    echo "  ${hook_cmd}"
    echo ""

    if confirm "Add direnv hook to your shell configuration?"; then
      {
        echo ""
        echo "# direnv hook - added by Ghaf ubuntu-setup.sh"
        echo "${hook_cmd}"
      } >>"${shell_config}"
      print_success "direnv hook added to ${shell_config}"
      print_info "Run 'source ${shell_config}' or restart your shell to activate."
    else
      print_warning "Skipped shell hook configuration."
      print_info "Add the following to your shell configuration manually:"
      echo "  ${hook_cmd}"
    fi
  fi
}

setup_binfmt() {
  print_header "Setting Up Cross-Architecture Support (Optional)"

  print_info "binfmt with QEMU allows building AArch64 (ARM64) targets via emulation."
  print_info "Note: Cross-compilation (-from-x86_64 targets) is faster and preferred."
  print_info "binfmt is useful when cross-compilation targets aren't available."
  echo ""

  if ! confirm "Install QEMU user-static for AArch64 emulation?"; then
    print_info "Skipping binfmt setup. You can still use -from-x86_64 targets."
    return 0
  fi

  # Check if already installed
  if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    print_success "QEMU AArch64 binfmt already configured."
  else
    print_step "Installing QEMU user-static..."
    if run_sudo "Install QEMU user-static and binfmt-support" \
      apt-get install -y qemu-user-static binfmt-support; then
      print_success "QEMU user-static installed."

      # Try to import and enable AArch64 support
      # First check if the format is in the database
      if update-binfmts --display qemu-aarch64 &>/dev/null; then
        if run_sudo "Enable AArch64 binfmt support" \
          update-binfmts --enable qemu-aarch64; then
          print_success "AArch64 binfmt enabled."
        fi
      else
        # Try importing from package files
        if [[ -f /usr/share/binfmts/qemu-aarch64 ]]; then
          if run_sudo "Import and enable AArch64 binfmt" \
            update-binfmts --import qemu-aarch64; then
            print_success "AArch64 binfmt imported and enabled."
          fi
        else
          print_info "binfmt format will be available after reboot or systemd restart."
          print_info "On systems with systemd: sudo systemctl restart binfmt-support"
        fi
      fi
    else
      print_warning "Failed to install QEMU user-static."
      print_info "You can still build using -from-x86_64 cross-compilation targets."
      return 0
    fi
  fi

  # Configure Nix to use aarch64-linux as an extra platform
  # This tells Nix it can build aarch64 packages via binfmt emulation
  local nix_custom_conf="/etc/nix/nix.custom.conf"
  if [[ -f $nix_custom_conf ]]; then
    if ! grep -q "extra-platforms.*aarch64-linux" "$nix_custom_conf" 2>/dev/null; then
      print_step "Configuring Nix for AArch64 builds..."
      if run_sudo "Add aarch64-linux to Nix extra-platforms" \
        bash -c "echo 'extra-platforms = aarch64-linux i686-linux' >> $nix_custom_conf"; then
        print_success "Nix configured for AArch64 emulation."

        # Restart Nix daemon if running
        if systemctl is-active --quiet nix-daemon 2>/dev/null; then
          if run_sudo "Restart Nix daemon" systemctl restart nix-daemon; then
            print_success "Nix daemon restarted."
          fi
        fi
      fi
    else
      print_success "Nix already configured for AArch64."
    fi
  else
    print_warning "Nix custom config not found. Configure extra-platforms manually."
    print_info "Add 'extra-platforms = aarch64-linux i686-linux' to /etc/nix/nix.custom.conf"
  fi
}

setup_vscode() {
  print_header "VSCode Configuration (Optional)"

  print_info "VSCode can be configured with Nix and direnv extensions for"
  print_info "better development experience."
  print_info "Settings will be added to your user VSCode configuration directory."
  echo ""

  if ! confirm "Configure VSCode for Nix/Ghaf development?"; then
    print_info "Skipping VSCode setup."
    return 0
  fi

  # Determine VSCode config directory (XDG compliant)
  local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
  local vscode_user_dir="${xdg_config}/Code/User"

  # Check for VSCode and VSCodium
  local vscode_installed=false
  local codium_installed=false

  if command -v code &>/dev/null; then
    vscode_installed=true
  fi
  if command -v codium &>/dev/null; then
    codium_installed=true
  fi

  if ! ${vscode_installed} && ! ${codium_installed}; then
    print_warning "Neither VSCode nor VSCodium appears to be installed."
    print_info "Install VSCode from: https://code.visualstudio.com/"
    print_info "Or VSCodium from: https://vscodium.com/"
    if ! confirm "Continue with configuration anyway?"; then
      return 0
    fi
  fi

  # Install extensions using CLI if available
  if ${vscode_installed}; then
    print_step "Installing recommended VSCode extensions..."
    local extensions=(
      "jnoortheen.nix-ide"
      "mkhl.direnv"
      "editorconfig.editorconfig"
      "timonwong.shellcheck"
    )
    for ext in "${extensions[@]}"; do
      print_info "  Installing ${ext}..."
      if code --install-extension "${ext}" --force 2>/dev/null; then
        print_success "  Installed ${ext}"
      else
        print_warning "  Failed to install ${ext} (may already be installed)"
      fi
    done
  fi

  if ${codium_installed}; then
    print_step "Installing recommended VSCodium extensions..."
    local extensions=(
      "jnoortheen.nix-ide"
      "mkhl.direnv"
      "editorconfig.editorconfig"
      "timonwong.shellcheck"
    )
    for ext in "${extensions[@]}"; do
      print_info "  Installing ${ext}..."
      if codium --install-extension "${ext}" --force 2>/dev/null; then
        print_success "  Installed ${ext}"
      else
        print_warning "  Failed to install ${ext} (may already be installed)"
      fi
    done
  fi

  # Configure VSCode settings
  print_step "Configuring VSCode user settings for Nix development..."

  mkdir -p "${vscode_user_dir}"

  local settings_file="${vscode_user_dir}/settings.json"

  # Nix-specific settings to add
  local nix_settings
  nix_settings=$(
    cat <<'EOF'
{
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nixd",
  "nix.serverSettings": {
    "nixd": {
      "formatting": {
        "command": ["nixfmt"]
      }
    }
  },
  "[nix]": {
    "editor.tabSize": 2,
    "editor.insertSpaces": true,
    "editor.formatOnSave": true
  },
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true
}
EOF
  )

  if [[ -f ${settings_file} ]]; then
    print_warning "Existing settings.json found at ${settings_file}"
    print_info "Current Nix-related settings will be merged/updated."
    print_info ""
    print_info "Settings to add/update:"
    echo "${nix_settings}" | head -20
    echo ""

    if confirm "Merge Nix settings into existing settings.json?"; then
      # Create backup
      cp "${settings_file}" "${settings_file}.backup.$(date +%Y%m%d%H%M%S)"
      print_info "Backup created: ${settings_file}.backup.*"

      # Use jq if available for proper JSON merge, otherwise provide manual instructions
      if command -v jq &>/dev/null; then
        local merged
        merged=$(jq -s '.[0] * .[1]' "${settings_file}" <(echo "${nix_settings}"))
        echo "${merged}" >"${settings_file}"
        print_success "Merged Nix settings into ${settings_file}"
      else
        print_warning "jq not installed - cannot automatically merge JSON."
        print_info "Please manually add the following to ${settings_file}:"
        echo ""
        echo "${nix_settings}"
        echo ""
        print_info "You can install jq with: sudo apt install jq"
      fi
    else
      print_info "Skipping settings.json merge."
    fi
  else
    # Create new settings file
    echo "${nix_settings}" >"${settings_file}"
    print_success "Created ${settings_file}"
  fi

  # Also configure VSCodium if installed
  if ${codium_installed}; then
    local codium_user_dir="${xdg_config}/VSCodium/User"
    local codium_settings="${codium_user_dir}/settings.json"

    mkdir -p "${codium_user_dir}"

    if [[ -f ${codium_settings} ]]; then
      print_info "VSCodium settings.json exists - apply same merge process."
      if confirm "Merge Nix settings into VSCodium settings.json?"; then
        cp "${codium_settings}" "${codium_settings}.backup.$(date +%Y%m%d%H%M%S)"
        if command -v jq &>/dev/null; then
          local merged
          merged=$(jq -s '.[0] * .[1]' "${codium_settings}" <(echo "${nix_settings}"))
          echo "${merged}" >"${codium_settings}"
          print_success "Merged Nix settings into ${codium_settings}"
        else
          print_warning "jq not installed - please manually merge settings."
        fi
      fi
    else
      echo "${nix_settings}" >"${codium_settings}"
      print_success "Created ${codium_settings}"
    fi
  fi

  print_info ""
  print_info "VSCode configuration complete!"
  print_info "The direnv extension will automatically load the Nix devshell when you"
  print_info "open the Ghaf project directory."
}

setup_remote_builders() {
  print_header "Remote Build Machines Configuration (Optional)"

  print_info "Remote builders allow offloading Nix builds to more powerful machines."
  print_info "This is especially useful for:"
  print_info "  • Building AArch64 targets on native ARM64 hardware (faster than cross-compilation)"
  print_info "  • Speeding up builds using dedicated build servers"
  print_info "  • Distributed builds across multiple machines"
  echo ""
  print_info "Note: You need SSH access to the remote build machines."
  print_info "The remote machines must have Nix installed and configured to accept builds."
  echo ""

  if ! confirm "Configure remote build machines?"; then
    print_info "Skipping remote builder setup."
    print_info "You can configure this later. See documentation for details."
    return 0
  fi

  # In non-interactive mode, skip the interactive builder collection
  if [[ ${ACCEPT_ALL} == "true" ]]; then
    print_info "Skipping interactive builder configuration in --accept mode."
    print_info "Configure remote builders manually later. See documentation for details."
    return 0
  fi

  # Collect builder information
  local builders=()
  local known_hosts_entries=()

  while true; do
    echo ""
    print_step "Add a remote builder (or press Enter to finish)"

    # Get hostname
    echo -n "  Remote host (e.g., builder.example.com or IP): "
    read -r builder_host
    if [[ -z ${builder_host} ]]; then
      break
    fi

    # Get SSH user
    echo -n "  SSH user [root]: "
    read -r builder_user
    builder_user=${builder_user:-root}

    # Get architecture
    echo "  Target architecture:"
    echo "    1) x86_64-linux"
    echo "    2) aarch64-linux"
    echo "    3) Both"
    echo -n "  Select [1]: "
    read -r arch_choice
    local builder_systems
    case "${arch_choice}" in
    2)
      builder_systems="aarch64-linux"
      ;;
    3)
      builder_systems="x86_64-linux,aarch64-linux"
      ;;
    *)
      builder_systems="x86_64-linux"
      ;;
    esac

    # Get max jobs
    echo -n "  Max parallel jobs [8]: "
    read -r max_jobs
    max_jobs=${max_jobs:-8}

    # Get SSH key path
    local default_key="${HOME}/.ssh/id_ed25519"
    if [[ ! -f ${default_key} ]]; then
      default_key="${HOME}/.ssh/id_rsa"
    fi
    echo -n "  SSH private key path [${default_key}]: "
    read -r ssh_key
    ssh_key=${ssh_key:-${default_key}}

    if [[ ! -f ${ssh_key} ]]; then
      print_warning "SSH key not found at ${ssh_key}"
      if ! confirm "Continue anyway?"; then
        continue
      fi
    fi

    # Build the machine line
    # Format: ssh://user@host system ssh-key max-jobs speed-factor supported-features mandatory-features public-key
    local machine_line="ssh://${builder_user}@${builder_host} ${builder_systems} ${ssh_key} ${max_jobs} 1 nixos-test,benchmark,big-parallel,kvm - -"
    builders+=("${machine_line}")

    # Try to get host key for known_hosts
    print_step "Fetching SSH host key for ${builder_host}..."
    local host_key
    if host_key=$(ssh-keyscan -t ed25519 "${builder_host}" 2>/dev/null); then
      known_hosts_entries+=("${host_key}")
      print_success "Retrieved host key for ${builder_host}"
    else
      print_warning "Could not fetch host key. You may need to add it manually."
    fi

    print_success "Added builder: ${builder_user}@${builder_host} (${builder_systems})"
  done

  if [[ ${#builders[@]} -eq 0 ]]; then
    print_info "No builders configured."
    return 0
  fi

  # Create /etc/nix/machines file
  print_step "Creating /etc/nix/machines file..."

  local machines_content=""
  for builder in "${builders[@]}"; do
    machines_content+="${builder}"$'\n'
  done

  echo ""
  echo "The following will be written to /etc/nix/machines:"
  echo "----------------------------------------"
  echo "${machines_content}"
  echo "----------------------------------------"

  if confirm "Create /etc/nix/machines with these builders?"; then
    echo "${machines_content}" | run_sudo "Create /etc/nix/machines" \
      tee /etc/nix/machines >/dev/null

    if [[ -f /etc/nix/machines ]]; then
      print_success "Created /etc/nix/machines"
    fi
  fi

  # Update nix.conf to use builders
  print_step "Configuring nix.conf to use remote builders..."

  local builder_config
  builder_config="
# Remote build machines configuration
# Added by ubuntu-setup.sh on $(date -Iseconds)
builders = @/etc/nix/machines
builders-use-substitutes = true
"

  if grep -q "^builders = " "${NIX_CONF_FILE}" 2>/dev/null; then
    print_info "builders already configured in nix.conf"
  else
    if confirm "Add remote builder configuration to nix.conf?"; then
      echo "${builder_config}" >>"${NIX_CONF_FILE}"
      print_success "Added builder configuration to nix.conf"
    fi
  fi

  # Add known hosts entries
  if [[ ${#known_hosts_entries[@]} -gt 0 ]]; then
    print_step "Adding SSH known hosts entries..."

    local known_hosts_file="/etc/ssh/ssh_known_hosts"
    local known_hosts_content=""
    for entry in "${known_hosts_entries[@]}"; do
      known_hosts_content+="${entry}"$'\n'
    done

    echo ""
    echo "The following will be appended to ${known_hosts_file}:"
    echo "----------------------------------------"
    echo "${known_hosts_content}"
    echo "----------------------------------------"

    if confirm "Add these entries to system-wide SSH known hosts?"; then
      echo "${known_hosts_content}" | run_sudo "Add SSH known hosts entries" \
        tee -a "${known_hosts_file}" >/dev/null
      print_success "Added known hosts entries"
    fi
  fi

  # Restart nix-daemon
  if systemctl is-active --quiet nix-daemon 2>/dev/null; then
    print_info "Restarting nix-daemon to apply changes..."
    if run_sudo "Restart nix-daemon" systemctl restart nix-daemon; then
      print_success "nix-daemon restarted"
    fi
  fi

  print_success "Remote builders configured!"
  print_info "Test with: nix store ping --store ssh://user@host"
}

setup_apparmor_workaround() {
  print_header "AppArmor Configuration (Ubuntu 24.04)"

  # shellcheck source=/dev/null
  source /etc/os-release 2>/dev/null || true

  if [[ ${ID:-} != "ubuntu" || ${VERSION_ID:-} != "24.04" ]]; then
    print_info "AppArmor workaround only needed for Ubuntu 24.04. Skipping."
    return 0
  fi

  print_warning "Ubuntu 24.04 has stricter AppArmor policies that may affect Nix builds."
  print_info "If you experience sandboxing errors during builds, you may need to"
  print_info "enable unprivileged user namespaces."
  echo ""

  if ! confirm "Configure sysctl for Nix sandboxing compatibility?"; then
    print_info "Skipping AppArmor workaround."
    print_info "If you encounter sandbox errors, run this script again or configure manually."
    return 0
  fi

  local sysctl_file="/etc/sysctl.d/99-nix-userns.conf"
  local sysctl_content="# Enable unprivileged user namespaces for Nix sandboxing
# Added by Ghaf ubuntu-setup.sh
kernel.unprivileged_userns_clone=1
"

  print_step "Creating sysctl configuration for user namespaces..."

  if [[ -f ${sysctl_file} ]]; then
    print_info "sysctl configuration already exists at ${sysctl_file}"
  else
    echo "${sysctl_content}" | run_sudo "Create sysctl config for Nix sandboxing" \
      tee "${sysctl_file}" >/dev/null

    if [[ -f ${sysctl_file} ]]; then
      print_success "Created ${sysctl_file}"

      # Apply immediately
      if run_sudo "Apply sysctl settings" sysctl --system; then
        print_success "sysctl settings applied."
      fi
    fi
  fi
}

verify_installation() {
  print_header "Verifying Installation"

  local all_ok=true

  # Check Nix
  print_step "Checking Nix..."
  if command_exists nix; then
    local nix_version
    nix_version=$(nix --version 2>/dev/null || echo "unknown")
    print_success "Nix: ${nix_version}"

    # Check flakes support
    if nix flake --help &>/dev/null; then
      print_success "Nix flakes: enabled"
    else
      print_warning "Nix flakes: not enabled"
      all_ok=false
    fi
  else
    print_error "Nix: not found"
    all_ok=false
  fi

  # Check direnv
  print_step "Checking direnv..."
  if command_exists direnv; then
    local direnv_version
    direnv_version=$(direnv version 2>/dev/null || echo "unknown")
    print_success "direnv: v${direnv_version}"
  else
    print_warning "direnv: not found"
  fi

  # Check binary cache configuration
  print_step "Checking binary cache configuration..."
  if [[ -f ${NIX_CONF_FILE} ]] && grep -q "ghaf-dev.cachix.org" "${NIX_CONF_FILE}"; then
    print_success "Ghaf binary cache: configured"
  else
    print_warning "Ghaf binary cache: not configured (builds may be slower)"
  fi

  # Check remote builders
  print_step "Checking remote builders..."
  if [[ -f /etc/nix/machines ]] && [[ -s /etc/nix/machines ]]; then
    local builder_count
    builder_count=$(grep -c "^ssh://" /etc/nix/machines 2>/dev/null || echo "0")
    print_success "Remote builders: ${builder_count} configured"
  else
    print_info "Remote builders: not configured (optional)"
  fi

  # Check binfmt
  print_step "Checking cross-architecture support..."
  if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    print_success "AArch64 emulation: available"
  else
    print_info "AArch64 emulation: not configured (use -from-x86_64 targets instead)"
  fi

  echo ""
  if [[ ${all_ok} == "true" ]]; then
    print_success "All essential components are installed and configured!"
  else
    print_warning "Some components may need attention. See messages above."
  fi
}

print_next_steps() {
  print_header "Next Steps"

  echo -e "${BOLD}1. Activate your shell configuration:${NC}"
  echo "   source $(detect_shell_config)"
  echo ""

  echo -e "${BOLD}2. Navigate to the Ghaf project and allow direnv:${NC}"
  echo "   cd ${GHAF_ROOT}"
  echo "   direnv allow"
  echo ""

  echo -e "${BOLD}3. Enter the development shell:${NC}"
  echo "   nix develop"
  echo "   # Or with direnv, it loads automatically!"
  echo ""

  echo -e "${BOLD}4. Build a target to test your setup:${NC}"
  echo "   # Quick VM test (recommended first build):"
  echo "   nix build .#packages.x86_64-linux.vm-debug"
  echo ""
  echo "   # Or build documentation:"
  echo "   nix build .#doc"
  echo ""

  echo -e "${BOLD}5. For ARM64 targets, use cross-compilation:${NC}"
  echo "   nix build .#nvidia-jetson-orin-agx-debug-from-x86_64"
  echo ""

  echo -e "${BOLD}Documentation:${NC}"
  echo "   https://ghaf.tii.ae/ghaf/dev/ref/ubuntu-development-setup/"
  echo "   https://ghaf.tii.ae/ghaf/dev/ref/build_and_run/"
  echo ""

  print_info "If you encounter issues, check the troubleshooting section in the documentation."
}

# =============================================================================
# Uninstall Function
# =============================================================================

uninstall() {
  print_header "Uninstalling Nix and Ghaf Development Environment"

  print_warning "This will remove:"
  print_info "  • Nix package manager and /nix directory"
  print_info "  • Nix configuration in ${NIX_CONF_DIR}"
  print_info "  • direnv configuration in ${DIRENV_CONF_DIR}"
  print_info "  • Shell hooks for direnv"
  echo ""

  if ! confirm "Are you sure you want to uninstall?" "n"; then
    print_info "Uninstall cancelled."
    exit 0
  fi

  # Try Determinate Systems uninstaller first
  if [[ -x /nix/nix-installer ]]; then
    print_step "Running Determinate Systems uninstaller..."
    if /nix/nix-installer uninstall; then
      print_success "Nix uninstalled via Determinate Systems installer."
    else
      print_error "Uninstaller failed. Manual cleanup may be required."
    fi
  else
    print_warning "Determinate Systems uninstaller not found."
    print_info "If you installed via the official installer, manual removal is required:"
    print_info "  https://nixos.org/manual/nix/stable/installation/uninstall"
  fi

  # Clean up configuration files
  print_step "Removing configuration files..."

  if [[ -d ${NIX_CONF_DIR} ]]; then
    if confirm "Remove ${NIX_CONF_DIR}?"; then
      rm -rf "${NIX_CONF_DIR}"
      print_success "Removed ${NIX_CONF_DIR}"
    fi
  fi

  if [[ -f ${DIRENV_CONF_FILE} ]]; then
    if confirm "Remove ${DIRENV_CONF_FILE}?"; then
      rm -f "${DIRENV_CONF_FILE}"
      print_success "Removed ${DIRENV_CONF_FILE}"
    fi
  fi

  # Remove shell hooks
  local shell_config
  shell_config=$(detect_shell_config)
  if [[ -f ${shell_config} ]] && grep -q "direnv hook" "${shell_config}"; then
    print_info "direnv hook found in ${shell_config}"
    print_info "Please remove the following lines manually:"
    grep -n "direnv" "${shell_config}" || true
  fi

  print_success "Uninstall completed."
  print_info "You may need to restart your shell or log out/in for changes to take effect."
}

# =============================================================================
# Help Function
# =============================================================================

show_help() {
  cat <<EOF
${BOLD}Ghaf Framework - Ubuntu Development Environment Setup${NC}

${BOLD}USAGE:${NC}
    ${SCRIPT_NAME} [OPTIONS]

${BOLD}OPTIONS:${NC}
    --accept      Accept all prompts automatically (non-interactive mode)
    --uninstall   Remove Nix and related configurations
    --help        Show this help message

${BOLD}DESCRIPTION:${NC}
    This script sets up a complete Nix-based development environment for
    Ghaf Framework on Ubuntu/Debian systems.

    It will:
    • Install the Nix package manager (using Determinate Systems installer)
    • Configure binary caches for faster builds
    • Set up direnv for automatic environment activation
    • Optionally configure remote build machines for distributed builds
    • Optionally configure VSCode for Nix development
    • Optionally set up QEMU for AArch64 emulation

${BOLD}EXAMPLES:${NC}
    # Interactive installation (prompts for each step)
    ./ubuntu-setup.sh

    # Non-interactive installation (accepts all defaults)
    ./ubuntu-setup.sh --accept

    # Uninstall everything
    ./ubuntu-setup.sh --uninstall

${BOLD}DOCUMENTATION:${NC}
    https://ghaf.tii.ae/ghaf/dev/ref/ubuntu-development-setup/

${BOLD}SUPPORT:${NC}
    https://github.com/tiiuae/ghaf/issues

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --accept)
      ACCEPT_ALL=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      echo "Use --help for usage information."
      exit 1
      ;;
    esac
  done

  # Handle uninstall
  if [[ ${UNINSTALL} == "true" ]]; then
    uninstall
    exit 0
  fi

  # Print banner
  echo ""
  echo -e "${BLUE}${BOLD}"
  echo "   ██████╗ ██╗  ██╗ █████╗ ███████╗"
  echo "  ██╔════╝ ██║  ██║██╔══██╗██╔════╝"
  echo "  ██║  ███╗███████║███████║█████╗  "
  echo "  ██║   ██║██╔══██║██╔══██║██╔══╝  "
  echo "  ╚██████╔╝██║  ██║██║  ██║██║     "
  echo "   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     "
  echo -e "${NC}"
  echo -e "${CYAN}  Ubuntu Development Environment Setup${NC}"
  echo ""

  if [[ ${ACCEPT_ALL} == "true" ]]; then
    print_info "Running in non-interactive mode (--accept)"
  fi

  # Run checks
  check_os
  check_architecture

  # Installation steps
  install_system_dependencies

  # Check for existing Nix and install if needed
  if check_existing_nix; then
    install_nix
  fi

  # Ensure Nix is available in current shell
  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi

  # Continue with configuration
  configure_nix
  install_direnv
  setup_apparmor_workaround
  setup_binfmt
  setup_remote_builders
  setup_vscode

  # Verify and show next steps
  verify_installation
  print_next_steps

  print_success "Setup complete!"
}

# Run main
main "$@"
