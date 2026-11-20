# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  flashers,
  defaultStorage,
}:
pkgs.writeShellApplication {
  name = "flash-ghaf-host";
  text = ''
    storage=${pkgs.lib.escapeShellArg defaultStorage}
    args=()
    while (( $# )); do
      case "$1" in
        --storage)
          [[ $# -ge 2 ]] || { echo "--storage requires a value" >&2; exit 1; }
          storage=$2; shift 2 ;;
        --secure-boot) shift ;;
        -h|--help)
          echo "Usage: flash-ghaf-host [--storage ${pkgs.lib.concatStringsSep "|" (builtins.attrNames flashers)}] [--disk /dev/disk/by-id/...] [-u] [--usb-instance PORT]"
          echo "Default storage: ${defaultStorage}. USB installation requires an SSD attached to this build PC."
          exit 0 ;;
        *) args+=("$1"); shift ;;
      esac
    done
    case "$storage" in
      ${pkgs.lib.concatStringsSep "\n" (
        pkgs.lib.mapAttrsToList (storage: flasher: ''
          ${storage}) exec ${pkgs.lib.getExe flasher} "''${args[@]}" ;;
        '') flashers
      )}
      *) echo "Unsupported storage for this board: $storage" >&2; exit 1 ;;
    esac
  '';
}
