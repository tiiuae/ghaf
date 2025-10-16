# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkIf
    types
    flatten
    concatMapStringsSep
    ;
  cfg = config.ghaf.services.kill-switch;

  netvmName = "net-vm";
  audiovmName = "audio-vm";
  inherit (config.microvm) stateDir;
  supportedDevices = [
    "mic"
    "net"
    "cam"
  ];

  # Flatten the list of devices
  audioPciDevices =
    if config.ghaf.virtualization.microvm.audiovm.enable then
      flatten (map (device: "${device.vendorId}:${device.productId}") config.ghaf.common.hardware.audio)
    else
      [ ];
  netPciDevices =
    if config.ghaf.virtualization.microvm.netvm.enable then
      flatten (map (device: "${device.vendorId}:${device.productId}") config.ghaf.common.hardware.nics)
    else
      [ ];
  camUsbDevices = builtins.filter (
    d: lib.hasPrefix "cam" d.name
  ) config.ghaf.hardware.definition.usb.devices;

  ghaf-killswitch = pkgs.writeShellApplication {
    name = "ghaf-killswitch";
    runtimeInputs = with pkgs; [
      coreutils
      hotplug
      vhotplug
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
      if [ $# -ge 2 ]; then
        device="$2"
      fi

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

        case "$device" in
        mic)
          vm_name="${audiovmName}"
          ${concatMapStringsSep "\n" (pciDevice: ''
            devices+=("${pciDevice}")
          '') audioPciDevices}
        ;;
        net)
          vm_name="${netvmName}"
          ${concatMapStringsSep "\n" (pciDevice: ''
            devices+=("${pciDevice}")
          '') netPciDevices}
        ;;
        esac
      }

      block_devices() {
        if [[ "$device" == "net" || "$device" == "mic" ]]; then
          echo "Blocking $device device ..."
          hotplug --detach-pci "''${devices[@]}" --data-path "$state_path" --socket-path "$socket_path"
        else
          ${lib.concatStringsSep "\n" (
            map (d: ''
              echo "Blocking device ${d.name} ..."
              vhotplugcli usb detach \
                ${if d.vendorId == null then "" else "--vid ${d.vendorId}"} \
                ${if d.productId == null then "" else "--pid ${d.productId}"} \
                ${if d.hostbus == null then "" else "--bus ${d.hostbus}"} \
                ${if d.hostport == null then "" else "--port ${d.hostport}"}
            '') camUsbDevices
          )}
          ${lib.optionalString (camUsbDevices == [ ]) ''
            echo "No USB devices to block"
          ''}
        fi
      }

      unblock_devices() {
        if [[ "$device" == "net" || "$device" == "mic" ]]; then
          echo "Unblocking $device device ..."
          if ! hotplug --attach-pci --data-path "$state_path" --socket-path "$socket_path"; then
            echo "Failed to attach PCI devices. Check systemctl status microvm@$vm_name.service"
            # Recovery from failed attach; restart the VM
            echo "Fallback: restarting $vm_name..."
            systemctl restart microvm@"$vm_name".service
          fi
        else
          ${lib.concatStringsSep "\n" (
            map (d: ''
              echo "Unblocking device ${d.name} ..."
              vhotplugcli usb attach \
                ${if d.vendorId == null then "" else "--vid ${d.vendorId}"} \
                ${if d.productId == null then "" else "--pid ${d.productId}"} \
                ${if d.hostbus == null then "" else "--bus ${d.hostbus}"} \
                ${if d.hostport == null then "" else "--port ${d.hostport}"}
            '') camUsbDevices
          )}
          ${lib.optionalString (camUsbDevices == [ ]) ''
            echo "No USB devices to unblock"
          ''}
        fi
      }

      supportedDevices=(${builtins.concatStringsSep " " supportedDevices})

      if [ -n "''${2:-}" ]; then
        # Check if the user-provided device has kill switch support.
        if ! [[ "''${supportedDevices[*]}" =~  (^|[[:space:]])$device($|[[:space:]])  ]]; then
          echo "$device is not supported"
          exit 1
        fi

        # Find VM name and the devices
        vm_name=""
        declare -a devices
        find_vm_devices

        # Set socket and state path
        socket_path="${stateDir}/$vm_name/$vm_name.sock"
        state_path="${stateDir}/$vm_name/state"
      fi

      case "$cmd" in
        list)
          echo "Supported Devices:"
          for device in "''${supportedDevices[@]}"; do
            echo "$device"
          done
          ;;
        block)
          block_devices
          ;;
        unblock)
          unblock_devices
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
  };
in
{
  options.ghaf.services.kill-switch = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable ghaf kill switch support".
      '';
    };
  };

  # TODO: Currently enabled for x86_64, we will evaluate the need for aarch64 support in the future
  config = mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isx86_64) {

    environment.systemPackages = [
      ghaf-killswitch
    ];
  };
}
