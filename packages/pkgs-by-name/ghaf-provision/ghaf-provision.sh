#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# =============================================================================
# SCRIPT CONSTANTS & DEFAULTS
# =============================================================================

# Debug configuration
LDAP_SEARCH_TIMEOUT=30

# Ghaf color scheme
GHAF_PRIMARY="#5AC379"
GHAF_SECONDARY="#3D8252"
GHAF_ERROR="#FF6B6B"

# UI color constants
COLOR_SUCCESS="$GHAF_PRIMARY"
COLOR_ERROR="$GHAF_ERROR"
COLOR_WARNING="#FFA500"
COLOR_INFO="#FFFFFF"
COLOR_DEBUG="#808080"

# Unified spacing constants
SPACING_MARGIN="0 1"
SPACING_PADDING="0 1"
SPACING_HEADER_BOTTOM="1 0"
SPACING_INFO_BOTTOM="0"

# Header styling constants
HEADER_WIDTH=80
HEADER_HEIGHT=3
HEADER_PADDING="1 2"

# System paths and configuration (no defaults in code)

# System paths and configuration
KERBEROS_KEYTAB="/etc/krb5.keytab"

# =============================================================================
# GLOBAL STATE VARIABLES
# =============================================================================

# User input variables (set by CLI args or config)
USERNAME=""
REALNAME=""
PASSWORD=""
FIDO_AUTH=false
USER_GROUPS=""
HOME_SIZE=""
USER_ID=""
FS_TYPE=""
FIDO_SUPPORT=""
USER_HOME_DIRECTORY=""
USER_SHELL=""
RECOVERY_KEY=true

# Active Directory variables
AD_MODE=false
AD_DOMAIN=""
AD_REALM=""
AD_SERVER=""
LDAP_SERVER=""
DNS_SERVER=""
BASE_DN=""
AD_USERNAME=""

# Script mode flags
SYSTEM_MODE=false
USER_MODE=false
NON_INTERACTIVE=false
REMOVE_USERS=false

# Global cleanup registry
cleanup_funcs=""

# =============================================================================
# STATE MACHINE
# =============================================================================

# State machine variables
CURRENT_STATE=""
PREVIOUS_STATE=""

# State function mapping
declare -A STATE_FUNCTIONS=(
  ["SYSTEM_SETUP"]="screen_system_setup"
  ["AD_CONFIG"]="screen_ad_config"
  ["AD_JOIN"]="screen_ad_join"
  ["USER_TYPE_SELECT"]="screen_user_type_select"
  ["LOCAL_USER_CREATE"]="screen_local_user_create"
  ["AD_USER_SEARCH"]="screen_ad_user_search"
  ["NETWORK_SETUP"]="screen_network_setup"
  ["COMPLETE"]="screen_complete"
)

# State transition helpers
goto_state() {
  CURRENT_STATE="$1"
  debug "Transitioning to state: $CURRENT_STATE"
}

# State machine entry point
start_state_machine() {
  local mode="$1"

  # Set starting state based on CLI mode
  case "$mode" in
  "system") CURRENT_STATE="SYSTEM_SETUP" ;;
  "user") CURRENT_STATE="USER_TYPE_SELECT" ;;
  "full") CURRENT_STATE="SYSTEM_SETUP" ;;
  *)
    debug "Unknown mode: $mode"
    CURRENT_STATE="EXIT"
    ;;
  esac

  debug "Starting state machine with mode: $mode, initial state: $CURRENT_STATE"
  while [[ $CURRENT_STATE != "EXIT" && $CURRENT_STATE != "COMPLETE" ]]; do
    PREVIOUS_STATE="$CURRENT_STATE"

    # Get and call the screen function for current state
    local screen_func="${STATE_FUNCTIONS[$CURRENT_STATE]}"
    if [[ -n $screen_func ]]; then
      $screen_func
    else
      debug "Error: No function defined for state: $CURRENT_STATE"
      break
    fi
  done

  # Run cleanup when state machine exits
  debug "State machine exited with state: $CURRENT_STATE"
  run_cleanups
}

# =============================================================================
# CORE UTILITIES & SYSTEM SETUP
# =============================================================================

# Set up signal handlers to ensure cleanup on exit
trap 'run_cleanups; exit 0' EXIT
trap 'run_cleanups; exit 130' INT
trap 'run_cleanups; exit 143' TERM

# Register cleanup function
register_cleanup() {
  cleanup_funcs="$cleanup_funcs $1"
}

# Run all registered cleanups
run_cleanups() {
  for func in $cleanup_funcs; do
    $func 2>/dev/null || true
  done
}

# Debug logging function - output to journald
debug() {
  echo "$*" | systemd-cat -t ghaf-provision -p debug
}

# =============================================================================
# CONFIGURATION FILE HANDLING
# =============================================================================

# Default configuration file location
CONFIG_FILE="/etc/ghaf/provisioning.json"

# Configuration variables (loaded from JSON)
declare -A CONFIG=()

# Load configuration from JSON file into associative array
load_configuration() {
  debug "Loading configuration from $CONFIG_FILE"

  if [[ ! -f $CONFIG_FILE ]]; then
    debug "Configuration file not found: $CONFIG_FILE"
    return 1
  fi

  # Validate JSON syntax
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    debug "Invalid JSON in configuration file: $CONFIG_FILE"
    return 1
  fi

  # Load all configuration values into associative array
  while IFS='=' read -r key value; do
    CONFIG["$key"]="$value"
  done < <(
    jq -r '
      [paths as $path |
       select(getpath($path) | type == "boolean" or type == "string" or type == "number") |
       { "key": ($path | map(tostring) | join(".")),
         "value": (getpath($path) | tostring) }
      ] |
      .[] |
      "\(.key)=\(.value)"
    ' "$CONFIG_FILE"
  )

  debug "Configuration loaded successfully (${#CONFIG[@]} keys)"
}

# Get configuration value by key
config_get() {
  local key="$1"
  local default="${2:-}"
  if [[ -v CONFIG["$key"] ]]; then
    echo "${CONFIG[$key]}"
  else
    echo "$default"
  fi
}

# Check if a configuration option is enabled (true/1/yes)
config_enabled() {
  local key="$1"
  local value
  value=$(config_get "$key")
  case "${value,,}" in
  true | yes | 1 | on) return 0 ;;
  *) return 1 ;;
  esac
}

# Apply configuration values only if not already set by CLI arguments
apply_configuration() {
  debug "Applying configuration values (CLI takes precedence)"

  # User setup configuration with sensible defaults
  if $USER_MODE; then
    [[ -z $USERNAME ]] && USERNAME=$(config_get "user_config.username" "")
    [[ -z $REALNAME ]] && REALNAME=$(config_get "user_config.realname" "")
    [[ -z $HOME_SIZE ]] && HOME_SIZE=$(config_get "user_config.home_size" "10000")
    [[ -z $USER_ID ]] && USER_ID=$(config_get "user_config.uid" "1000")
    [[ -z $FS_TYPE ]] && FS_TYPE=$(config_get "user_config.fs_type" "ext4")
    [[ -z $USER_SHELL ]] && USER_SHELL=$(config_get "user_config.shell" "/run/current-system/sw/bin/bash")
    [[ -z $USER_GROUPS ]] && USER_GROUPS=$(config_get "user_config.groups" "users")

    # FIDO auth from config
    if ! $FIDO_AUTH; then
      config_enabled "user_config.fido_auth" && FIDO_AUTH=true
    fi
  fi

  # Initialize Active Directory configuration from config
  init_ad_config

  debug "Configuration applied."
}

# Validate required configuration parameters
validate_configuration() {
  local errors=0

  debug "Validating configuration parameters"

  # Non-interactive mode requires specific parameters
  if $NON_INTERACTIVE; then
    [[ -z $USERNAME ]] && {
      show_error "Error: --username required for non-interactive mode"
      ((errors++))
    }
    [[ -z $REALNAME ]] && {
      show_error "Error: --realname required for non-interactive mode"
      ((errors++))
    }
    [[ -z $PASSWORD ]] && {
      show_error "Error: --password required for non-interactive mode"
      ((errors++))
    }
  fi

  if [[ $errors -gt 0 ]]; then
    show_error "Configuration validation failed with $errors error(s)"
    return 1
  fi

  debug "Configuration validation passed"
  return 0
}

# =============================================================================
# GUM/TUI CONFIGURATION & WRAPPERS
# =============================================================================

# Configure gum styling
export GUM_INPUT_CURSOR_FOREGROUND="$GHAF_PRIMARY"
export GUM_INPUT_HEADER_FOREGROUND="$GHAF_SECONDARY"
export GUM_CHOOSE_CURSOR_FOREGROUND="$GHAF_PRIMARY"
export GUM_CHOOSE_SELECTED_FOREGROUND="$GHAF_SECONDARY"
export GUM_SPIN_SPINNER_FOREGROUND="$GHAF_PRIMARY"
export GUM_CONFIRM_SELECTED_BACKGROUND="$GHAF_PRIMARY"

# Success message wrapper
show_success() {
  gum style --foreground="$COLOR_SUCCESS" "$*"
}

# Error message wrapper
show_error() {
  gum style --foreground="$COLOR_ERROR" "$*" >&2
}

# Info message wrapper
show_info() {
  gum style --foreground="$COLOR_INFO" --margin="$SPACING_INFO_BOTTOM" "$@"
}

# Warning message wrapper
show_warning() {
  gum style --foreground="$COLOR_WARNING" "$*"
}

# Header wrapper - creates a bordered header box
show_header() {
  gum style \
    --foreground="$GHAF_PRIMARY" \
    --border="rounded" \
    --border-foreground="$GHAF_SECONDARY" \
    --align="center" \
    --width="$HEADER_WIDTH" \
    --height="$HEADER_HEIGHT" \
    --margin="$SPACING_HEADER_BOTTOM" \
    --padding="$HEADER_PADDING" \
    "$@"
}

# Section wrapper with border
show_section() {
  gum style \
    --border="rounded" \
    --border-foreground="$GHAF_SECONDARY" \
    --padding="$SPACING_PADDING" \
    --margin="$SPACING_MARGIN" \
    "$@"
}

# Input wrapper
prompt_input() {
  local prompt_text="$1"
  local placeholder="${2:-}"
  gum input \
    --prompt="$prompt_text " \
    --placeholder="$placeholder" \
    --cursor.foreground="$GHAF_PRIMARY" \
    --prompt.bold
}

# Password input wrapper
prompt_password() {
  local prompt_text="$1"
  gum input \
    --prompt="$prompt_text " \
    --password \
    --cursor.foreground="$GHAF_PRIMARY" \
    --prompt.bold
}

# Confirmation wrapper
prompt_confirm() {
  local message="$1"
  local affirmative="${2:-Yes}"
  local negative="${3:-No}"
  gum confirm \
    --affirmative="$affirmative" \
    --negative="$negative" \
    --default=true \
    "$message"
}

# Choice menu wrapper
prompt_choice() {
  local header="$1"
  shift
  gum choose \
    --cursor.foreground="$GHAF_PRIMARY" \
    --selected.foreground="$GHAF_SECONDARY" \
    --header="$header" \
    --header.foreground="$GHAF_SECONDARY" \
    "$@"
}

# Progress spinner wrapper
show_progress() {
  local title="$1"
  shift
  gum spin \
    --spinner="dot" \
    --title="$title" \
    --spinner.foreground="$GHAF_PRIMARY" \
    -- "$@"
}

# =============================================================================
# INPUT VALIDATION & PROCESSING
# =============================================================================

# Display usage information
usage() {
  cat <<EOF
ghaf-provision - Ghaf system and user provisioning service

Usage: ghaf-provision [MODE] [OPTIONS]

MODES:
  user                    User setup mode - Create or manage systemd-homed users
  system                  System setup mode - AD domain join, fleet enrollment
  full                    Full setup mode - Both system and user setup

USER MODE OPTIONS:
  --username USER         Username for the new user account
  --realname NAME         Real/full name for the user
  --groups GROUPS   Comma-separated list of additional groups
  --home-size SIZE        Home directory size in MB
  --uid UID               User ID
  --fido                  Enable FIDO2 authentication
  --password PASS         Password for non-interactive setup
  --fs-type TYPE          Filesystem type for home directory
  --shell PATH            Login shell
  --non-interactive       Non-interactive user creation (requires username, realname, password)
  --remove                Remove all systemd-homed users

GENERAL OPTIONS:
  --config FILE           Use custom configuration file (default: /etc/ghaf/provisioning.json)
  -h, --help              Show this help message

EXAMPLES:

  Full setup (system & user):
    ghaf-provision full

  User setup with options:
    ghaf-provision user --username alice --realname "Alice Smith" --fido

  Non-interactive user creation:
    ghaf-provision user --non-interactive --username bob --realname "Bob Jones" --password "SecurePass123"

  Remove all users:
    ghaf-provision user --remove

EOF
}

# Parse command-line arguments
parse_args() {
  # Handle positional argument for mode
  if [[ $# -gt 0 && $1 != -* ]]; then
    case $1 in
    user)
      USER_MODE=true
      SYSTEM_MODE=false
      shift
      ;;
    system)
      SYSTEM_MODE=true
      USER_MODE=false
      shift
      ;;
    full)
      SYSTEM_MODE=true
      USER_MODE=true
      shift
      ;;
    *)
      show_error "Invalid mode: '$1'. Use 'user', 'system', or 'full'"
      usage >&2
      exit 1
      ;;
    esac
  fi

  # Handle remaining options
  while [[ $# -gt 0 ]]; do
    case $1 in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --realname)
      REALNAME="$2"
      shift 2
      ;;
    --groups)
      USER_GROUPS="$2"
      shift 2
      ;;
    --home-size)
      if [[ $2 =~ ^[0-9]+$ ]] && [[ $2 != "0" ]]; then
        HOME_SIZE="$2"
      else
        show_error "Invalid home size '$2'. Must be a string containing a positive number."
        exit 1
      fi
      shift 2
      ;;
    --uid)
      if [[ $2 =~ ^[0-9]+$ ]]; then
        USER_ID="$2"
      else
        show_error "Invalid user ID '$2'. Must be a string containing a number."
        exit 1
      fi
      shift 2
      ;;
    --fido)
      FIDO_AUTH=true
      shift
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --fs-type)
      FS_TYPE="$2"
      shift 2
      ;;
    --shell)
      USER_SHELL="$2"
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --remove)
      REMOVE_USERS=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      show_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
    esac
  done

  # Require a mode to be specified
  if ! $SYSTEM_MODE && ! $USER_MODE; then
    show_error "Error: A mode argument is required. Use 'user', 'system', or 'full'"
    usage >&2
    exit 1
  fi

  # Validate mode-specific options
  if $SYSTEM_MODE; then
    if $NON_INTERACTIVE; then
      show_error "Error: --non-interactive not supported in system mode"
      exit 1
    fi
    if $REMOVE_USERS; then
      show_error "Error: --remove not supported in system mode"
      exit 1
    fi
  fi
}

# Validate and set the username
set_username() {
  local user="$1"
  user="${user// /_}"
  user="${user//[^a-zA-Z0-9_-]/}"
  user="$(echo -n "$user" | tr '[:upper:]' '[:lower:]')"

  if [[ -z $user ]]; then
    debug "Error: Username cannot be empty"
    return 1
  elif getent passwd "$user" >/dev/null 2>&1; then
    debug "Error: User $user already exists"
    return 1
  fi

  USERNAME="$user"
  return 0
}

# Validate and set the real name
set_realname() {
  local name="$1"
  name="${name//[^a-zA-Z ]/}"

  if [[ -z $name ]]; then
    debug "Error: Real name cannot be empty"
    return 1
  fi

  REALNAME="$name"
  return 0
}

# Prompt user to enter a username
prompt_username() {
  debug "Prompting for username"

  while true; do
    local username_input
    username_input=$(prompt_input "Username:" "Enter username (lowercase, no spaces)") || return 1

    if set_username "$username_input"; then
      debug "Username set: $USERNAME"
      show_success "Username: $USERNAME"
      break
    else
      show_error "Invalid or empty username. Must be lowercase letters, numbers, underscore, or dash only."
    fi
  done
}

# Prompt user to enter a real name
prompt_realname() {
  debug "Prompting for real name"

  while true; do
    local realname_input
    realname_input=$(prompt_input "Full name:" "Enter your full name") || return 1

    if set_realname "$realname_input"; then
      debug "Real name set: $REALNAME"
      show_success "Real name: $REALNAME"
      break
    else
      show_error "Invalid or empty name. Letters and spaces only."
    fi
  done
}

# Validate and warn about incompatible options in AD mode
validate_ad_mode_options() {

  # Warn about incompatible options that will be ignored
  if [[ -n $USERNAME ]]; then
    show_warning "--username ignored in AD mode"
  fi

  if [[ -n $REALNAME ]]; then
    show_warning "--realname ignored in AD mode"
  fi

  if [[ -n $PASSWORD ]]; then
    show_warning "--password ignored in AD mode"
  fi

}

# =============================================================================
# NETWORK & CONNECTIVITY FUNCTIONS
# =============================================================================

# Check connectivity and provide setup options if needed
check_connectivity() {
  local test_host="${1:-8.8.8.8}"
  debug "Checking internet connectivity to $test_host"

  # Show animated connectivity check
  if show_progress "Checking internet connection..." ping -c 1 -W 3 "$test_host"; then
    show_success "Internet connection confirmed"
    debug "Internet connectivity check passed"
    return 0
  fi

  show_error "No internet connection detected"
  show_error "Please connect an ethernet cable or set up WiFi to proceed."
  debug "Internet connectivity check failed"

  # Interactive connectivity setup loop
  while true; do
    # Check if connection was established
    if ping -c 1 -W 3 "$test_host" &>/dev/null; then
      show_success "Internet connection established"
      debug "Internet connectivity established"
      return 0
    fi

    echo ""
    local choice
    choice=$(prompt_choice "Choose network setup option:" \
      "Check connection again" \
      "Setup WiFi" \
      "Change test host (currently: $test_host)" \
      "Continue without internet") || return 1

    debug "Connectivity choice selected: '$choice'"

    case "$choice" in
    "Check connection"*)
      if ping -c 1 -W 3 "$test_host" &>/dev/null; then
        show_success "Internet connection established"
        debug "Internet connectivity established"
        return 0
      else
        show_error "Still no internet connection"
      fi
      ;;
    "Setup WiFi"*)
      setup_wifi
      ;;
    "Change test host"*)
      echo ""
      local new_host
      new_host=$(prompt_input "Enter new test host:" "IP or hostname") || return 1
      if [[ -n $new_host ]]; then
        test_host="$new_host"
        show_success "Test host changed to: $test_host"
        debug "Test host changed to: $test_host"
      else
        show_warning "No change made to test host"
      fi
      ;;
    "Continue without"*)
      show_warning "Continuing without internet connection"
      debug "User chose to continue without internet"
      echo ""
      if prompt_confirm "Would you like to create local users instead?" "Yes, create local users" "No, exit setup"; then
        debug "User chose to switch to local user creation"
        AD_MODE=false
        # For now, just return 1 - callers should handle mode switching
        return 1
      else
        debug "User chose to exit setup"
        return 1
      fi
      ;;
    *)
      show_error "Unknown choice: '$choice'"
      ;;
    esac
  done
}

# Setup WiFi connection
setup_wifi() {

  if ! nmcli device wifi list; then
    show_error "Could not scan for WiFi networks"
    debug "WiFi scan failed"
    return
  fi

  echo ""
  local wifi_ssid
  wifi_ssid=$(prompt_input "Enter WiFi network SSID:" "network name") || return 1

  debug "Attempting to connect to WiFi: $wifi_ssid"

  if nmcli device wifi connect "$wifi_ssid" --ask; then
    show_success "Successfully connected to '$wifi_ssid'"
    debug "WiFi connection successful: $wifi_ssid"
  else
    show_error "Failed to connect to WiFi network '$wifi_ssid'"
    debug "WiFi connection failed: $wifi_ssid"
    nmcli connection delete "$wifi_ssid" 2>/dev/null || true
    debug "Removed failed connection profile: $wifi_ssid"
    return 1
  fi
}

# Check for FIDO2 device availability
check_fido_support() {
  if $FIDO_AUTH; then
    local fido2_dev
    fido2_dev=$(fido2-token2 -L || true)
    if [[ -n $fido2_dev ]]; then
      FIDO_SUPPORT="auto"
    else
      FIDO_SUPPORT=""
    fi
  else
    FIDO_SUPPORT=""
  fi
}

# =============================================================================
# ACTIVE DIRECTORY INTEGRATION
# =============================================================================

# Initialize/reset AD configuration from config file defaults
init_ad_config() {
  debug "Initializing AD configuration from config"

  # Load AD configuration (same logic as apply_configuration)
  AD_DOMAIN=$(config_get "ad_config.domain")
  AD_REALM=$(config_get "ad_config.realm")
  AD_SERVER=$(config_get "ad_config.ad_server")
  LDAP_SERVER=$(config_get "ad_config.ldap_server")

  # Handle domain/realm relationship
  if [[ -n $AD_DOMAIN && -n $AD_REALM ]]; then
    # Both configured - use as-is
    debug "Using configured domain: $AD_DOMAIN and realm: $AD_REALM"
  elif [[ -n $AD_REALM && -z $AD_DOMAIN ]]; then
    # Only realm configured - derive domain from realm
    AD_DOMAIN="${AD_REALM,,}"
    debug "Derived domain '$AD_DOMAIN' from realm '$AD_REALM'"
  elif [[ -n $AD_DOMAIN && -z $AD_REALM ]]; then
    # Only domain configured - derive realm from domain
    AD_REALM="${AD_DOMAIN^^}"
    debug "Derived realm '$AD_REALM' from domain '$AD_DOMAIN'"
  fi

  BASE_DN=$(get_base_dn "$AD_DOMAIN")

  debug "AD config initialized - Domain: $AD_DOMAIN, Realm: $AD_REALM, Server: $AD_SERVER, LDAP: $LDAP_SERVER"
}

# Convert domain name to LDAP Base DN format
get_base_dn() {
  local domain="$1"
  echo "DC=${domain//./,DC=}"
}

# Configure DNS server if needed
configure_dns_server() {
  debug "Configuring DNS server"

  if is_domain_joined; then
    show_info "System is already domain-joined; DNS configuration is probably unnecessary."
    debug "System already domain-joined; DNS configuration is probably unnecessary."
  fi

  DNS_SERVER=$(prompt_input "Enter custom DNS server IP:" "e.g., 4.4.4.4 (leave blank to skip)") || return 1
  if [[ -n $DNS_SERVER ]]; then
    show_info "Adding temporary DNS server: $DNS_SERVER"
    # Get default route interface
    local default_iface
    if default_iface=$(ip route show default | awk '/default/ {print $5}' | head -1) && [[ -n $default_iface ]]; then
      # Try different methods to set DNS
      if resolvectl dns "$default_iface" "$DNS_SERVER" 2>/dev/null; then
        debug "DNS server added via systemd-resolved: $DNS_SERVER"
        show_success "DNS server added via systemd-resolved: $DNS_SERVER"
        # Register cleanup to restart systemd-resolved
        # shellcheck disable=SC2329  # Function called indirectly via cleanup registry
        cleanup_dns() {
          debug "Restarting systemd-resolved to restore original DNS"
          systemctl restart systemd-resolved 2>/dev/null || true
        }
        # shellcheck disable=SC2329  # Function called indirectly via cleanup registry
        register_cleanup cleanup_dns
        # Flush DNS caches
        resolvectl flush-caches
      elif nmcli device modify "$default_iface" ipv4.dns "$DNS_SERVER" 2>/dev/null; then
        debug "DNS server added via NetworkManager: $DNS_SERVER"
        show_success "DNS server added via NetworkManager: $DNS_SERVER"
        # Register cleanup to restart NetworkManager
        # shellcheck disable=SC2329  # Function called indirectly via cleanup registry
        cleanup_dns() {
          debug "Restarting NetworkManager to restore original DNS"
          systemctl restart NetworkManager 2>/dev/null || true
        }
        # shellcheck disable=SC2329  # Function called indirectly via cleanup registry
        register_cleanup cleanup_dns
        sleep 1 # Small delay for NM
      else
        debug "Failed to set DNS server via systemd-resolved or NetworkManager"
        show_warning "Could not set DNS server - continuing anyway"
      fi
    else
      debug "Could not detect default interface for DNS setup"
      show_warning "Could not detect default interface - continuing anyway"
    fi
  else
    debug "No custom DNS server entered"
  fi

  show_success "DNS server: ${DNS_SERVER:-System Default}"
}

# Detect AD servers automatically using DNS SRV records
detect_ad_servers() {
  local domain="$1"
  local detected_servers=()
  local services=("_ldap._tcp" "_kerberos._tcp" "_kpasswd._tcp")

  debug "Attempting automatic AD server detection for domain: $domain"

  for service in "${services[@]}"; do
    local srv_results
    debug "Querying SRV record: $service.$domain"
    if srv_results=$(dig +short SRV "$service.$domain" 2>/dev/null); then
      debug "SRV query for $service.$domain returned: '$srv_results'"
      if [[ -n $srv_results ]] && [[ ! $srv_results =~ ^\;\; ]]; then
        debug "Found SRV records for $service"
        while IFS= read -r srv_record; do
          if [[ -n $srv_record ]] && [[ ! $srv_record =~ ^\;\; ]]; then
            debug "Processing SRV record: '$srv_record'"
            # Extract hostname from SRV record (format: priority weight port hostname)
            local server_name
            server_name=$(echo "$srv_record" | awk '{print $4}' | awk '{sub(/\.$/, ""); print}')
            debug "Extracted server name: '$server_name'"
            if [[ -n $server_name ]]; then
              detected_servers+=("$server_name")
            fi
          fi
        done <<<"$srv_results"
      else
        debug "No SRV records found for $service.$domain"
      fi
    else
      debug "SRV query failed for $service.$domain"
    fi
  done

  # Remove duplicates and return unique servers
  local unique_servers
  unique_servers=$(printf '%s\n' "${detected_servers[@]}" | sort -u)
  debug "Unique servers found: $unique_servers"
  echo "$unique_servers"
}

# Helper function to configure server with smart detection and selection
configure_server() {
  local server_var="$1"
  local server_name="$2"
  local previous_server="$3"
  local detected_servers_list="$4"

  while true; do
    local choices=()
    local current_server="${!server_var}"

    # Build choice list - include current value first if set
    [[ -n $current_server ]] && choices+=("$current_server (current)")
    [[ -n $previous_server && $previous_server != "$current_server" ]] && choices+=("$previous_server")
    if [[ -n $detected_servers_list ]]; then
      while IFS= read -r server; do
        [[ -n $server && $server != "$previous_server" && $server != "$current_server" ]] && choices+=("$server")
      done <<<"$detected_servers_list"
    fi
    choices+=("Enter manually")

    # Get user choice
    local value
    if [[ ${#choices[@]} -gt 1 ]]; then
      value=$(prompt_choice "Select $server_name:" "${choices[@]}") || return 1

      # Handle different choice types
      if [[ $value == "Enter manually" ]]; then
        value=$(prompt_input "Enter $server_name hostname/IP:" "hostname or IP address") || return 1
      elif [[ $value == *" (current)" ]]; then
        break
      fi
    else
      value=$(prompt_input "Enter $server_name hostname/IP:" "hostname or IP address") || return 1
    fi

    # Validate and set
    if [[ -n $value ]]; then
      if [[ ! $value =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! nslookup "$value" >/dev/null 2>&1; then
        show_warning "Warning: Cannot resolve hostname '$value'"
        prompt_confirm "Continue anyway?" || continue
      fi
      declare -g "$server_var=$value"
      break
    else
      show_error "$server_name cannot be empty."
    fi
  done

  show_success "$server_name: ${!server_var}"
}

# Interactive AD configuration setup
configure_ad_parameters() {

  show_warning "Note: If using hostnames, ensure they resolve to externally accessible IPs."

  # Store current config values for potential defaults
  local config_domain="$AD_DOMAIN"
  local config_ad_server="$AD_SERVER"
  local config_ldap_server="$LDAP_SERVER"

  # Get AD domain (use config as default suggestion)
  debug "Starting AD domain configuration"
  echo ""
  local domain_prompt="Enter AD domain:"
  local domain_placeholder="e.g., example.com"
  if [[ -n $config_domain ]]; then
    domain_prompt="Enter AD domain (current: $config_domain):"
    domain_placeholder="$config_domain"
  fi

  local new_domain
  while true; do
    new_domain=$(prompt_input "$domain_prompt" "$domain_placeholder") || return 1
    if [[ -n $new_domain ]]; then
      AD_DOMAIN="$new_domain"
      break
    elif [[ -n $config_domain ]]; then
      AD_DOMAIN="$config_domain"
      break
    else
      show_error "Domain cannot be empty."
    fi
  done

  # Derive base DN and realm (if not set)
  AD_DOMAIN=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
  [[ -z $AD_REALM ]] && AD_REALM="${AD_DOMAIN^^}"
  BASE_DN=$(get_base_dn "$AD_DOMAIN")
  show_success "AD Domain: $AD_DOMAIN"
  show_success "AD Realm: $AD_REALM"
  show_success "Base DN: $BASE_DN"

  # Configure DNS server first (affects detection)
  DNS_SERVER=""
  configure_dns_server || return 1

  # Detect available AD servers
  local detected_servers
  detected_servers=$(detect_ad_servers "$AD_DOMAIN")

  if [[ -n $detected_servers ]]; then
    local server_count
    server_count=$(echo "$detected_servers" | wc -l)
    show_success "Detected $server_count AD server(s)"
  else
    show_warning "No AD/LDAP servers detected for realm $AD_REALM. You will need to enter them manually."
    echo ""
  fi

  # Configure AD and LDAP servers (use config values as suggestions)
  configure_server "AD_SERVER" "AD server" "$config_ad_server" "$detected_servers" || return 1
  configure_server "LDAP_SERVER" "LDAP server" "${config_ldap_server:-$AD_SERVER}" "$detected_servers" || return 1

  return 0
}

# Query LDAP for AD users with authentication and format output as pipe-delimited
query_ldap() {
  local server="$1"
  local base_dn="$2"
  local ad_user="$3"
  local ad_domain="$4"
  local name_filter="$5"

  # Build LDAP filter for users
  local ldap_filter="(objectClass=user)"
  if [[ -n $name_filter ]]; then
    local name_filter_escaped
    name_filter_escaped=$(echo "$name_filter" | awk '{gsub(/\\/, "\\\\"); gsub(/\(/, "\\("); gsub(/\)/, "\\)"); gsub(/\*/, "\\*"); print}')
    ldap_filter="(&$ldap_filter(|(sAMAccountName=*$name_filter_escaped*)(displayName=*$name_filter_escaped*)(uidNumber=$name_filter_escaped)(gidNumber=$name_filter_escaped)))"
  fi

  # Basic check if LDAP is reachable
  local ldap_host="$server"
  local ldap_port="389"
  if [[ $server =~ ^([^:]+):([0-9]+)$ ]]; then
    ldap_host="${BASH_REMATCH[1]}"
    ldap_port="${BASH_REMATCH[2]}"
  fi
  if ! timeout 5 nc -z "$ldap_host" "$ldap_port" >/dev/null 2>&1; then
    show_error "Cannot reach LDAP server at $ldap_host:$ldap_port"
    return 1
  fi

  # Query LDAP with appropriate authentication
  local ldap_output

  # If keyfile exists (enrolled machine), use GSSAPI
  if [[ -r $KERBEROS_KEYTAB ]]; then
    debug "Using GSSAPI authentication (enrolled machine)"

    # Acquire Kerberos ticket
    MACHINE_HOSTNAME=$(hostname -f | tr '[:lower:]' '[:upper:]')
    debug "Using VM hostname from system: $MACHINE_HOSTNAME"
    KERBEROS_PRINCIPAL="$MACHINE_HOSTNAME\$@$AD_REALM"
    debug "Acquiring Kerberos ticket for principal: $KERBEROS_PRINCIPAL"

    if ! kinit -kt "$KERBEROS_KEYTAB" "$KERBEROS_PRINCIPAL"; then
      show_error "Error: kinit failed to acquire a Kerberos ticket."
      show_error "Check the principal name, keytab content, and network connection to the KDC."
      return 1
    fi

    # Perform LDAP search with GSSAPI
    if ! ldap_output=$(timeout "$LDAP_SEARCH_TIMEOUT" ldapsearch -H "ldap://$server" -b "$base_dn" \
      -Y GSSAPI \
      "$ldap_filter" \
      sAMAccountName displayName uidNumber gidNumber homeDirectory loginShell \
      -LLL -o ldif_wrap=no 2>&1); then
      debug "LDAP query failed with output: $ldap_output"
      show_error "LDAP query failed: $ldap_output"
      return 1
    fi

  else

    # Prompt for AD user password
    local ad_password
    ad_password=$(prompt_password "Enter password for $AD_USERNAME:") || return 1

    # No keyfile (unenrolled machine), use simple bind
    debug "Using simple bind authentication (unenrolled machine)"
    if ! ldap_output=$(timeout "$LDAP_SEARCH_TIMEOUT" ldapsearch -H "ldap://$server" -b "$base_dn" \
      -x \
      -D "$ad_user@$ad_domain" \
      -y <(printf '%s' "$ad_password") \
      "$ldap_filter" \
      sAMAccountName displayName uidNumber gidNumber homeDirectory loginShell \
      -LLL -o ldif_wrap=no 2>&1); then
      debug "LDAP query failed with output: $ldap_output"
      show_error "LDAP query failed: $ldap_output"
      return 1
    fi
  fi

  # Parse LDAP output and format as pipe-delimited
  echo "$ldap_output" |
    awk -v OFS='|' '
      /^sAMAccountName: / { samAccountName = substr($0, index($0, ": ") + 2) }
      /^displayName: / { displayName = substr($0, index($0, ": ") + 2) }
      /^uidNumber: / { uidNumber = substr($0, index($0, ": ") + 2) }
      /^gidNumber: / { gidNumber = substr($0, index($0, ": ") + 2) }
      /^homeDirectory: / { homeDirectory = substr($0, index($0, ": ") + 2) }
      /^loginShell: / { loginShell = substr($0, index($0, ": ") + 2) }
      /^$/ {
        if (samAccountName && uidNumber) {
          print samAccountName, (displayName ? displayName : samAccountName), uidNumber, gidNumber, homeDirectory, loginShell
        }
        samAccountName = displayName = uidNumber = gidNumber = homeDirectory = loginShell = ""
      }
      END {
        if (samAccountName && uidNumber) {
          print samAccountName, (displayName ? displayName : samAccountName), uidNumber, gidNumber, homeDirectory, loginShell
        }
      }'
}

# Check if system is already joined to a domain using adcli
is_domain_joined() {
  adcli testjoin 2>/dev/null
}

# Get storage mount path from configuration
get_storage_mount_path() {
  config_get "storage.mount_path"
}

# Perform Active Directory domain join
perform_ad_join() {
  debug "Starting AD domain join process"

  # Use current configured values
  local domain="$AD_DOMAIN"
  local realm="$AD_REALM"

  if [[ -z $domain ]]; then
    show_error "AD domain must be configured for domain joining"
    return 1
  fi

  # Check if already joined
  if is_domain_joined; then
    show_success "Already joined to domain: $realm"
    debug "Domain join skipped - already joined"
    return 0
  fi

  show_info "Joining domain: $domain (realm: $realm)"

  # Ensure network connectivity (blocks until connected or user exits)
  if ! check_connectivity; then
    show_error "Network connectivity required for domain join"
    return 1
  fi

  # Allow user to optionally configure custom DNS for domain join
  configure_dns_server || return 1

  # Prompt for admin credentials (interactive mode only)
  local ad_user=""
  while [[ -z $ad_user ]]; do
    ad_user=$(prompt_input "Enter AD admin username:" "e.g., admin") || return 1
  done

  # Recreate exact logic from sssd.nix: handle existing keytab if storagevm is available
  local storage_mount_path
  storage_mount_path=$(get_storage_mount_path)
  if [[ -n $storage_mount_path ]]; then
    # adcli does not accept the pre-created keytab file, so we remove it to force re-creation
    if [[ -e $KERBEROS_KEYTAB ]]; then
      debug "StorageVM detected: removing existing keytab for recreation"
      umount "$KERBEROS_KEYTAB" 2>/dev/null || true
      rm -f "$KERBEROS_KEYTAB"
    fi
  fi

  # Attempt domain join
  show_info "Attempting to join domain..."
  debug "Running: adcli join $domain --verbose"

  until adcli join --user="$ad_user" "$domain" --verbose; do
    show_error "Failed to join the Active Directory domain."
    debug "Domain join failed"
    prompt_confirm "Retry domain join?" || return 1
  done

  show_success "Successfully joined domain: $domain"
  debug "Domain join completed successfully"

  # Recreate exact logic from sssd.nix: copy keytab to persistent storage
  if [[ -n $storage_mount_path ]]; then
    debug "StorageVM detected: copying keytab to persistent storage"
    rm -f "${storage_mount_path}$KERBEROS_KEYTAB" 2>/dev/null || true
    cp "$KERBEROS_KEYTAB" "${storage_mount_path}$KERBEROS_KEYTAB"
    mount --bind "${storage_mount_path}$KERBEROS_KEYTAB" "$KERBEROS_KEYTAB"
    debug "Keytab copied to persistent storage: ${storage_mount_path}$KERBEROS_KEYTAB"
  fi

  return 0
}

# =============================================================================
# USER MANAGEMENT OPERATIONS
# =============================================================================

# Create a new systemd-homed user account
create_user() {
  debug "Starting user creation"

  # Check for FIDO2 support
  check_fido_support

  # Show configuration summary
  show_info "User Configuration Summary:"
  show_section \
    "Username:     $USERNAME" \
    "Real name:    $REALNAME" \
    "User ID:      $USER_ID" \
    "Groups:       $USER_GROUPS" \
    "Home size:    ${HOME_SIZE}MB" \
    "Filesystem:   $FS_TYPE" \
    "Shell:        $USER_SHELL" \
    ${FIDO_AUTH:+"FIDO2 Device:  ${FIDO_SUPPORT:-Not configured}"} \
    "Recovery Key: $RECOVERY_KEY"
  echo ""

  if ! $NON_INTERACTIVE; then
    if ! prompt_confirm "Create user with these settings?" "Create user" "Cancel"; then
      debug "User creation cancelled"
      return 1
    fi
  fi

  # Build base homectl command
  local homectl_args=(
    --real-name="$REALNAME"
    --skel=/etc/skel
    --storage=luks
    --luks-pbkdf-type=argon2id
    --fs-type="$FS_TYPE"
    --disk-size="$HOME_SIZE"M
    --drop-caches=true
    --nosuid=true
    --noexec=true
    --nodev=true
    --uid="$USER_ID"
    --member-of="$USER_GROUPS"
    --shell="$USER_SHELL"
    --enforce-password-policy=true
    --fido2-device="$FIDO_SUPPORT"
    --recovery-key="$RECOVERY_KEY"
  )

  # Add home directory if specified (otherwise let systemd-homed use default)
  if [[ -n $USER_HOME_DIRECTORY ]]; then
    homectl_args+=(--home-dir="$USER_HOME_DIRECTORY")
  fi

  # Add realm for AD users
  if $AD_MODE; then
    homectl_args+=(--realm="$AD_REALM")
  fi

  # Create systemd-homed user account
  if ! homectl create "$USERNAME" "${homectl_args[@]}"; then
    debug "An error occurred while creating the user account."
    show_error "User creation failed. Please check the debug log for details."

    if $FIDO_AUTH && [[ -n $FIDO_SUPPORT ]]; then
      debug "(HINT: You may have inserted a FIDO2/Yubikey after boot.)"
      debug "(      - If you want to use a FIDO2 device, please restart the machine with the device inserted.)"
      debug "(      - If you DONT want to use a FIDO2 device, please remove it and continue.)"
    fi

    show_error "Failed to create user. Check debug log for details."
    return 1
  else
    show_success "User '$USERNAME' created successfully!"
    debug "User creation completed successfully"
    return 0
  fi
}

# =============================================================================
# STATE-BASED SCREEN FUNCTIONS
# =============================================================================

# System setup state screen
screen_system_setup() {
  clear
  show_header "System Setup"
  show_info "Configure domain join and fleet enrollment."
  gum style --foreground="$COLOR_DEBUG" --italic \
    "Press ESC to restart • Press Ctrl+C to exit"
  echo ""

  # Check if already domain joined
  if is_domain_joined; then
    show_success "Already joined to domain: $AD_REALM"
    if $USER_MODE; then
      goto_state "USER_TYPE_SELECT"
    else
      goto_state "COMPLETE"
    fi
    return
  fi

  # Show current AD configuration status
  if [[ -n $AD_DOMAIN ]]; then
    show_info "AD Domain configured: $AD_DOMAIN"
  else
    show_info "No AD domain configured"
  fi

  local choice
  choice=$(prompt_choice "Choose system setup option:" \
    "Join Active Directory domain" \
    "Skip domain join" \
    "Exit setup") || goto_state "EXIT"

  case "$choice" in
  "Join Active"*)
    if [[ -n $AD_DOMAIN ]]; then
      goto_state "AD_JOIN"
    else
      goto_state "AD_CONFIG"
    fi
    ;;
  "Skip"*)
    if $USER_MODE; then
      goto_state "USER_TYPE_SELECT"
    else
      goto_state "COMPLETE"
    fi
    ;;
  "Exit"*)
    goto_state "EXIT"
    ;;
  esac
}

# AD configuration state screen
screen_ad_config() {
  clear
  show_header "Active Directory Configuration"

  # Check network connectivity first
  if ! check_connectivity; then
    local choice
    choice=$(prompt_choice "Network setup required. What would you like to do?" \
      "Retest connection" \
      "Setup network" \
      "Go back") || goto_state "EXIT"

    case "$choice" in
    "Retest"*) ;; # Continue with config to retest
    "Setup network"*)
      goto_state "NETWORK_SETUP"
      return
      ;;
    "Go back"*)
      goto_state "SYSTEM_SETUP"
      return
      ;;
    esac
  fi

  # Configure AD parameters
  if configure_ad_parameters; then
    goto_state "AD_JOIN"
  else
    local choice
    choice=$(prompt_choice "AD configuration failed. How would you like to proceed?" \
      "Retry configuration" \
      "Setup network" \
      "Go back") || goto_state "EXIT"

    case "$choice" in
    "Retry"*) goto_state "AD_CONFIG" ;;
    "Setup network"*) goto_state "NETWORK_SETUP" ;;
    "Go back"*) goto_state "SYSTEM_SETUP" ;;
    esac
  fi
}

# AD join state screen
screen_ad_join() {
  clear
  show_header "Active Directory Domain Join"

  show_info "Joining domain: $AD_DOMAIN"

  if perform_ad_join; then
    if $USER_MODE; then
      goto_state "USER_TYPE_SELECT"
    else
      goto_state "COMPLETE"
    fi
  else
    local choice
    choice=$(prompt_choice "Domain join failed. How would you like to proceed?" \
      "Retry join" \
      "Reconfigure AD" \
      "Skip domain join") || goto_state "EXIT"

    case "$choice" in
    "Retry"*) goto_state "AD_JOIN" ;;
    "Reconfigure"*) goto_state "AD_CONFIG" ;;
    "Skip"*)
      if $USER_MODE; then
        goto_state "USER_TYPE_SELECT"
      else
        goto_state "COMPLETE"
      fi
      ;;
    esac
  fi
}

# User type selection state screen
screen_user_type_select() {
  clear
  show_header "User Setup"
  show_info "Add local or AD as systemd-homed users."
  gum style --foreground="$COLOR_DEBUG" --italic \
    "Press ESC to restart • Press Ctrl+C to exit"
  echo ""

  # Show current users
  local current_users
  current_users=$(homectl list | awk '/^$/ {exit} {print}' 2>/dev/null) || true
  if [[ -n $current_users ]]; then
    show_section "$current_users"
  else
    show_section "No existing users found."
  fi
  echo ""

  local choice
  choice=$(prompt_choice "Choose user management action:" \
    "Create local user" \
    "Add Active Directory user" \
    "Remove all users" \
    "Finish setup") || goto_state "EXIT"

  case "$choice" in
  "Create local"*) goto_state "LOCAL_USER_CREATE" ;;
  "Add Active"*) goto_state "AD_USER_SEARCH" ;;
  "Remove all"*)
    if remove_all_users; then
      show_success "All users removed"
    else
      show_error "Failed to remove some users"
    fi
    goto_state "USER_TYPE_SELECT"
    ;;
  "Finish"*) goto_state "COMPLETE" ;;
  esac
}

# Local user creation state screen
screen_local_user_create() {
  clear
  show_header "Create Local User"

  # Get user input - exit if user cancels
  if ! prompt_username || ! prompt_realname; then
    goto_state "EXIT"
    return
  fi

  # Create the user
  if create_user; then
    local choice
    choice=$(prompt_choice "User created successfully. What would you like to do next?" \
      "Back to user menu" \
      "Finish setup") || goto_state "EXIT"

    case "$choice" in
    "Back to user menu") goto_state "USER_TYPE_SELECT" ;;
    "Finish"*) goto_state "COMPLETE" ;;
    esac
  else
    local choice
    choice=$(prompt_choice "User creation failed. How would you like to proceed?" \
      "Try again" \
      "Back to user menu") || goto_state "EXIT"

    case "$choice" in
    "Try again") goto_state "LOCAL_USER_CREATE" ;;
    "Back to user menu") goto_state "USER_TYPE_SELECT" ;;
    esac
  fi
}

# AD user search state screen
screen_ad_user_search() {
  clear
  show_header "Active Directory User Search"

  # Check network connectivity
  if ! check_connectivity; then
    local choice
    choice=$(prompt_choice "Network connection required for AD search. What would you like to do?" \
      "Setup network" \
      "Go back") || goto_state "EXIT"

    case "$choice" in
    "Setup network"*)
      goto_state "NETWORK_SETUP"
      return
      ;;
    "Go back"*)
      goto_state "USER_TYPE_SELECT"
      return
      ;;
    esac
  fi

  # Configure AD if needed
  if [[ -z $AD_DOMAIN ]]; then
    if configure_ad_parameters; then
      show_success "AD configured successfully"
    else
      goto_state "USER_TYPE_SELECT"
      return
    fi
  fi

  # Get AD username if needed (reuse existing if available)
  if [[ ! -r $KERBEROS_KEYTAB ]]; then
    if [[ -z $AD_USERNAME ]]; then
      AD_USERNAME=$(prompt_input "Enter AD admin username:" "domain username") || {
        goto_state "EXIT"
        return
      }
      debug "AD credentials entered for user: $AD_USERNAME"
    else
      debug "Reusing existing AD credentials for user: $AD_USERNAME"
    fi
  fi

  # Get search filter
  local search_filter
  search_filter=$(prompt_input "Enter search filter (optional):" "leave blank for all users") || {
    goto_state "EXIT"
    return
  }

  # Perform LDAP search
  show_info "Searching LDAP for users..."
  local ldap_results
  if ! ldap_results=$(query_ldap "$LDAP_SERVER" "$BASE_DN" "$AD_USERNAME" "$AD_DOMAIN" "$search_filter"); then
    show_error "LDAP search failed"
    local choices=("Try again")
    # Add credential option if not using keytab
    if [[ ! -r $KERBEROS_KEYTAB && -n $AD_USERNAME ]]; then
      choices+=("Use different credentials")
    fi
    choices+=("Change AD configuration" "Go back")

    local choice
    choice=$(prompt_choice "LDAP search failed. How would you like to proceed?" "${choices[@]}") || goto_state "EXIT"

    case "$choice" in
    "Try again"*) goto_state "AD_USER_SEARCH" ;;
    "Use different credentials")
      # Clear credentials to force re-entry
      AD_USERNAME=""
      goto_state "AD_USER_SEARCH"
      ;;
    "Change AD configuration")
      # Reset AD configuration to config defaults
      init_ad_config
      goto_state "AD_USER_SEARCH"
      ;;
    "Go back"*) goto_state "USER_TYPE_SELECT" ;;
    esac
    return
  fi

  # Process search results
  local users_found=false
  local -a ad_users=()

  while IFS='|' read -r name display_name user_id group_id home_dir shell; do
    [[ -z $name ]] && continue
    users_found=true
    ad_users+=("$name|$display_name|$user_id|$group_id|$home_dir|$shell")
  done <<<"$ldap_results"

  if ! $users_found; then
    show_warning "No users found with current filter"
    goto_state "AD_USER_SEARCH"
    return
  fi

  # Present users for selection
  for user_entry in "${ad_users[@]}"; do
    IFS='|' read -r name display_name user_id group_id home_dir shell <<<"$user_entry"

    clear
    show_header "Active Directory User Search"
    show_info "Found AD user matching your search '$search_filter'"
    show_section \
      "Username:     $name" \
      "Display Name: $display_name" \
      "UID:          $user_id" \
      "GID:          $group_id" \
      ${home_dir:+"Home Dir:     $home_dir"} \
      ${shell:+"Shell:        $shell"}

    # Check if user already exists
    if homectl inspect "$name" >/dev/null 2>&1; then
      debug "User '$name' already exists. Skipping."
      continue
    fi

    local choice
    choice=$(prompt_choice "Would you like to enroll this AD user?" \
      "Enroll user" \
      "Skip this user" \
      "Stop searching") || goto_state "EXIT"

    case "$choice" in
    "Enroll user"*)
      # Set user variables and create
      USERNAME="$name"
      REALNAME="$display_name"
      USER_ID="$user_id"
      USER_HOME_DIRECTORY="$home_dir"
      USER_SHELL="$shell"
      AD_MODE=true

      if create_user; then
        show_success "User '$USERNAME' enrolled successfully!"
        break
      else
        show_error "Failed to enroll user '$USERNAME'"
      fi
      ;;
    "Skip"*) continue ;;
    "Stop searching"*) break ;;
    esac
  done

  # Ask what to do next
  local choices=("Search again")
  # Add credential option if not using keytab
  if [[ ! -r $KERBEROS_KEYTAB && -n $AD_USERNAME ]]; then
    choices+=("Use different credentials")
  fi
  choices+=("Change AD configuration" "Back to user menu" "Finish setup")

  local choice
  choice=$(prompt_choice "Choose next action:" "${choices[@]}") || goto_state "EXIT"

  case "$choice" in
  "Search again"*) goto_state "AD_USER_SEARCH" ;;
  "Use different"*)
    # Clear credentials to force re-entry
    AD_USERNAME=""
    goto_state "AD_USER_SEARCH"
    ;;
  "Change AD configuration")
    # Reset AD configuration to config defaults
    init_ad_config
    goto_state "AD_USER_SEARCH"
    ;;
  "Back to user menu") goto_state "USER_TYPE_SELECT" ;;
  "Finish"*) goto_state "COMPLETE" ;;
  esac
}

# Network setup utility state screen
screen_network_setup() {
  clear
  show_header "Network Setup"

  # Use existing network connectivity function
  if ! check_connectivity; then
    goto_state "EXIT"
    return
  fi

  # Always return to previous state when done
  goto_state "$PREVIOUS_STATE"
}

# Completion state screen
screen_complete() {
  clear
  show_header "Setup Complete"

  show_success "Ghaf provisioning completed successfully!"

  local status_lines=()
  if is_domain_joined; then
    status_lines+=("Domain joined: $AD_REALM")
  fi

  local user_count
  user_count=$(homectl list | tail -n +2 | awk '/^$/ {exit} {count++} END {print count+0}' 2>/dev/null)
  if [[ $user_count -gt 0 ]]; then
    status_lines+=("Users created: $user_count")
  fi

  if [[ ${#status_lines[@]} -gt 0 ]]; then
    show_section "${status_lines[@]}"
  fi

  echo ""
  prompt_confirm "Press Enter to exit..." || true
  goto_state "EXIT"
}

# Non-interactive 1: Automated user creation with pre-provided arguments
non_interactive_setup() {

  # Validate required parameters
  if [[ -z $USERNAME ]]; then
    show_error "Username is required. Use --username or run interactive mode"
    exit 1
  fi

  if [[ -z $REALNAME ]]; then
    show_error "Real name is required. Use --realname or run interactive mode"
    exit 1
  fi

  if [[ -z $PASSWORD ]]; then
    show_error "Password is required. Use --password or run interactive mode"
    exit 1
  fi

  # Validate username
  if ! set_username "$USERNAME"; then
    show_error "Invalid username."
    exit 1
  fi

  # Validate real name
  if ! set_realname "$REALNAME"; then
    show_error "Invalid real name."
    exit 1
  fi

  # Set cleanup for passwords
  # shellcheck disable=SC2329  # Function called indirectly via cleanup registry
  cleanup_passwords() {
    unset PASSWORD NEWPASSWORD 2>/dev/null
  }
  register_cleanup cleanup_passwords

  # Set environment variables for non-interactive password handling
  export PASSWORD
  export NEWPASSWORD="$PASSWORD"

  # Disable recovery key for non-interactive mode
  RECOVERY_KEY=false

  echo "Creating user account with the following settings:"
  echo "Username:     $USERNAME"
  echo "Real name:    $REALNAME"
  echo "Groups:       $USER_GROUPS"
  echo "Home size:    ${HOME_SIZE}MB"
  echo "User ID:      $USER_ID"
  echo "Filesystem:   $FS_TYPE"
  echo "FIDO2:        $FIDO_AUTH"
  echo "Recovery key: $RECOVERY_KEY"

  if create_user; then
    echo "User '$USERNAME' created successfully!"
  else
    echo "Failed to create user account." >&2
  fi
}

# Non-interactive 2: Automated user removal
remove_all_users() {
  debug "Removing all enrolled users..."
  local user
  while IFS= read -r user; do
    [[ -n $user ]] || continue
    debug "Removing user: $user"
    if homectl remove "$user"; then
      debug "Removed user: $user"
    else
      debug "Failed to remove user '$user'. Aborting."
      return 1
    fi
  done < <(homectl list | tail -n +2 | awk '/^$/ {exit} {print $1}' 2>/dev/null)

  debug "User removal completed."
}

# =============================================================================
# MAIN ENTRY
# =============================================================================

# Main script entry point
main() {

  # Ensure TERM=linux
  export TERM=linux

  # Check if running as root
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must run with root privileges." >&2
    exit 1
  fi

  # Parse arguments
  parse_args "$@"

  # Load and apply configuration
  if ! load_configuration; then
    show_warning "Configuration file not found or invalid. Using defaults."
    debug "No configuration loaded - using defaults"
  fi

  # Apply configuration values (CLI takes precedence over config)
  apply_configuration

  # Validate configuration
  if ! validate_configuration; then
    show_error "Configuration validation failed. Please check the debug log for details."
    debug "Configuration validation failed"
    exit 1
  fi

  # Handle special cases for non-interactive and remove users
  if $NON_INTERACTIVE; then
    non_interactive_setup
  elif $REMOVE_USERS; then
    remove_all_users
  else
    # Interactive modes
    local mode="user"
    if $SYSTEM_MODE && $USER_MODE; then
      mode="full"
    elif $SYSTEM_MODE; then
      mode="system"
    fi

    # Set up display
    brightnessctl set 100% >/dev/null 2>&1 || true

    # Run interactive state machine
    start_state_machine "$mode"
  fi
}

# Execute main function with all arguments
main "$@"
