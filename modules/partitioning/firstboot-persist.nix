# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# First-boot service for Jetson Orin A/B verity boot.
#
# The pre-built LVM image only contains the A-slot root and verity LVs
# to minimize flash image size (~5.5 GiB instead of ~16 GiB). On first
# boot this service:
#
#   1. Expands the LVM PV after initrd has grown APP and the open LUKS mapping
#   2. Creates swap and persist LVs from the free space, reserving
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
  cfg = config.ghaf.partitioning.verity;
  # TODO: make this configurable?
  swapSizeMiB = 4096;

  firstbootScript = pkgs.writeShellApplication {
    name = "firstboot-persist";
    runtimeInputs = with pkgs; [
      gnugrep
      gawk
      lvm2
      coreutils
      btrfs-progs
      util-linux
    ];
    text = ''
      set -euo pipefail
      echo "firstboot-persist: starting at $(date)"

      # Initrd grows APP and the open LUKS mapping while the OP-TEE DUK is
      # still available in its shared keyring.  Only the PV and new LVs are
      # safe to grow here after switch-root.

      PV_PATH=$(pvdisplay -C -o pv_name --noheadings -S vg_name=pool | head -n1 | tr -d '[:space:]')
      [[ -n "$PV_PATH" ]] || { echo "ERROR: pool PV not found"; exit 1; }
      echo "PV: $PV_PATH -> $(readlink -f "$PV_PATH")"

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

      # --- Create persist LV and finish an interrupted format if needed ---

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

      else
        echo "persist LV already exists."
      fi

      PERSIST_TYPE=$(blkid -o value -s TYPE /dev/pool/persist 2>/dev/null || true)
      case "$PERSIST_TYPE" in
        "")
          echo "Formatting uninitialized persist LV as btrfs..."
          mkfs.btrfs -L persist /dev/pool/persist
          ;;
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
