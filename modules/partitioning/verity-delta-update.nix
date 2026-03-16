# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Device-side delta update service using desync content-addressed chunks.
# Replaces sysupdate's root/verity transfers with a chunk-based approach
# that only downloads blocks that differ from the currently running partition.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;
  delta = cfg.deltaUpdate;

  ukiName = config.boot.uki.name;

  updateScript = pkgs.writeShellApplication {
    name = "ghaf-delta-update";
    runtimeInputs = with pkgs; [
      curl
      desync
      jq
      util-linux
      coreutils
      systemd
    ];
    text = ''
      set -euo pipefail

      MANIFEST_URL="${delta.manifestUrl}"
      CHUNK_STORE_URL="${delta.chunkStoreUrl}"
      CACHE_DIR="/var/cache/desync"

      echo "ghaf-delta-update: Fetching manifest from $MANIFEST_URL"
      manifest="$(curl -fsSL "$MANIFEST_URL")"

      remote_version="$(echo "$manifest" | jq -r '.version')"
      current_version="${cfg.version}"

      echo "ghaf-delta-update: Current version: $current_version"
      echo "ghaf-delta-update: Remote version:  $remote_version"

      if [ "$remote_version" = "$current_version" ]; then
        echo "ghaf-delta-update: Already up to date."
        exit 0
      fi

      # --- Determine active slot by comparing dm-verity backing device ---
      # Through dm-verity, / is mounted from /dev/mapper/root. We resolve
      # which real block device backs it and compare against root-a/root-b
      # partlabel symlinks to determine the active slot.
      dm_backing=""
      if [ -e /sys/block/dm-0/slaves ]; then
        # Get the first (and only) slave device of the dm-verity target
        for slave in /sys/block/dm-0/slaves/*; do
          dm_backing="/dev/$(basename "$slave")"
          break
        done
      fi

      root_a_dev="$(readlink -f /dev/disk/by-partlabel/root-a 2>/dev/null || echo "")"
      root_b_dev="$(readlink -f /dev/disk/by-partlabel/root-b 2>/dev/null || echo "")"

      active_root=""
      inactive_root=""
      inactive_verity=""
      inactive_slot=""

      if [ "$dm_backing" = "$root_a_dev" ]; then
        active_root="/dev/disk/by-partlabel/root-a"
        inactive_root="/dev/disk/by-partlabel/root-b"
        inactive_verity="/dev/disk/by-partlabel/root-verity-b"
        inactive_slot="b"
      elif [ "$dm_backing" = "$root_b_dev" ]; then
        active_root="/dev/disk/by-partlabel/root-b"
        inactive_root="/dev/disk/by-partlabel/root-a"
        inactive_verity="/dev/disk/by-partlabel/root-verity-a"
        inactive_slot="a"
      else
        echo "ghaf-delta-update: ERROR: Could not determine active slot." >&2
        echo "  dm_backing=$dm_backing root_a=$root_a_dev root_b=$root_b_dev" >&2
        exit 1
      fi

      # Verify partition devices exist
      for dev in "$active_root" "$inactive_root" "$inactive_verity"; do
        if [ ! -e "$dev" ]; then
          echo "ghaf-delta-update: ERROR: Partition $dev not found" >&2
          exit 1
        fi
      done

      echo "ghaf-delta-update: Active root:     $active_root"
      echo "ghaf-delta-update: Inactive root:   $inactive_root (slot $inactive_slot)"
      echo "ghaf-delta-update: Inactive verity:  $inactive_verity"

      # Derive the base URL for artifacts from the manifest URL
      base_url="''${MANIFEST_URL%/*}"

      # --- Download and apply root image via delta chunks ---
      caibx_file="$(echo "$manifest" | jq -r '.root.caibx')"
      caibx_url="$base_url/$caibx_file"

      echo "ghaf-delta-update: Downloading root image (delta) from $caibx_url"
      echo "ghaf-delta-update: Using seed: $active_root"

      mkdir -p "$CACHE_DIR"
      desync --digest sha256 extract \
        --store "$CHUNK_STORE_URL" \
        --seed "$active_root" \
        --cache "$CACHE_DIR" \
        "$caibx_url" \
        "$inactive_root"

      echo "ghaf-delta-update: Root image written to $inactive_root"

      # --- Download and write verity hash tree (small, direct download) ---
      verity_file="$(echo "$manifest" | jq -r '.verity.file')"
      verity_url="$base_url/$verity_file"
      verity_sha256="$(echo "$manifest" | jq -r '.verity.sha256')"

      echo "ghaf-delta-update: Downloading verity from $verity_url"
      curl -fsSL "$verity_url" | dd of="$inactive_verity" bs=1M conv=notrunc status=progress

      # Verify verity checksum
      actual_verity_sha256="$(sha256sum "$inactive_verity" | cut -d' ' -f1)"
      if [ "$actual_verity_sha256" != "$verity_sha256" ]; then
        echo "ghaf-delta-update: ERROR: Verity checksum mismatch!" >&2
        echo "  expected: $verity_sha256" >&2
        echo "  actual:   $actual_verity_sha256" >&2
        exit 1
      fi
      echo "ghaf-delta-update: Verity checksum verified: $verity_sha256"

      # --- Update partition labels for the inactive slot ---
      inactive_root_dev="$(readlink -f "$inactive_root")"
      inactive_verity_dev="$(readlink -f "$inactive_verity")"

      # Resolve device to disk + partition number for sfdisk
      # e.g. /dev/nvme0n1p3 → disk=/dev/nvme0n1 partnum=3
      resolve_part() {
        local dev="$1"
        local partnum
        partnum="$(cat "/sys/class/block/$(basename "$dev")/partition")"
        local parent
        parent="$(basename "$(readlink -f "/sys/class/block/$(basename "$dev")/..")")"
        echo "/dev/$parent" "$partnum"
      }

      read -r root_disk root_partnum <<< "$(resolve_part "$inactive_root_dev")"
      read -r verity_disk verity_partnum <<< "$(resolve_part "$inactive_verity_dev")"

      echo "ghaf-delta-update: Updating partition labels..."
      sfdisk --part-label "$root_disk" "$root_partnum" "root-$remote_version"
      sfdisk --part-label "$verity_disk" "$verity_partnum" "root-verity-$remote_version"
      echo "ghaf-delta-update: Labels updated: root-$remote_version, root-verity-$remote_version"

      # --- Install UKI with boot-counting ---
      uki_file="$(echo "$manifest" | jq -r '.uki.file')"
      uki_url="$base_url/$uki_file"
      uki_sha256="$(echo "$manifest" | jq -r '.uki.sha256')"

      esp_mount="$(findmnt -n -o TARGET /efi 2>/dev/null || findmnt -n -o TARGET /boot/efi 2>/dev/null || findmnt -n -o TARGET /boot 2>/dev/null || echo "/efi")"
      uki_dir="$esp_mount/EFI/Linux"
      mkdir -p "$uki_dir"

      # Download the UKI to a temporary file for verification
      uki_target="${ukiName}_''${remote_version}+3.efi"
      echo "ghaf-delta-update: Downloading UKI from $uki_url"
      curl -fsSL "$uki_url" -o "$uki_dir/$uki_target.tmp"

      # Verify UKI checksum
      actual_uki_sha256="$(sha256sum "$uki_dir/$uki_target.tmp" | cut -d' ' -f1)"
      if [ "$actual_uki_sha256" != "$uki_sha256" ]; then
        echo "ghaf-delta-update: ERROR: UKI checksum mismatch!" >&2
        echo "  expected: $uki_sha256" >&2
        echo "  actual:   $actual_uki_sha256" >&2
        rm -f "$uki_dir/$uki_target.tmp"
        exit 1
      fi
      mv "$uki_dir/$uki_target.tmp" "$uki_dir/$uki_target"
      echo "ghaf-delta-update: UKI checksum verified: $uki_sha256"
      echo "ghaf-delta-update: UKI installed as $uki_dir/$uki_target"

      # Clean up old UKIs (keep current + new)
      find "$uki_dir" -name "${ukiName}_*.efi" \
        ! -name "$uki_target" \
        ! -name "${ukiName}_''${current_version}*" \
        -delete 2>/dev/null || true

      # Clear chunk cache to reclaim space
      rm -rf "$CACHE_DIR"

      echo "ghaf-delta-update: Update to version $remote_version complete."
      echo "ghaf-delta-update: Rebooting to apply update..."
      systemctl reboot
    '';
  };
in
{
  _file = ./verity-delta-update.nix;

  config = lib.mkIf (cfg.enable && delta.enable) {
    environment.systemPackages = [ pkgs.desync ];

    systemd.services.ghaf-delta-update = {
      description = "Ghaf delta update via content-addressed chunks";
      after = [
        "network-online.target"
        "multi-user.target"
      ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe updateScript;
        StandardOutput = "journal+console";
        StandardError = "journal+console";

        # Hardening
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/dev"
          "/efi"
          "/boot"
          "/var/cache/desync"
        ];
      };
    };

    systemd.timers.ghaf-delta-update = {
      description = "Periodic check for Ghaf delta updates";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
        RandomizedDelaySec = "5min";
      };
    };
  };
}
