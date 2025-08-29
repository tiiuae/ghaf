# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  pkgs,
  lib,
  config ? { },
}:
let
  netvmName = "net-vm";
  audiovmName = "audio-vm";
  supportedDevices = [
    "mic"
    "net"
  ];
  # Flatten the list of PCI devices for audio and network
  audioPciDevices = lib.flatten (
    map (device: "${device.vendorId}:${device.productId}") config.ghaf.common.hardware.audio
  );
  netPciDevices = lib.flatten (
    map (device: "${device.vendorId}:${device.productId}") config.ghaf.common.hardware.nics
  );
  inherit (config.microvm) stateDir;
in
writeShellApplication {
  name = "ghaf-killswitch";

  runtimeInputs = with pkgs; [
    coreutils
    pci-hotplug
  ];

  text = ''
    help_msg() {
      cat << EOF
    Usage: $(basename "$0") <COMMAND> [OPTIONS]

    Tool for enabling and disabling devices.

    Commands:
      block             [device]
      unblock           [device]
      list              List the devices supported
      help, --help      Show this help message and exit.

    Examples:
      $(basename "$0") block mic
      $(basename "$0") unblock mic
      $(basename "$0") block net

    EOF
    }

    if [ "$EUID" -ne 0 ]; then
      echo "Please run as root"
      exit 1
    fi

    if [ $# -eq 0 ]; then
        help_msg
        exit 0
    fi

    cmd="$1"
    if [ "$cmd" == "block" ] || [ "$cmd" == "unblock" ]; then
      if [ -z "''${2:-}" ]; then
          RED="\e[31m"
          ENDCOLOR="\e[0m"
          echo -e "''${RED}Please provide the device''${ENDCOLOR}"
          echo ""
          help_msg
          exit 1
        fi
    fi

    find_vm_devices() {
      local device=$1

      case "$device" in
      mic)
        vm_name="${audiovmName}"
        ${lib.concatMapStringsSep "\n" (pciDevice: ''
          pci_devices+=("${pciDevice}")
        '') audioPciDevices}
      ;;
      net)
        vm_name="${netvmName}"
        ${lib.concatMapStringsSep "\n" (pciDevice: ''
          pci_devices+=("${pciDevice}")
        '') netPciDevices}
      ;;
      esac
    }

    pci_suspend() {
      device="$1"

      echo "Suspending $device ..."
      pci-hotplug --detach "''${pci_devices[@]}" --data-path "$state_path" --socket-path "$socket_path"
    }

    pci_resume() {
      device="$1"

      echo "Resuming $device ..."
      if ! pci-hotplug --attach --data-path "$state_path" --socket-path "$socket_path"; then
              echo "Failed to attach PCI devices. Check systemctl status microvm@$vm_name.service"
              # Recovery from failed attach; restart the VM
              echo "Fallback: restarting $vm_name..."
              systemctl restart microvm@"$vm_name".service
      fi
    }

    devices=(${builtins.concatStringsSep " " supportedDevices})

    if [ -n "''${2:-}" ]; then
      # Check if the user-provided device has kill switch support.
      if ! [[ "''${devices[*]}" =~  (^|[[:space:]])$2($|[[:space:]])  ]]; then
        echo "$2 device is not supported"
        exit 1
      fi

      # Find VM and PCI devices
      vm_name=""
      declare -a pci_devices
      find_vm_devices "$2"

      # Set socket and state path
      socket_path="${stateDir}/$vm_name/$vm_name.sock"
      state_path="${stateDir}/$vm_name/pci-state"
    fi

    case "$cmd" in
      list)
        echo "Supported Devices:"
        for device in "''${devices[@]}"; do
          echo "$device"
        done
        ;;
      block)
        pci_suspend "$2"
        ;;
      unblock)
        pci_resume "$2"
        ;;
      help|--help)
        help_msg
        ;;
      *)
        help_msg
        exit 1
        ;;
    esac
  '';

  meta = {
    description = "Wrapper script for kill switch implementation";
    platforms = [
      "x86_64-linux"
    ];
  };
}
