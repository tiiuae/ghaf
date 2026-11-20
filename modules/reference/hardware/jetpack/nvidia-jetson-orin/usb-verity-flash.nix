# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, pkgs }:
let
  native = pkgs.pkgsBuildBuild;
  writer = import ./write-verity-nvme.nix { pkgs = native; };
in
native.writeShellApplication {
  name = "flash-verity-usb";
  runtimeInputs = with native; [
    coreutils
    util-linux
  ];
  text = ''
    disk=
    args=()
    while (( $# )); do
      case "$1" in
        --disk)
          [[ $# -ge 2 ]] || { echo "--disk requires a value" >&2; exit 1; }
          disk=$2; shift 2 ;;
        -u|--uki) shift ;;
        --usb-instance)
          [[ $# -ge 2 ]] || { echo "--usb-instance requires a value" >&2; exit 1; }
          args+=("$1" "$2"); shift 2 ;;
        *) echo "Unsupported initial-flash argument: $1" >&2; exit 1 ;;
      esac
    done
    [[ -b "$disk" && $(lsblk -dn -o TYPE "$disk") == disk && $(lsblk -dn -o TRAN "$disk") == usb ]] || {
      echo "--disk must identify a whole USB SSD attached to this build PC" >&2; exit 1;
    }
    umask 077
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    WORKDIR="$work" ${pkgs.lib.getExe config.system.build.prepareVerityFlashImages}
    ${pkgs.lib.getExe writer} "$disk" "$work/bootloader/esp.img" "$work/bootloader/system.img"
    (unset WORKDIR; ${pkgs.lib.getExe pkgs.nvidia-jetpack.signedFlashScript} "''${args[@]}")
    echo "Connect the USB SSD to the board and power-cycle it. Select USB first in existing UEFI boot settings."
  '';
}
