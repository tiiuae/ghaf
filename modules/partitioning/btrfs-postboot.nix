# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  postBootCmds = pkgs.writeShellApplication {
    name = "postBootScript";
    runtimeInputs =
      with pkgs;
      [
        btrfs-progs
        gnugrep
        gawk
        util-linux
        gptfdisk
        parted
        lvm2
        coreutils
        systemd
      ]
      ++ lib.optionals config.ghaf.storage.encryption.enable [
        cryptsetup
      ];
    text = ''
      # Enable logging
      exec > >(tee -a /persist/postboot.log) 2>&1
      echo "Starting postBootScript at $(date)"

      if [ ! -f /persist/.extendpersist ]; then
        echo "Marker file not found, proceeding with resize..."

        # Extracts the Physical Volume path for the 'pool' VG
        DEV_LOCATION=$(pvdisplay -C -o pv_name --noheadings -S vg_name=pool | head -n1 | tr -d '[:space:]')
        echo "Found PV: $DEV_LOCATION"
        DEVICE="$DEV_LOCATION"
    ''
    + lib.optionalString config.ghaf.storage.encryption.enable ''
      # on encrypted disk `pvdisplay` will return /dev/mapper/crypted
      # map it to the actual partition
      if cryptsetup status "$DEVICE" >/dev/null 2>&1; then
          echo "Device is encrypted, resolving underlying device..."
          DEV_LOCATION=$(cryptsetup status "$DEVICE" | grep 'device:' | awk '{ print $2 }')
          echo "Resolved underlying device: $DEV_LOCATION"
      else
          echo "Device $DEVICE is not a LUKS device (or not active), assuming plain partition."
      fi
    ''
    + ''
      # Get the actual device path
      P_DEVPATH=$(readlink -f "$DEV_LOCATION")
      echo "Canonical device path: $P_DEVPATH"

      # Extract the partition number using regex
      if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
        PARTNUM=$(echo "$P_DEVPATH" | grep -o '[0-9]*$')
        PARENT_DISK=/dev/$(lsblk --nodeps --noheadings -o pkname "$P_DEVPATH")
        echo "Partition: $PARTNUM, Parent Disk: $PARENT_DISK"
      else
        echo "No partition number found in device path: $P_DEVPATH"
        exit 1
      fi

      # Fix GPT first
      echo "Fixing GPT..."
      sgdisk "$PARENT_DISK" -e || true

      # Extend the partition to use unallocated space
      echo "Resizing partition..."
      parted -s -a opt "$PARENT_DISK" "resizepart $PARTNUM 100%" || true

      # Call partprobe to update kernel's partitions
      partprobe || true
      udevadm settle || true
    ''
    + lib.optionalString config.ghaf.storage.encryption.enable ''
      if cryptsetup status crypted >/dev/null 2>&1; then
          echo "Resizing LUKS container..."
          # For deferred encryption, the device is unlocked with password (empty in debug mode)
          # cryptsetup resize needs authentication even when device is already open
          ${
            if !config.ghaf.storage.encryption.interactiveSetup then
              ''
                # Automated mode: use default password
                printf 'ghaf' | cryptsetup resize -v crypted --key-file=- 2>&1 || {
                  echo "WARNING: LUKS resize failed, trying without key..."
                  cryptsetup resize -v crypted || true
                }
              ''
            else
              ''
                # Interactive mode: prompt user for password
                echo "LUKS container needs to be resized to use full disk space."
                while true; do
                PASSPHRASE=$(systemd-ask-password --timeout=0 "Enter encryption PIN / password:");

                    if printf '%s' "$PASSPHRASE" | cryptsetup resize -v crypted 2>&1; then
                      echo "LUKS resize successful"
                      break
                    fi
                      echo "Resize failed. Retrying in 2 seconds..."
                    sleep 2
                  done
              ''
          }
      fi
    ''
    + ''
        echo "Extending 'persist' Logical Volume to use all free space..."
        pvresize "$DEVICE" || true
        lvextend -l +100%FREE /dev/pool/persist || true

        echo "Creating marker file..."
        touch /persist/.extendpersist
        echo "Done."
      else
        echo "Marker file exists, skipping."
      fi
    '';
  };

in
{
  _file = ./btrfs-postboot.nix;

  options.ghaf.partitioning.btrfs-postboot.enable =
    lib.mkEnableOption "btrfs post-boot partition extension";

  config = lib.mkIf config.ghaf.partitioning.btrfs-postboot.enable {

    # To debug postBootCommands, one may run
    # journalctl -u initrd-nixos-activation.service
    # inside the running Ghaf host.
    boot.postBootCommands = "${postBootCmds}/bin/postBootScript";

    systemd.services.extendbtrfs =
      let
        extendbtrfs = pkgs.writeShellApplication {
          name = "extendbtrfs";
          runtimeInputs = [ pkgs.btrfs-progs ];
          text = ''
            # Extend btrfs to use newly allocated space
            ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /persist
          '';
        };
      in
      {
        enable = true;
        description = "Extend the btrfs filesystem";
        wantedBy = [ "multi-user.target" ];
        after = [ "persist.mount" ];
        requires = [ "persist.mount" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${extendbtrfs}/bin/extendbtrfs";
        };
      };
  };
}
