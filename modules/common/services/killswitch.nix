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
        case "$device" in
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
        case "$device" in
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
            for d in "''${supportedDevices[@]}"; do
              device=$d
              # Get status and extract device state
              show_output="$(show_status)"
               status=$(awk -F': ' -v dev="$device" '
                  tolower($1) == tolower(dev) {
                      print tolower($2);
                      exit
                  }
              ' <<< "$show_output")

              # Check status and block if needed
              if [[ -z "$status" ]]; then
                echo "warning: couldn't find status for '$device'" >&2
              elif [[ "$status" == "blocked" ]]; then
                echo "Skipping $device - already blocked"
                continue
              fi

              block_devices
            done
          else
            block_devices
          fi
          ;;
        unblock)
          if [[ "$device" == "--all" ]]; then
            for d in "''${supportedDevices[@]}"; do
              device=$d
              unblock_devices
            done
          else
            unblock_devices
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
      pkgs.ghaf-kill-switch-app
    ];
  };
}
