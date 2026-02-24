# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# First-boot service for Jetson Orin A/B verity boot.
#
# The pre-built LVM image only contains the A-slot root and verity LVs
# to minimize flash image size (~5.5 GiB instead of ~16 GiB). On first
# boot this service:
#
#   1. Resizes the GPT and APP partition to fill the eMMC
#   2. Expands the LVM PV to match
#   3. Creates swap and persist LVs from the free space, reserving
#      enough room for a future B-slot root+verity pair (OTA updates)
#
# Every step is idempotent — the service can be interrupted and re-run
# safely (e.g. after a power loss during first boot).
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
  cfg = config.ghaf.partitioning.verity-volume;
  # TODO: make this configurable?
  swapSizeMiB = 4096;

  firstbootScript = pkgs.writeShellApplication {
    name = "firstboot-persist";
    runtimeInputs = with pkgs; [
      gnugrep
      gawk
      util-linux
      gptfdisk
      parted
      lvm2
      coreutils
      btrfs-progs
    ];
    text = ''
      set -euo pipefail
      echo "firstboot-persist: starting at $(date)"

      # --- Resize APP partition to fill the eMMC (idempotent) ---

      PV_PATH=$(pvdisplay -C -o pv_name --noheadings -S vg_name=pool | head -n1 | tr -d '[:space:]')
      P_DEVPATH=$(readlink -f "$PV_PATH")
      echo "PV: $PV_PATH -> $P_DEVPATH"

      if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
        PARTNUM=$(echo "$P_DEVPATH" | grep -o '[0-9]*$')
        PARENT_DISK=/dev/$(lsblk --nodeps --noheadings -o pkname "$P_DEVPATH")
      else
        echo "ERROR: cannot determine partition number from $P_DEVPATH"
        exit 1
      fi

      echo "Fixing GPT and resizing partition $PARTNUM on $PARENT_DISK..."
      sgdisk "$PARENT_DISK" -e || true
      # parted resizepart updates the kernel's partition size synchronously
      # via BLKPG_RESIZE_PARTITION ioctl, so no partprobe/udevadm needed.
      parted -s -a opt "$PARENT_DISK" "resizepart $PARTNUM 100%" || true

      # pvresize is idempotent — no-op if PV already matches partition
      echo "Resizing PV..."
      pvresize "$PV_PATH"

      # --- Compute B-slot reservation ---

      A_ROOT_MIB=$(lvs --noheadings -o lv_size --nosuffix --units m -S "vg_name=pool && lv_name=~^root_" | head -1 | tr -d '[:space:]')
      A_VERITY_MIB=$(lvs --noheadings -o lv_size --nosuffix --units m -S "vg_name=pool && lv_name=~^verity_" | head -1 | tr -d '[:space:]')
      # Reserve 50% headroom on top of the current A-slot sizes so the
      # B-slot can accommodate a significantly larger image after OTA
      # updates that add packages or data.
      RESERVE_MIB=$(awk "BEGIN { printf \"%d\", (''${A_ROOT_MIB:-0} + ''${A_VERITY_MIB:-0}) * 1.5 + 64 }")
      echo "B-slot reservation: $RESERVE_MIB MiB (1.5 * (root=$A_ROOT_MIB + verity=$A_VERITY_MIB) + 64)"

      # --- Create swap LV (skip if already exists) ---

      if [ ! -e /dev/pool/swap ]; then
        echo "Creating swap LV (${toString swapSizeMiB} MiB)..."
        lvcreate -L ${toString swapSizeMiB}M -n swap pool
      else
        echo "swap LV already exists, skipping."
      fi

      # --- Create persist LV (skip if already exists) ---

      if [ ! -e /dev/pool/persist ]; then
        VG_FREE_MIB=$(vgs --noheadings -o vg_free --nosuffix --units m pool | tr -d '[:space:]')
        VG_FREE_INT=$(awk "BEGIN { printf \"%d\", $VG_FREE_MIB }")
        PERSIST_MIB=$(( VG_FREE_INT - RESERVE_MIB ))

        if [ "$PERSIST_MIB" -le 0 ]; then
          echo "ERROR: not enough free space (free=$VG_FREE_INT, reserve=$RESERVE_MIB)"
          exit 1
        fi

        echo "Creating persist LV: $PERSIST_MIB MiB (leaving $RESERVE_MIB MiB for B-slot)"
        lvcreate -L "''${PERSIST_MIB}M" -n persist pool

        echo "Formatting persist as btrfs..."
        mkfs.btrfs -L persist /dev/pool/persist
      else
        echo "persist LV already exists, skipping."
      fi

      echo "firstboot-persist: done."
    '';
  };
in
{
  _file = ./firstboot-persist.nix;

  config = lib.mkIf cfg.enable {

    # --- First-boot service ---
    systemd.services.firstboot-persist = {
      description = "Create swap and persist LVs on first boot";
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
