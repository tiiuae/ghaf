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
#   2. Creates the fixed-capacity empty B-slot root and verity LVs
#   3. Creates swap and persist LVs from the remaining free space
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

      # --- Provision the fixed-capacity B slot before persist takes the rest ---

      ensure_empty_lv() {
        name="$1"
        expected_mib="$2"
        if lvs "pool/$name" >/dev/null 2>&1; then
          actual_mib=$(lvs --noheadings -o lv_size --nosuffix --units m "pool/$name" \
            | awk '{ sub(/^</, "", $1); printf "%d", $1 }')
          if [ "$actual_mib" -ne "$expected_mib" ]; then
            echo "ERROR: pool/$name is $actual_mib MiB, expected $expected_mib MiB" >&2
            exit 1
          fi
          echo "pool/$name already has the required $expected_mib MiB capacity."
        else
          echo "Creating pool/$name ($expected_mib MiB)..."
          DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n "$name" -L "''${expected_mib}M" pool
        fi
      }

      ensure_empty_lv root_empty ${toString cfg.rootSlotSizeMiB}
      ensure_empty_lv verity_empty ${toString cfg.veritySlotSizeMiB}
      vgmknodes pool

      # --- Create swap LV (skip if already exists) ---

      if [ ! -e /dev/pool/swap ]; then
        echo "Creating swap LV (${toString swapSizeMiB} MiB)..."
        lvcreate -L ${toString swapSizeMiB}M -n swap pool
      else
        echo "swap LV already exists, skipping."
      fi

      # --- Create persist LV and finish an interrupted format if needed ---

      if [ ! -e /dev/pool/persist ]; then
        VG_FREE_INT=$(vgs --noheadings -o vg_free --nosuffix --units m pool \
          | awk '{ sub(/^</, "", $1); printf "%d", $1 }')
        PERSIST_MIB=$VG_FREE_INT

        if [ "$PERSIST_MIB" -le 0 ]; then
          echo "ERROR: no free space remains for persist after fixed slots and swap"
          exit 1
        fi

        echo "Creating persist LV from the remaining $PERSIST_MIB MiB..."
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
      description = "Create inactive system slot, swap, and persist LVs on first boot";
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
