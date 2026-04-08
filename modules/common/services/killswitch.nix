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
    mkEnableOption
    mkIf
    ;
  cfg = config.ghaf.services.kill-switch;

  supportedDevices = [
    "mic"
    "net"
    "cam"
    "bluetooth"
  ];

  # A function to generate shell commands for PCI devices
  mkPciCommands =
    {
      command,
      tag,
    }:
    ''
      vhotplugcli pci ${command} --tag ${tag}
    '';

  # A function to generate shell commands for USB devices
  mkUsbCommands =
    {
      command,
      tag,
    }:
    ''
      vhotplugcli usb ${command} --tag ${tag}
    '';

  # A function to generate shell code for checking PCI device status
  mkPciStatusCheck =
    {
      tag,
      blockedVar,
    }:
    ''
      if [ -z "$(vhotplugcli pci list --tag ${tag} --connected | tr -d '[:space:]')" ]; then
        ${blockedVar}="true"
      fi
    '';

  # A function to generate shell code for checking USB device status
  mkUsbStatusCheck =
    {
      tag,
      blockedVar,
    }:
    ''
      if [ -z "$(vhotplugcli usb list --tag ${tag} --connected | tr -d '[:space:]')" ]; then
        ${blockedVar}="true"
      fi
    '';

  ghaf-killswitch = pkgs.writeShellApplication {
    name = "ghaf-killswitch";
    runtimeInputs = with pkgs; [
      coreutils
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
        block             [device | --all]
        unblock           [device | --all]
        list              List the devices supported
        status            Show block/unblock status of devices
        help, --help      Show this help message and exit.
      Examples:
        $(basename "$0") block mic
        $(basename "$0") unblock mic
        $(basename "$0") block net
        $(basename "$0") block --all
        $(basename "$0") unblock --all
        $(basename "$0") status

      EOF
      }

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

      block_devices() {
        local target_device="$1"
        case "$target_device" in
          net)
            echo "Blocking net device ..."
            ${mkPciCommands {
              command = "detach";
              tag = "net";
            }}
            ;;
          mic)
            echo "Blocking mic device ..."
            ${mkPciCommands {
              command = "detach";
              tag = "audio";
            }}
            ;;
          cam)
            echo "Blocking cam device ..."
            ${mkUsbCommands {
              command = "detach";
              tag = "cam";
            }}
            ;;
          bluetooth)
            echo "Blocking bluetooth device ..."
            ${mkUsbCommands {
              command = "detach";
              tag = "bt";
            }}
            ;;
        esac
      }

      unblock_devices() {
        local target_device="$1"
        case "$target_device" in
          net)
            echo "Unblocking net device ..."
            ${mkPciCommands {
              command = "attach";
              tag = "net";
            }}
            ;;
          mic)
            echo "Unblocking mic device ..."
            ${mkPciCommands {
              command = "attach";
              tag = "audio";
            }}
            ;;
          cam)
            echo "Unblocking cam device ..."
            ${mkUsbCommands {
              command = "attach";
              tag = "cam";
            }}
            ;;
          bluetooth)
            echo "Unblocking bluetooth device ..."
            ${mkUsbCommands {
              command = "attach";
              tag = "bt";
            }}
            ;;
        esac
      }

      show_status() {

        # Check for Mic status
        mic_blocked="false"
        ${mkPciStatusCheck {
          tag = "audio";
          blockedVar = "mic_blocked";
        }}
        [ "$mic_blocked" = true ] && echo "mic: blocked" || echo "mic: unblocked"

        # Check for Network status
        net_blocked="false"
        ${mkPciStatusCheck {
          tag = "net";
          blockedVar = "net_blocked";
        }}
        [ "$net_blocked" = true ] && echo "net: blocked" || echo "net: unblocked"

        # Check for camera status
        cam_blocked="false"
        ${mkUsbStatusCheck {
          tag = "cam";
          blockedVar = "cam_blocked";
        }}
        [ "$cam_blocked" = true ] && echo "cam: blocked" || echo "cam: unblocked"

        # Check for bluetooth status
        bt_blocked="false"
        ${mkUsbStatusCheck {
          tag = "bt";
          blockedVar = "bt_blocked";
        }}
        [ "$bt_blocked" = true ] && echo "bluetooth: blocked" || echo "bluetooth: unblocked"
      }

      get_status_from_vhotplug() {
        local bus="$1"
        local tag="$2"

        if [ -z "$(vhotplugcli "$bus" list --tag "$tag" --connected | tr -d '[:space:]')" ]; then
          echo "blocked"
        else
          echo "unblocked"
        fi
      }

      get_device_status() {
        case "$1" in
          mic)
            get_status_from_vhotplug pci audio
            ;;
          net)
            get_status_from_vhotplug pci net
            ;;
          cam)
            get_status_from_vhotplug usb cam
            ;;
          bluetooth)
            get_status_from_vhotplug usb bt
            ;;
          *)
            echo "unknown"
            return 1
            ;;
        esac
      }

      run_all_in_parallel() {
        local action="$1"
        local target_status action_label
        local -a pids devices
        local failed status

        case "$action" in
          block)
            target_status="blocked"
            action_label="block"
            ;;
          unblock)
            target_status="unblocked"
            action_label="unblock"
            ;;
          *)
            echo "Unsupported action: $action" >&2
            return 1
            ;;
        esac

        failed=0

        for d in "''${supportedDevices[@]}"; do
          devices+=("$d")
          (
            status="$(get_device_status "$d")"

            if [[ -z "$status" || "$status" == "unknown" ]]; then
              echo "Warning: couldn't find status for '$d'" >&2
              exit 1
            fi

            if [[ "$status" == "$target_status" ]]; then
              echo "Skipping $d - already $target_status"
              exit 0
            fi

            if [[ "$action" == "block" ]]; then
              block_devices "$d"
            else
              unblock_devices "$d"
            fi
          ) &
          pids+=("$!")
        done

        for i in "''${!pids[@]}"; do
          if ! wait "''${pids[$i]}"; then
            failed=1
            echo "Error: Failed to $action_label ''${devices[$i]}" >&2
          fi
        done
        return "$failed"
      }

      supportedDevices=(${builtins.concatStringsSep " " supportedDevices})

      if [ -n "''${2:-}" ]; then
        # Check if the user-provided device has kill switch support.
        if [[ "$device" != "--all" ]] && ! [[ "''${supportedDevices[*]}" =~  (^|[[:space:]])$device($|[[:space:]])  ]]; then
          echo "$device is not supported"
          exit 1
        fi
      fi

      case "$cmd" in
        list)
          echo "Supported Devices:"
          for device in "''${supportedDevices[@]}"; do
            echo "$device"
          done
          ;;
        block)
          if [[ "$device" == "--all" ]]; then
            run_all_in_parallel block
          else
            block_devices "$device"
          fi
          ;;
        unblock)
          if [[ "$device" == "--all" ]]; then
            run_all_in_parallel unblock
          else
            unblock_devices "$device"
          fi
          ;;
        status)
          show_status
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
  _file = ./killswitch.nix;

  options.ghaf.services.kill-switch.enable = mkEnableOption "ghaf kill switch support";

  # TODO: Currently enabled for x86_64, we will evaluate the need for aarch64 support in the future
  config = mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isx86_64) {

    environment.systemPackages = [
      ghaf-killswitch
      pkgs.ghaf-kill-switch-app
    ];
  };
}
