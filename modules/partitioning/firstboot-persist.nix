# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# First-boot service for Jetson Orin A/B verity boot.
#
# Secure A/B images contain both fixed-capacity slots; legacy images reserve
# space for the second slot here. On first boot this service:
#
#   1. Grows APP and the PV (encrypted APP is grown earlier in initrd)
#   2. Creates swap and persist LVs from the remaining free space
#
# An existing persist LV with no recognized filesystem fails closed.
#
# Ordering: systemd's device unit for /dev/pool/persist gates the
# persist.mount unit. This service creates the device, which triggers
# the mount automatically. For swap, we explicitly order the NixOS
# mkswap-* service after this one.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;
  encrypted = config.ghaf.hardware.nvidia.orin.diskEncryption.enable;
  fixedSlotSizes = cfg.rootSlotSizeMiB != null && cfg.veritySlotSizeMiB != null;
  # TODO: make this configurable?
  swapSizeMiB = 4096;

  firstbootScript = pkgs.writeShellApplication {
    name = "firstboot-persist";
    runtimeInputs =
      with pkgs;
      [
        gnugrep
        gawk
        lvm2
        coreutils
        btrfs-progs
        util-linux
      ]
      ++ lib.optionals (!encrypted) [ parted ];
    text = ''
      set -euo pipefail
      echo "firstboot-persist: starting at $(date)"

      # Encrypted APP is grown in initrd while the OP-TEE DUK is available.

      PV_PATH=$(pvdisplay -C -o pv_name --noheadings -S vg_name=pool | head -n1 | tr -d '[:space:]')
      [[ -n "$PV_PATH" ]] || { echo "ERROR: pool PV not found"; exit 1; }
      echo "PV: $PV_PATH -> $(readlink -f "$PV_PATH")"

      ${lib.optionalString (!encrypted) ''
        partition=$(readlink -f "$PV_PATH")
        part_num=$(cat "/sys/class/block/$(basename "$partition")/partition")
        disk="/dev/$(lsblk --nodeps --noheadings -o pkname "$partition" | xargs)"
        # parted also relocates the backup GPT without changing its reserved space.
        parted -s -f "$disk" resizepart "$part_num" 100%
      ''}

      # pvresize is idempotent — no-op if PV already matches partition
      echo "Resizing PV..."
      pvresize "$PV_PATH"

      # Slot names change during updates; never recreate their initial names.
      vgmknodes pool

      # --- Create swap LV (skip if already exists) ---

      if [ ! -e /dev/pool/swap ]; then
        echo "Creating swap LV (${toString swapSizeMiB} MiB)..."
        lvcreate -L ${toString swapSizeMiB}M -n swap pool
      else
        echo "swap LV already exists, skipping."
      fi

      # --- Create persist LV ---

      if [ ! -e /dev/pool/persist ]; then
        VG_FREE_INT=$(vgs --noheadings -o vg_free --nosuffix --units m pool \
          | awk '{ sub(/^</, "", $1); printf "%d", $1 }')
        PERSIST_MIB=$VG_FREE_INT
        ${lib.optionalString (!fixedSlotSizes) ''
          A_ROOT_MIB=$(lvs --noheadings -o lv_size --nosuffix --units m -S "vg_name=pool && lv_name=~^root_" | head -n1 | xargs)
          A_VERITY_MIB=$(lvs --noheadings -o lv_size --nosuffix --units m -S "vg_name=pool && lv_name=~^verity_" | head -n1 | xargs)
          RESERVE_MIB=$(awk "BEGIN { printf \"%d\", (''${A_ROOT_MIB:-0} + ''${A_VERITY_MIB:-0}) * 1.5 + 64 }")
          PERSIST_MIB=$((VG_FREE_INT - RESERVE_MIB))
        ''}

        if [ "$PERSIST_MIB" -le 0 ]; then
          echo "ERROR: no free space remains for persist after fixed slots and swap"
          exit 1
        fi

        echo "Creating persist LV from the remaining $PERSIST_MIB MiB..."
        lvcreate -L "''${PERSIST_MIB}M" -n persist pool
        mkfs.btrfs -L persist /dev/pool/persist

      else
        echo "persist LV already exists."
      fi

      PERSIST_TYPE=$(blkid -o value -s TYPE /dev/pool/persist 2>/dev/null || true)
      case "$PERSIST_TYPE" in
        btrfs)
          echo "persist LV already contains btrfs, retaining it."
          ;;
        *)
          echo "ERROR: persist LV has unexpected filesystem type: $PERSIST_TYPE"
          exit 1
          ;;
      esac

      echo "firstboot-persist: done."
    '';
  };
in
{
  _file = ./firstboot-persist.nix;

  config = lib.mkIf cfg.enable {

    # --- First-boot service ---
    systemd.services.firstboot-persist = {
      description = "Grow the storage pool and provision swap and persist";
      wantedBy = [ "local-fs-pre.target" ];
      before = [ "local-fs-pre.target" ];
      after = [
        "lvm2-activation.service"
        "lvm2-monitor.service"
      ];
      unitConfig = {
        DefaultDependencies = false;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${firstbootScript}/bin/firstboot-persist";
      };
    };

    # Ensure NixOS-generated mkswap service runs after we create the swap LV.
    systemd.services."mkswap-dev-pool-swap" = {
      after = [ "firstboot-persist.service" ];
      wants = [ "firstboot-persist.service" ];
    };

    # --- Filesystem and swap declarations ---

    fileSystems."/persist" = {
      device = "/dev/pool/persist";
      fsType = "btrfs";
      # Not neededForBoot: systemd waits for the device to appear
      # (created by firstboot-persist on first boot, or LVM activation on subsequent boots)
    };

    swapDevices = [
      {
        device = "/dev/pool/swap";
        randomEncryption.enable = true;
      }
    ];

    boot.initrd.supportedFilesystems.btrfs = true;
  };
}
