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

# System paths and configuration
KERBEROS_KEYTAB="/etc/krb5.keytab"
STORAGE_MOUNT_PATH=""

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
AD_DOMAIN=""
AD_REALM=""
AD_SERVER=""
LDAP_SERVER=""
BASE_DN=""
AD_USERNAME=""
declare -A AVAILABLE_DOMAINS=()

# Runtime states
DOMAIN_SELECT_CONTEXT=""
NON_INTERACTIVE=false
REMOVE_USERS=false

# Global cleanup registry
cleanup_funcs=""

# =============================================================================
# STATE MACHINE
# =============================================================================

# State machine variables
CURRENT_STATE=""

# State function mapping
declare -A STATE_FUNCTIONS=(
  ["MAIN_MENU"]="screen_main_menu"
  ["DOMAIN_SELECT"]="screen_domain_select"
  ["AD_JOIN"]="screen_ad_join"
  ["LOCAL_USER_CREATE"]="screen_local_user_create"
  ["AD_USER_SEARCH"]="screen_ad_user_search"
  ["USER_REMOVE"]="screen_user_remove"
)

# State transition helpers
goto_state() {
  CURRENT_STATE="$1"
  debug "Transitioning to state: $CURRENT_STATE"
}

# State machine entry point
start_state_machine() {
  # Always start at main menu for interactive mode
  CURRENT_STATE="MAIN_MENU"
  debug "Starting state machine at: $CURRENT_STATE"
  while [[ $CURRENT_STATE != "EXIT" ]]; do

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
  cleanup_and_exit
}

# =============================================================================
# CORE UTILITIES & SYSTEM SETUP
# =============================================================================

# Cleanup function that preserves exit code
cleanup_and_exit() {
  local exit_code=$?
  debug "Running cleanup with exit code: $exit_code"
  run_cleanups
  exit $exit_code
}

# Set up signal handlers to ensure cleanup on exit
trap cleanup_and_exit EXIT INT TERM

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

# Debug logging function
debug() {
  if [[ -n ${INVOCATION_ID:-} ]]; then
    echo "$*" | systemd-cat -p debug
  else
    echo "[DEBUG] $*" >&2
  fi
}

# =============================================================================
# CONFIGURATION FILE HANDLING
# =============================================================================

# Default configuration file location
CONFIG_FILE="/etc/ghaf/provisioning.json"

# Configuration variables (loaded from JSON)
declare -A CONFIG=()

# Load configuration from JSON file into associative array
load_config_file() {
  debug "Loading configuration from $CONFIG_FILE"

  if [[ ! -f $CONFIG_FILE ]]; then
    debug "Configuration file not found: $CONFIG_FILE"
    return 0
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
  [[ -z $USERNAME ]] && USERNAME=$(config_get "user_config.username" "")
  [[ -z $REALNAME ]] && REALNAME=$(config_get "user_config.realname" "")
  [[ -z $HOME_SIZE ]] && HOME_SIZE=$(config_get "user_config.home_size" "10000")
  [[ -z $USER_ID ]] && USER_ID=$(config_get "user_config.uid" "")
  [[ -z $FS_TYPE ]] && FS_TYPE=$(config_get "user_config.fs_type" "ext4")
  [[ -z $USER_SHELL ]] && USER_SHELL=$(config_get "user_config.shell" "/run/current-system/sw/bin/bash")
  [[ -z $USER_GROUPS ]] && USER_GROUPS=$(config_get "user_config.groups" "users")

  # FIDO auth from config
  if ! $FIDO_AUTH; then
    config_enabled "user_config.fido_auth" && FIDO_AUTH=true
  fi

  # Initialize Active Directory configuration from config
  # Load available domains
  debug "Loading available domains from config"

  # Load all domains from the new format
  local domain_keys
  domain_keys=$(jq -r '.ad_config.domains // {} | keys[]' "$CONFIG_FILE" 2>/dev/null) || true

  while IFS= read -r domain_name; do
    [[ -z $domain_name ]] && continue

    local domain_config
    domain_config=$(config_get "ad_config.domains.$domain_name.domain")
    local realm_config
    realm_config=$(config_get "ad_config.domains.$domain_name.realm")
    local ad_server_config
    ad_server_config=$(config_get "ad_config.domains.$domain_name.ad_server")
    local ldap_server_config
    ldap_server_config=$(config_get "ad_config.domains.$domain_name.ldap_server")

    # Store domain info
    AVAILABLE_DOMAINS["$domain_name"]="$domain_config|$realm_config|$ad_server_config|$ldap_server_config"
    debug "Domain '$domain_name' ($domain_config) is available"

  done <<<"$domain_keys"

  # Load storage mount path from config
  [[ -z $STORAGE_MOUNT_PATH ]] && STORAGE_MOUNT_PATH=$(config_get "storage.mount_path" "")

  debug "Configuration applied."
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
  debug "SUCCESS: $*"
}

# Error message wrapper
show_error() {
  gum style --foreground="$COLOR_ERROR" "$*" >&2
  debug "ERROR: $*"
}

# Info message wrapper
show_info() {
  gum style --foreground="$COLOR_INFO" --margin="$SPACING_INFO_BOTTOM" "$@"
  debug "INFO: $*"
}

# Warning message wrapper
show_warning() {
  gum style --foreground="$COLOR_WARNING" "$*"
  debug "WARNING: $*"
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

# Wait for user confirmation before continuing
wait_for_user() {
  local message="${1:-Press any key to continue...}"
  echo ""
  gum style --foreground="$COLOR_INFO" --italic "$message"
  read -n 1 -s -r
}

# =============================================================================
# STATUS FUNCTIONS
# =============================================================================

# Check if there are any domains configured
has_configured_domains() {
  [[ ${#AVAILABLE_DOMAINS[@]} -gt 0 ]]
}

# Check if AD is configured
has_ad_config() {
  [[ -n $AD_DOMAIN && -n $AD_SERVER && -n $LDAP_SERVER ]]
}

# Check if systemd-homed is available and running
has_systemd_homed() {
  systemctl is-active --quiet systemd-homed 2>/dev/null
}

# =============================================================================
# INPUT VALIDATION & PROCESSING
# =============================================================================

# Display usage information
usage() {
  cat <<EOF
user-provision - Ghaf user provisioning service

Usage: user-provision [OPTIONS]

OPTIONS:
  --username USER         Username for the new user account
  --realname NAME         Real/full name for the user
  --groups GROUPS         Comma-separated list of additional groups
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
  user-provision

  User setup with options:
    user-provision --username alice --realname "Alice Smith" --fido

  Non-interactive user creation:
    user-provision --non-interactive --username bob --realname "Bob Jones" --password "SecurePass123"

  Remove all users:
    user-provision --remove

EOF
}

# Parse command-line arguments
parse_args() {

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
  while true; do
    local username_input
    username_input=$(prompt_input "Enter username:" "lowercase, no spaces") || return 1

    if set_username "$username_input"; then
      show_success "Username: $USERNAME"
      break
    else
      show_error "Invalid or empty username."
      show_error "Must be lowercase letters, numbers, underscore, or dash only."
    fi
  done
}

# Prompt user to enter a real name
prompt_realname() {
  while true; do
    local realname_input
    realname_input=$(prompt_input "Enter full name:" "your display name") || return 1

    if set_realname "$realname_input"; then
      show_success "Real name: $REALNAME"
      break
    else
      show_error "Invalid or empty name. Letters and spaces only."
    fi
  done
}

# =============================================================================
# NETWORK & CONNECTIVITY FUNCTIONS
# =============================================================================

# Check AD server connectivity
check_ad_connectivity() {
  # Only check if AD is configured
  if [[ -z $AD_SERVER ]]; then
    debug "No AD server configured, skipping connectivity check"
    return 0
  fi

  # Interactive network setup loop for AD connectivity
  while true; do

    # Show connectivity check
    if show_progress "Checking AD server connectivity..." ping -c 1 -W 3 "$AD_SERVER"; then
      show_success "AD server reachable: $AD_SERVER"
    else
      show_warning "Cannot reach AD server: $AD_SERVER"
    fi

    # Check LDAP/LDAPS connectivity based on protocol
    if [[ -n $LDAP_SERVER ]]; then

      # Extract host and determine protocol/port
      local ldap_host="$LDAP_SERVER"
      local ldap_port=""
      local protocol=""

      if [[ $LDAP_SERVER =~ ^ldaps:// ]]; then
        protocol="LDAPS"
        ldap_port="636"
        ldap_host="${ldap_host#ldaps://}"
      elif [[ $LDAP_SERVER =~ ^ldap:// ]]; then
        protocol="LDAP"
        ldap_port="389"
        ldap_host="${ldap_host#ldap://}"
      else
        # Default to LDAP if no protocol specified
        protocol="LDAP"
        ldap_port="389"
      fi

      ldap_host="${ldap_host%%/*}" # Remove any path
      # Check if port is specified in URL, otherwise use default
      if [[ $ldap_host =~ :[0-9]+$ ]]; then
        ldap_port="${ldap_host##*:}"
        ldap_host="${ldap_host%%:*}"
      fi

      if show_progress "Checking $protocol server connectivity to $LDAP_SERVER" timeout 2 nc -z "$ldap_host" "$ldap_port" >/dev/null 2>&1; then
        show_success "$protocol server reachable: $LDAP_SERVER"
        return 0
      else
        show_warning "Cannot reach $protocol server: $LDAP_SERVER"
      fi
    else
      debug "No LDAP server configured, skipping LDAP connectivity check"
      return 0
    fi

    # No connectivity, show error and prompt for action
    show_error "Cannot connect to AD backend - please check network configuration or AD server settings."

    echo ""
    local choice
    choice=$(prompt_choice "Server not reachable. Choose action:" \
      "Test connection" \
      "Setup WiFi" \
      "Skip AD setup") || return 1

    debug "AD connectivity choice selected: '$choice'"

    case "$choice" in
    "Test connection")
      # continue loop to retest
      ;;
    "Setup WiFi")
      setup_wifi
      ;;
    "Skip AD setup")
      show_warning "Continuing without AD server connectivity"
      return 0
      ;;
    *)
      show_error "Unknown choice: '$choice'"
      ;;
    esac
  done
}

# Setup WiFi connection
setup_wifi() {

  show_info "Scanning for available WiFi networks..."

  if ! nmcli device wifi list; then
    show_error "Could not scan for WiFi networks"
    wait_for_user
    return
  fi

  echo ""
  local wifi_ssid
  wifi_ssid=$(prompt_input "Enter WiFi network name:" "network SSID") || return 1

  if nmcli device wifi connect "$wifi_ssid" --ask; then
    show_success "Successfully connected to '$wifi_ssid'"
  else
    show_error "Failed to connect to WiFi network '$wifi_ssid'"
    nmcli connection delete "$wifi_ssid" 2>/dev/null || true
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

# Set AD configuration for selected domain
set_ad_config_for_domain() {
  local domain_name="$1"

  if [[ -z ${AVAILABLE_DOMAINS[$domain_name]:-} ]]; then
    debug "Domain '$domain_name' not found in available domains"
    return 1
  fi

  # Parse domain configuration
  local domain_info="${AVAILABLE_DOMAINS[$domain_name]}"
  IFS='|' read -r AD_DOMAIN AD_REALM AD_SERVER LDAP_SERVER <<<"$domain_info"

  # Handle domain/realm relationship
  if [[ -n $AD_DOMAIN && -n $AD_REALM ]]; then
    debug "Using configured domain: $AD_DOMAIN and realm: $AD_REALM"
  elif [[ -n $AD_REALM && -z $AD_DOMAIN ]]; then
    AD_DOMAIN="${AD_REALM,,}"
    debug "Derived domain '$AD_DOMAIN' from realm '$AD_REALM'"
  elif [[ -n $AD_DOMAIN && -z $AD_REALM ]]; then
    AD_REALM="${AD_DOMAIN^^}"
    debug "Derived realm '$AD_REALM' from domain '$AD_DOMAIN'"
  fi

  BASE_DN=$(get_base_dn "$AD_DOMAIN")

  debug "AD config set for domain '$domain_name'"
  debug "  Domain: $AD_DOMAIN, Realm: $AD_REALM"
  debug "  AD: $AD_SERVER, LDAP: $LDAP_SERVER"
}

# Convert domain name to LDAP Base DN format
get_base_dn() {
  local domain="$1"
  echo "DC=${domain//./,DC=}"
}

# Query LDAP for AD users with authentication and format output as pipe-delimited
query_ldap() {
  local server="$1"
  local base_dn="$2"
  local ad_user="$3"
  local name_filter="$4"

  # Build LDAP filter for users (supports both AD and RFC2307)
  local ldap_filter="(|(objectClass=user)(objectClass=posixAccount))"
  if [[ -n $name_filter ]]; then
    local name_filter_escaped
    name_filter_escaped=$(echo "$name_filter" |
      awk '{gsub(/\\/, "\\\\"); gsub(/\(/, "\\("); \
            gsub(/\)/, "\\)"); gsub(/\*/, "\\*"); print}')
    ldap_filter="(&$ldap_filter(|"
    ldap_filter+="(sAMAccountName=*$name_filter_escaped*)"
    ldap_filter+="(displayName=*$name_filter_escaped*)"
    ldap_filter+="(uid=*$name_filter_escaped*)"
    ldap_filter+="(cn=*$name_filter_escaped*)))"
  fi

  # Ensure we have a valid Kerberos ticket for GSSAPI authentication
  if ! klist -s 2>/dev/null; then

    # No valid ticket, acquire one
    if [[ -r $KERBEROS_KEYTAB ]]; then
      debug "Using machine keytab authentication"
      # Acquire machine ticket
      MACHINE_HOSTNAME=$(hostname -f | tr '[:lower:]' '[:upper:]')
      debug "Using VM hostname from system: $MACHINE_HOSTNAME"
      KERBEROS_PRINCIPAL="$MACHINE_HOSTNAME\$@$AD_REALM"
      debug "Acquiring Kerberos ticket for principal: $KERBEROS_PRINCIPAL"

      if ! kinit -kt "$KERBEROS_KEYTAB" "$KERBEROS_PRINCIPAL"; then
        show_error "Error: kinit failed to acquire a Kerberos ticket."
        show_error "Check the principal name, keytab content, and network connection to the KDC."
        return 1
      fi
    else
      debug "Using user credential authentication"

      # Use file-based credential cache when KCM is not available
      KRB5CCNAME="FILE:$(mktemp -t krb5cc_XXXXXXXX)"
      export KRB5CCNAME

      # Register cleanup to destroy user ticket (only for user tickets)
      # shellcheck disable=SC2329  # Function called indirectly via cleanup registry
      cleanup_user_ticket() {
        kdestroy 2>/dev/null || true
        [[ -n ${KRB5CCNAME:-} ]] && rm -f "${KRB5CCNAME#FILE:}" 2>/dev/null || true
        unset KRB5CCNAME
      }
      register_cleanup cleanup_user_ticket

      # Acquire user ticket
      if ! kinit "$ad_user@$AD_REALM" </dev/tty >/dev/tty 2>/dev/tty; then
        show_error "Error: kinit failed to acquire a Kerberos ticket for user."
        show_error "Check the username, password, and network connection to the KDC."
        return 1
      fi
    fi
  else
    debug "Using existing valid Kerberos ticket"
  fi

  # Perform LDAP search with GSSAPI (unified for both machine and user auth)
  local ldap_output
  if ! ldap_output=$(timeout "$LDAP_SEARCH_TIMEOUT" ldapsearch -H "$server" -b "$base_dn" \
    -Y GSSAPI \
    "$ldap_filter" \
    sAMAccountName displayName uid cn uidNumber gidNumber homeDirectory loginShell \
    -LLL -o ldif_wrap=no 2>&1); then
    show_error "LDAP query failed: $ldap_output"
    return 1
  fi

  # Parse LDAP output and format as pipe-delimited (RFC2307 compliant)
  echo "$ldap_output" |
    awk -v OFS='|' '
      /^uid: / { uid = substr($0, index($0, ": ") + 2) }
      /^cn: / { cn = substr($0, index($0, ": ") + 2) }
      /^uidNumber: / { uidNumber = substr($0, index($0, ": ") + 2) }
      /^gidNumber: / { gidNumber = substr($0, index($0, ": ") + 2) }
      /^homeDirectory: / { homeDirectory = substr($0, index($0, ": ") + 2) }
      /^loginShell: / { loginShell = substr($0, index($0, ": ") + 2) }
      /^$/ {
        if (uid && uidNumber) {
          print uid, (cn ? cn : uid), uidNumber, gidNumber, homeDirectory, loginShell
        }
        uid = cn = uidNumber = gidNumber = homeDirectory = loginShell = ""
      }
      END {
        if (uid && uidNumber) {
          print uid, (cn ? cn : uid), uidNumber, gidNumber, homeDirectory, loginShell
        }
      }'
}

# Check if system is already joined to a domain using adcli
is_domain_joined() {
  adcli testjoin >/dev/null 2>&1
}

# Perform Active Directory domain join
perform_ad_join() {
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
    return 0
  fi

  show_info "Joining domain: $domain (realm: $realm)"

  # Ensure network connectivity (blocks until connected or user exits)
  if ! check_ad_connectivity; then
    return 1
  fi

  # Prompt for admin credentials (interactive mode only)
  local ad_user=""
  while [[ -z $ad_user ]]; do
    ad_user=$(prompt_input "Enter admin username:" "e.g., admin") || return 1
  done

  # Handle existing keytab if persistent storage is available to force re-creation
  if [[ -n $STORAGE_MOUNT_PATH ]]; then
    if [[ -e $KERBEROS_KEYTAB ]]; then
      debug "Persistent storage detected: removing existing keytab for recreation"
      umount "$KERBEROS_KEYTAB" 2>/dev/null || true
      rm -f "$KERBEROS_KEYTAB"
    fi
  fi

  # Attempt domain join
  show_info "Attempting to join domain..."

  until adcli join --user="$ad_user" --domain="$domain" --domain-realm="$realm" --verbose; do
    show_error "Failed to join the Active Directory domain."
    prompt_confirm "Retry join?" || return 1
  done

  show_success "Successfully joined domain: $domain"

  # Copy and remount keytab to persistent storage
  if [[ -n $STORAGE_MOUNT_PATH ]]; then
    debug "Persistent storage detected: copying keytab to persistent storage"
    rm -f "${STORAGE_MOUNT_PATH}$KERBEROS_KEYTAB" 2>/dev/null || true
    cp "$KERBEROS_KEYTAB" "${STORAGE_MOUNT_PATH}$KERBEROS_KEYTAB"
    mount --bind "${STORAGE_MOUNT_PATH}$KERBEROS_KEYTAB" "$KERBEROS_KEYTAB"
    debug "Keytab copied to persistent storage: ${STORAGE_MOUNT_PATH}$KERBEROS_KEYTAB"
  fi

  return 0
}

# =============================================================================
# USER MANAGEMENT OPERATIONS
# =============================================================================

# Create a new systemd-homed user account
create_user() {

  if ! $NON_INTERACTIVE; then
    # Check for FIDO2 support
    check_fido_support
  fi

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
    --recovery-key="$RECOVERY_KEY"
  )

  # Add home directory if specified (otherwise let systemd-homed use default)
  [[ -n $USER_HOME_DIRECTORY ]] && homectl_args+=(--home-dir="$USER_HOME_DIRECTORY")

  # Add FIDO2 device if enabled and supported
  [[ -n $FIDO_SUPPORT ]] && homectl_args+=(--fido2-device="$FIDO_SUPPORT")

  # Add realm for AD users
  [[ -n $AD_REALM ]] && homectl_args+=(--realm="$AD_REALM")

  # Create systemd-homed user account
  if ! homectl create "$USERNAME" "${homectl_args[@]}"; then
    show_error "User creation (homectl) failed. Please check the debug log for details."
    return 1
  else
    show_success "User '$USERNAME' created successfully!"
    return 0
  fi
}

# =============================================================================
# SCREEN FUNCTIONS
# =============================================================================

# Main menu screen
screen_main_menu() {
  while true; do
    clear
    show_header "Ghaf User Provisioning"

    # Build menu options dynamically based on state
    local options=()

    # Show AD-related options if configured domains are available
    if has_configured_domains && ! has_systemd_homed; then

      # Domain Configuration section
      show_info "Domain Configuration:"

      # Show currently joined domain(s) if any
      if is_domain_joined; then
        local joined_domains
        joined_domains=$(klist -k 2>/dev/null |
          awk -F'@' '/@/ && NF>1 {domains[$2]=1} \
                     END {for (d in domains) printf "%s ", d}' |
          awk '{$1=$1; print}') || true
        if [[ -n $joined_domains ]]; then
          show_section "  Domain: $joined_domains"
        else
          show_section "  Domain: joined (unknown)"
        fi
      else
        show_section "  Domain: no domain joined"
      fi
      echo ""

      # AD join option - show if domains available and not joined
      if ! is_domain_joined && has_configured_domains; then
        options+=("Join Active Directory domain")
      fi

    fi

    # Show user creation options if systemd-homed is available
    if has_systemd_homed; then
      # Homed Management section
      echo ""
      show_info "Homed Management:"

      local current_users
      current_users=$(homectl list | awk '/^$/ {exit} {print}' 2>/dev/null) || true
      if [[ -n $current_users ]]; then
        show_section "$current_users"
      fi

      options+=("Create local user")

      # AD user enrollment - available if configured domains exist
      if has_configured_domains; then
        options+=("Enroll AD user to homed")
      fi

      options+=("Remove all users")
    fi

    # Exit option
    options+=("Exit provisioning")

    # Show menu and get choice
    echo ""
    local choice
    choice=$(prompt_choice "Select an option:" "${options[@]}") || {
      # User pressed ESC or Ctrl+C
      if prompt_confirm "Exit setup?" "Yes, exit" "No, continue"; then
        goto_state "EXIT"
        return
      fi
      continue
    }

    # Handle menu selection
    case "$choice" in
    "Join Active Directory domain")
      if has_configured_domains; then
        goto_state "DOMAIN_SELECT"
      else
        show_error "No domains configured for joining"
        wait_for_user
      fi
      return
      ;;
    "Create local user")
      goto_state "LOCAL_USER_CREATE"
      return
      ;;
    "Enroll AD user to homed")
      if has_ad_config; then
        goto_state "AD_USER_SEARCH"
      else
        DOMAIN_SELECT_CONTEXT="AD_USER_SEARCH"
        goto_state "DOMAIN_SELECT"
      fi
      return
      ;;
    "Remove all users")
      goto_state "USER_REMOVE"
      return
      ;;
    "Exit provisioning")
      if prompt_confirm "Exit setup?" "Yes, exit" "No, continue"; then
        goto_state "EXIT"
        return
      fi
      ;;
    esac
  done
}

# User removal screen
screen_user_remove() {
  clear
  show_header "Remove Users"

  local users
  users=$(homectl list --no-legend 2>/dev/null | awk '{print $1}')

  if [[ -z $users ]]; then
    show_info "No users to remove"
    wait_for_user
    goto_state "MAIN_MENU"
    return
  fi

  show_info "Select users to remove:"
  echo "$users"
  echo ""

  if prompt_confirm "Remove all users?" "Yes, remove all" "No, cancel"; then
    if remove_all_users; then
      show_success "All users removed"
    else
      show_error "Failed to remove some users"
    fi
    wait_for_user
  fi

  goto_state "MAIN_MENU"
}

# Domain selection state screen
screen_domain_select() {
  clear
  show_header "Select AD Domain"
  show_info "Choose an Active Directory domain to continue."
  gum style --foreground="$COLOR_DEBUG" --italic \
    "Press ESC to restart • Press Ctrl+C to exit"
  echo ""

  # Build choice list from all available domains
  local choices=()
  for domain_name in "${!AVAILABLE_DOMAINS[@]}"; do
    local domain_info="${AVAILABLE_DOMAINS[$domain_name]}"
    IFS='|' read -r domain_fqdn _ _ _ <<<"$domain_info"
    choices+=("$domain_name ($domain_fqdn)")
  done
  choices+=("Go back")

  # Let user select domain
  local choice
  choice=$(prompt_choice "Select domain:" "${choices[@]}") || goto_state "MAIN_MENU"

  case "$choice" in
  *)
    # Extract domain name from choice
    local selected_domain="${choice// (*/}"

    # Set AD config for selected domain
    if set_ad_config_for_domain "$selected_domain"; then
      show_success "Selected domain: $selected_domain ($AD_DOMAIN)"
      if [[ $DOMAIN_SELECT_CONTEXT == "AD_USER_SEARCH" ]]; then
        DOMAIN_SELECT_CONTEXT=""
        goto_state "AD_USER_SEARCH"
      else
        goto_state "AD_JOIN"
      fi
    else
      show_error "Failed to configure domain parameters for: $selected_domain"
      goto_state "DOMAIN_SELECT"
    fi
    ;;
  esac
}

# AD join state screen
screen_ad_join() {
  clear
  show_header "Active Directory Domain Join"

  if perform_ad_join; then
    wait_for_user
    goto_state "MAIN_MENU"
  else
    local choice
    choice=$(prompt_choice "Join failed. Choose action:" \
      "Retry join" \
      "Change domain" \
      "Back to menu") || goto_state "MAIN_MENU"

    case "$choice" in
    "Retry join") goto_state "AD_JOIN" ;;
    "Change domain") goto_state "DOMAIN_SELECT" ;;
    "Back to menu") goto_state "MAIN_MENU" ;;
    esac
  fi
}

# Local user creation state screen
screen_local_user_create() {
  clear
  show_header "Create Local User"

  # Get user input - exit if user cancels
  if ! prompt_username || ! prompt_realname; then
    goto_state "MAIN_MENU"
    return
  fi

  # Create the user
  if create_user; then
    wait_for_user
    goto_state "MAIN_MENU"
  else
    local choice
    choice=$(prompt_choice "Creation failed. Choose action:" \
      "Try again" \
      "Back to menu") || goto_state "MAIN_MENU"

    case "$choice" in
    "Try again") goto_state "LOCAL_USER_CREATE" ;;
    "Back to menu") goto_state "MAIN_MENU" ;;
    esac
  fi
}

# AD user search state screen
screen_ad_user_search() {
  clear
  show_header "Active Directory User Search"

  # Check network connectivity (function handles all user interaction)
  if ! check_ad_connectivity; then
    goto_state "MAIN_MENU"
    return
  fi

  # AD config should already be set by domain selection flow
  if [[ -z $AD_DOMAIN ]]; then
    show_error "No AD domain configured. Please check your configuration."
    goto_state "MAIN_MENU"
    return
  fi

  # Get AD username if needed (reuse existing if available)
  if [[ ! -r $KERBEROS_KEYTAB ]]; then
    if [[ -z $AD_USERNAME ]]; then
      AD_USERNAME=$(prompt_input "Enter admin username:" "domain username") || {
        goto_state "MAIN_MENU"
        return
      }
      debug "AD credentials entered for user: $AD_USERNAME"
    else
      debug "Reusing existing AD credentials for user: $AD_USERNAME"
    fi
  fi

  # Get search filter
  local search_filter
  search_filter=$(prompt_input "Enter user search filter:" "leave blank for all users") || {
    goto_state "MAIN_MENU"
    return
  }

  # Perform LDAP search
  show_info "Searching LDAP for users..."
  local ldap_results
  if ! ldap_results=$(query_ldap "$LDAP_SERVER" "$BASE_DN" "$AD_USERNAME" "$search_filter"); then
    show_error "LDAP search failed"
    local choices=("Try again")
    if [[ ! -r $KERBEROS_KEYTAB && -n $AD_USERNAME ]]; then
      choices+=("Change user")
    fi
    choices+=("Back to menu")

    local choice
    choice=$(prompt_choice "Search failed. Choose action:" \
      "${choices[@]}") || goto_state "MAIN_MENU"

    case "$choice" in
    "Try again") goto_state "AD_USER_SEARCH" ;;
    "Change user")
      # Clear user to force re-entry
      AD_USERNAME=""
      goto_state "AD_USER_SEARCH"
      ;;
    "Back to menu") goto_state "MAIN_MENU" ;;
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
    choice=$(prompt_choice "Enroll this user?" \
      "Enroll user" \
      "Skip user" \
      "Stop search") || goto_state "MAIN_MENU"

    case "$choice" in
    "Enroll user")
      # Reset user variables to avoid contamination between users
      USERNAME=""
      REALNAME=""

      # Set user variables from LDAP data
      [[ -n $name ]] && USERNAME="$name"
      [[ -n $display_name ]] && REALNAME="$display_name"

      # Only set USER_ID if it wasn't set before (config/cmdline)
      if [[ -z $USER_ID && -n $user_id ]]; then
        USER_ID="$user_id"
        debug "Using uidNumber from LDAP: $user_id"
      elif [[ -n $user_id && $USER_ID != "$user_id" ]]; then
        show_warning "LDAP uidNumber ($user_id) differs from configured UID ($USER_ID)"
        show_warning "Using configured value instead"
      fi

      # Warn about unused attributes
      if [[ -n $group_id ]]; then
        show_warning "LDAP gidNumber ($group_id) is not used by systemd-homed"
      fi

      # Set optional attributes
      [[ -n $home_dir ]] && USER_HOME_DIRECTORY="$home_dir"
      [[ -n $shell ]] && USER_SHELL="$shell"

      # Validate required fields
      if [[ -z $USERNAME ]]; then
        show_error "Cannot enroll user: missing username"
        continue
      fi
      if [[ -z $REALNAME ]]; then
        show_warning "No display name found, using username as display name"
        REALNAME="$USERNAME"
      fi
      if [[ -z $USER_ID ]]; then
        show_warning "No uidNumber found in LDAP, systemd-homed will auto-assign UID"
      fi

      if create_user; then
        break
      else
        show_error "Failed to enroll user '$USERNAME'"
      fi
      ;;
    "Skip user") continue ;;
    "Stop search") break ;;
    esac
  done

  # Ask what to do next
  local choices=("Search again")
  if [[ -n $AD_USERNAME ]]; then
    choices+=("Change credentials")
  fi
  choices+=("Back to menu" "Finish setup")

  echo ""
  local choice
  choice=$(prompt_choice "Choose action:" "${choices[@]}") || goto_state "MAIN_MENU"

  case "$choice" in
  "Search again") goto_state "AD_USER_SEARCH" ;;
  "Change credentials")
    AD_USERNAME=""
    goto_state "AD_USER_SEARCH"
    ;;
  "Back to menu") goto_state "MAIN_MENU" ;;
  "Finish setup") goto_state "MAIN_MENU" ;;
  esac
}

# Non-interactive 1: Automated user creation with pre-provided arguments
non_interactive_setup() {

  # Validate systemd-homed availability
  if ! has_systemd_homed; then
    debug "systemd-homed is not available on this system."
    exit 1
  fi

  # Validate required parameters
  if [[ -z $USERNAME ]]; then
    debug "Username is required. Use --username or run interactive mode"
    exit 1
  fi

  if [[ -z $REALNAME ]]; then
    debug "Real name is required. Use --realname or run interactive mode"
    exit 1
  fi

  if [[ -z $PASSWORD ]]; then
    debug "Password is required. Use --password or run interactive mode"
    exit 1
  fi

  # Validate username
  if ! set_username "$USERNAME"; then
    debug "Invalid username."
    exit 1
  fi

  # Validate real name
  if ! set_realname "$REALNAME"; then
    debug "Invalid real name."
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

  debug "Creating user account with the following settings:"
  debug "Username:     $USERNAME"
  debug "Real name:    $REALNAME"
  debug "Groups:       $USER_GROUPS"
  debug "Home size:    ${HOME_SIZE}MB"
  debug "User ID:      $USER_ID"
  debug "Filesystem:   $FS_TYPE"
  debug "FIDO2:        $FIDO_AUTH"
  debug "Recovery key: $RECOVERY_KEY"

  if create_user; then
    debug "User creation completed"
  else
    debug "Failed to create user account."
  fi
}

# Non-interactive 2: Automated user removal
remove_all_users() {
  debug "Removing all enrolled users..."

  # Throw error if systemd-homed is not available
  if ! has_systemd_homed; then
    debug "systemd-homed is not available on this system."
    return 1
  fi

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
  if ! load_config_file; then
    debug "Configuration file not found or invalid. Using defaults."
  fi

  # Apply configuration values (CLI takes precedence over config)
  apply_configuration

  # Handle special cases for non-interactive and remove users
  if $NON_INTERACTIVE; then
    non_interactive_setup
  elif $REMOVE_USERS; then
    remove_all_users
  else
    # Interactive mode
    # Set up display
    brightnessctl set 100% >/dev/null 2>&1 || true

    # Run interactive state machine
    start_state_machine
  fi
}

# Execute main function with all arguments
main "$@"
