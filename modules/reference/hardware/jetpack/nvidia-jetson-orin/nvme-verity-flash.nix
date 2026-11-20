# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  jetpackSource,
}:
let
  inherit (pkgs) lib;
  native = pkgs.pkgsBuildBuild;
  jetpack = pkgs.nvidia-jetpack;
  cfg = config.hardware.nvidia-jetpack;
  recovery = jetpack.nvmeFlashRecoveryInputs;
  peripheral = import (jetpackSource + "/device-pkgs/force-xusb-peripheral.nix") {
    inherit config lib;
    inherit (jetpack) l4tMajorMinorPatchVersion;
    inherit (native) writeText deviceTree;
  };
  rcm = native.writeShellApplication {
    name = "boot-verity-nvme-recovery";
    text = ''
      : "''${flash_id:?}" "''${verity_work:?}"
    ''
    + jetpack.mkRcmBootScript {
      kernelPath = "${recovery}/Image";
      initrdPath = "${recovery}/initrd";
      kernelCmdline = lib.concatStringsSep " " (
        [
          "clk_ignore_unused"
          "flash-id=$flash_id"
        ]
        ++ cfg.console.args
      );
      bootImagePath = "$verity_work/recovery/boot.img";
      additionalDtbOverlays =
        lib.filter (
          path: (path.name or "") != "DefaultBootOrder.dtbo"
        ) cfg.flashScriptOverrides.additionalDtbOverlays
        ++ [ peripheral ];
    };
  };
  writer = import ./write-verity-nvme.nix { pkgs = native; };
in
native.writeShellApplication {
  name = "flash-verity-nvme";
  runtimeInputs = with native; [
    coreutils
    util-linux
    openssl
    sbsigntool
  ];
  text = ''
    args=()
    while (( $# )); do
      case "$1" in
        -u|--uki) shift ;;
        --usb-instance)
          [[ $# -ge 2 && -n "$2" ]] || { echo "--usb-instance requires a value" >&2; exit 1; }
          args+=("$1" "$2"); shift 2 ;;
        -h|--help)
          echo "Usage: flash-verity-nvme [-u] [--usb-instance PORT]"
          exit 0 ;;
        *) echo "Unsupported initial-flash argument: $1" >&2; exit 1 ;;
      esac
    done
    umask 077
    verity_work=$(mktemp -d)
    export verity_work
    trap 'rm -rf "$verity_work"' EXIT
    WORKDIR="$verity_work" ${lib.getExe config.system.build.prepareVerityFlashImages}
    flash_id=$(cat /proc/sys/kernel/random/uuid)
    export flash_id
    disk=/dev/disk/by-id/usb-Linux_File-Stor_Gadget_''${flash_id}-0:0
    [[ ! -e "$disk" ]]
    mkdir "$verity_work/recovery"
    cp ${recovery}/Image "$verity_work/recovery/Image"
    ${lib.optionalString config.ghaf.hardware.nvidia.orin.secureboot.enable ''
      key_dir="''${GHAF_DEV_KEY_DIR:-''${SECURE_BOOT_SIGNING_KEY_DIR:-${config.ghaf.hardware.nvidia.orin.secureboot.signingKeyDir}}}"
      sbsign --key "$key_dir/db.key" --cert "$key_dir/db.crt" \
        --output "$verity_work/recovery/Image" "$verity_work/recovery/Image"
    ''}
    ${native.nvidia-jetpack.flash-tools}/bootloader/mkbootimg \
      --kernel "$verity_work/recovery/Image" --ramdisk ${recovery}/initrd --board nvme0n1p2 \
      --cmdline "$(cat ${recovery}/cmdline) flash-id=$flash_id" \
      --output "$verity_work/recovery/boot.img"
    ${lib.optionalString config.ghaf.hardware.nvidia.orin.secureboot.enable ''
      bash ${native.nvidia-jetpack.flash-tools}/l4t_uefi_sign_image.sh \
        --image "$verity_work/recovery/boot.img" --key "$key_dir/db.key" \
        --cert "$key_dir/db.crt" --mode append
    ''}
    (unset WORKDIR; ${lib.getExe rcm} "''${args[@]}")
    for ((attempt=0; attempt<120; attempt++)); do
      [[ -b "$disk" ]] && break
      sleep 1
    done
    [[ -b "$disk" ]] || { echo "Recovery did not expose the NX NVMe disk" >&2; exit 1; }
    ${lib.getExe writer} "$disk" "$verity_work/bootloader/esp.img" "$verity_work/bootloader/system.img"
    shopt -s nullglob
    control=(/dev/serial/by-id/usb-NixOS_NVMe-flash_"$flash_id"-if*)
    [[ ''${#control[@]} -eq 1 ]]
    printf 'recovery\n' > "''${control[0]}"
    for ((attempt=0; attempt<30; attempt++)); do
      [[ ! -e "$disk" ]] && break
      sleep 1
    done
    [[ ! -e "$disk" ]] || { echo "NX did not return to USB recovery" >&2; exit 1; }
    sleep 3
    (unset WORKDIR; ${lib.getExe jetpack.signedFlashScript} "''${args[@]}")
  '';
}
