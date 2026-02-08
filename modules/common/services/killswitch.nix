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

  audioPciDevices =
    if config.ghaf.common.hardware ? "audio" then config.ghaf.common.hardware.audio else [ ];
  netPciDevices =
    if config.ghaf.common.hardware ? "nics" then config.ghaf.common.hardware.nics else [ ];
  camUsbDevices =
    if config.ghaf.common.hardware ? usb then
      lib.filter (d: lib.hasPrefix "cam" d.name) config.ghaf.common.hardware.usb
    else
      [ ];
  btUsbDevices =
    if config.ghaf.common.hardware ? "usb" then
      lib.filter (d: lib.hasPrefix "bt" d.name) config.ghaf.common.hardware.usb
    else
      [ ];

  # A function to generate shell commands for PCI devices
  mkPciCommands =
    {
      command,
      devices,
    }:
    lib.concatStringsSep "\n" (
      map (d: ''
        vhotplugcli pci ${command} \
          ${lib.optionalString (d.vendorId != null) "--vid ${d.vendorId}"} \
          ${lib.optionalString (d.productId != null) "--did ${d.productId}"}
      '') devices
    );

  # A function to generate shell commands for USB devices
  mkUsbCommands =
    {
      command,
      devices,
      actionStr,
    }:
    lib.concatStringsSep "\n" (
      map (d: ''
        echo "${actionStr} device ${d.name} ..."
        vhotplugcli usb ${command} \
          ${lib.optionalString (d.vendorId != null) "--vid ${d.vendorId}"} \
          ${lib.optionalString (d.productId != null) "--pid ${d.productId}"} \
          ${lib.optionalString (d.hostbus != null) "--bus ${d.hostbus}"} \
          ${lib.optionalString (d.hostport != null) "--port ${d.hostport}"}
      '') devices
    );

  # A function to generate shell code for checking PCI device status
  mkPciStatusCheck =
    {
      devices,
      blockedVar,
    }:
    lib.concatStringsSep "\n" (
      map (d: ''
        vid="${lib.optionalString (d.vendorId != null) d.vendorId}"
        did="${lib.optionalString (d.productId != null) d.productId}"
        if [ -n "$vid" ] && [ -n "$did" ] && echo "$pci_out" | grep -qi "''${vid}:''${did}"; then
          ${blockedVar}="true"
        fi
      '') devices
    );

  # A function to generate shell code for checking USB device status
  mkUsbStatusCheck =
    {
      devices,
      blockedVar,
    }:
    lib.concatStringsSep "\n" (
      map (d: ''
        vid="${lib.optionalString (d.vendorId != null) d.vendorId}"
        did="${lib.optionalString (d.productId != null) d.productId}"
        hbus="${lib.optionalString (d.hostbus != null) d.hostbus}"
        hport="${lib.optionalString (d.hostport != null) d.hostport}"

        # Normalize to lowercase for case-insensitive matching
        vid_l=$(echo "$vid" | tr '[:upper:]' '[:lower:]')
        did_l=$(echo "$did" | tr '[:upper:]' '[:lower:]')

        # Check if vid:pid match (case-insensitive)
        if [ -n "$vid" ] && [ -n "$did" ]; then
          if echo "$usb_out" | grep -qi "vid[[:space:]]*:[[:space:]]*$vid_l" \
            && echo "$usb_out" | grep -qi "pid[[:space:]]*:[[:space:]]*$did_l"; then
            ${blockedVar}="true"
          fi
        fi

        # Check if busnum + portnum match
        if [ -n "$hbus" ] && [ -n "$hport" ]; then
          if echo "$usb_out" | grep -q "busnum[[:space:]]*:[[:space:]]*$hbus" \
            && echo "$usb_out" | grep -q "portnum[[:space:]]*:[[:space:]]*$hport"; then
            ${blockedVar}="true"
          fi
        fi
      '') devices
    );

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
            ${
              if netPciDevices == [ ] then
                ''echo "No net devices to block"''
              else
                mkPciCommands {
                  command = "detach";
                  devices = netPciDevices;
                }
            }
            ;;
          mic)
            echo "Blocking mic device ..."
            ${
              if audioPciDevices == [ ] then
                ''echo "No mic devices to block"''
              else
                mkPciCommands {
                  command = "detach";
                  devices = audioPciDevices;
                }
            }
            ;;
          cam)
            ${
              if camUsbDevices == [ ] then
                ''echo "No cam devices to block"''
              else
                mkUsbCommands {
                  command = "detach";
                  devices = camUsbDevices;
                  actionStr = "Blocking";
                }
            }
            ;;
          bluetooth)
            ${
              if btUsbDevices == [ ] then
                ''echo "No bluetooth devices to block"''
              else
                mkUsbCommands {
                  command = "detach";
                  devices = btUsbDevices;
                  actionStr = "Blocking";
                }
            }
            ;;
        esac
      }

      unblock_devices() {
        case "$device" in
          net)
            echo "Unblocking net device ..."
            ${
              if netPciDevices == [ ] then
                ''echo "No net devices to unblock"''
              else
                mkPciCommands {
                  command = "attach";
                  devices = netPciDevices;
                }
            }
            ;;
          mic)
            echo "Unblocking mic device ..."
            ${
              if audioPciDevices == [ ] then
                ''echo "No mic devices to unblock"''
              else
                mkPciCommands {
                  command = "attach";
                  devices = audioPciDevices;
                }
            }
            ;;
          cam)
            ${
              if camUsbDevices == [ ] then
                ''echo "No cam devices to unblock"''
              else
                mkUsbCommands {
                  command = "attach";
                  devices = camUsbDevices;
                  actionStr = "Unblocking";
                }
            }
            ;;
          bluetooth)
            ${
              if btUsbDevices == [ ] then
                ''echo "No bluetooth devices to unblock"''
              else
                mkUsbCommands {
                  command = "attach";
                  devices = btUsbDevices;
                  actionStr = "Unblocking";
                }
            }
            ;;
        esac
      }

      show_status() {
        pci_out="$(vhotplugcli pci list --short --disconnected)"

        # Check for Mic status
        mic_blocked="false"
        ${mkPciStatusCheck {
          devices = audioPciDevices;
          blockedVar = "mic_blocked";
        }}
        [ "$mic_blocked" = true ] && echo "mic: blocked" || echo "mic: unblocked"

        # Check for Network status
        net_blocked="false"
        ${mkPciStatusCheck {
          devices = netPciDevices;
          blockedVar = "net_blocked";
        }}
        [ "$net_blocked" = true ] && echo "net: blocked" || echo "net: unblocked"

        # Disable the warning that appears when no USB devices
        # shellcheck disable=SC2034
        usb_out="$(vhotplugcli usb list --disconnected)"

        # Check for camera status
        cam_blocked="false"
        ${mkUsbStatusCheck {
          devices = camUsbDevices;
          blockedVar = "cam_blocked";
        }}
        [ "$cam_blocked" = true ] && echo "cam: blocked" || echo "cam: unblocked"

        # Check for bluetooth status
        bt_blocked="false"
        ${mkUsbStatusCheck {
          devices = btUsbDevices;
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
