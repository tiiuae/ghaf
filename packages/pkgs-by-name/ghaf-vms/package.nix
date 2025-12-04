# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  busybox,
  systemd,
}:
let
  colors = {
    normal = "\\033[0m";
    red = "\\033[0;31m";
    green = "\\033[0;32m";
    yellow = "\\033[0;33m";
    boldRed = "\\033[1;31m";
  };
  colored = color: text: "${colors.${color}}${text}${colors.normal}";
in
writeShellApplication {
  name = "ghaf-vms";

  runtimeInputs = [
    busybox
    systemd
  ];

  text = ''
    MICROVM_DIR="/var/lib/microvms"

    # Function to display usage
    show_usage() {
        echo "Usage: ghaf-vms [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -l, --list    List all VMs and their status"
        echo "  -h, --help    Show this help message"
        echo ""
        echo "If no option is specified, -l/--list is assumed."
    }

    # Function to list VMs
    list_vms() {
        if [ ! -d "$MICROVM_DIR" ]; then
            echo -e "${colored "red" "Error: MicroVM directory $MICROVM_DIR does not exist"}"
            exit 1
        fi

        # Check if there are any VMs
        if [ -z "$(ls -A "$MICROVM_DIR" 2>/dev/null)" ]; then
            echo "No VMs found in $MICROVM_DIR"
            exit 0
        fi

        echo "VM Status:"
        echo "=========="

        # Iterate through each VM directory
        for vm_dir in "$MICROVM_DIR"/*; do
            if [ -d "$vm_dir" ]; then
                vm_name=$(basename "$vm_dir")

                # Only allow alphanumeric, hyphens, and underscores
                if [[ ! "$vm_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo -e "${colored "yellow" "Warning: Skipping invalid VM name: $vm_name"}" >&2
                    continue
                fi

                service_name="microvm@$vm_name.service"

                # Get service status
                if systemctl is-active --quiet "$service_name"; then
                    status="${colored "green" "running"}"
                elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
                    status="${colored "red" "stopped"}"
                else
                    # Check if service exists but is failed or in other state
                    if systemctl status "$service_name" &>/dev/null; then
                        service_state=$(systemctl show -p ActiveState --value "$service_name")
                        case "$service_state" in
                        failed)
                            status="${colored "boldRed" "failed"}"
                            ;;
                        *)
                            status="${colored "yellow" "$service_state"}"
                            ;;
                        esac
                    else
                        status="${colored "yellow" "unknown"}"
                    fi
                fi

                # Print VM status
                echo -e "$vm_name: $status"
            fi
        done
    }

    while getopts ":lh" opt; do
        case $opt in
        l) list_vms ;;
        h)
            show_usage
            exit 0
            ;;
        *)
            show_usage
            exit 1
            ;;
        esac
    done

    # If no arguments are provided, list VMs
    list_vms
  '';

  meta = {
    description = "List status of Ghaf MicroVMs";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
