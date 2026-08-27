# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  # The B slot is not reserved in the image (see disko-debug-partition.nix), so
  # it is cut here -- after pvresize has exposed the whole disk and before
  # persist takes 100%FREE. Ordering is the whole trick: persist claims
  # everything left, so anything wanted afterwards has to be taken first.
  #
  # Guarded because btrfs-postboot is also imported by verity-release-partition,
  # which does not declare these sizes.
  hasDisko = config.ghaf.partitioning ? disko;
  bSlotCmds = lib.optionalString hasDisko ''
    b_root=${toString config.ghaf.partitioning.disko.rootSize}
    b_verity=${toString config.ghaf.partitioning.disko.veritySize}
    b_needed=$((b_root + b_verity))
    if lvs pool/root_empty >/dev/null 2>&1; then
      echo "B slot already present, leaving it alone."
    else
      vg_free=$(vgs --noheadings --nosuffix --units m -o vg_free pool 2>/dev/null | tr -d ' ' | cut -d. -f1 || true)
      if [ "''${vg_free:-0}" -ge "$b_needed" ]; then
        echo "Creating the B slot ($b_needed MiB) before persist claims the rest..."
        # -Zn -Wn: zeroing opens /dev/pool/<lv>, which udev has not made yet
        # this early -- "device not cleared", and the create aborts. Empty
        # placeholders an A/B update overwrites, so nothing needs clearing.
        if DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n root_empty -L "''${b_root}M" pool &&
          DM_DISABLE_UDEV=1 lvcreate -y -Zn -Wn -n verity_empty -L "''${b_verity}M" pool; then
          echo "B slot created."
        else
          echo "WARNING: could not create the B slot; A/B updates will be unavailable."
        fi
      else
        # Not a failure: the machine is installed and boots. It simply has
        # no room for a second slot, which is a property of the disk.
        echo "WARNING: ''${vg_free:-0} MiB free but the B slot needs $b_needed MiB."
        echo "         Installed and bootable; A/B updates will be unavailable."
      fi
    fi
  '';

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
      pvresize "$DEVICE" || true
    ''
    + bSlotCmds
    + ''
        echo "Extending 'persist' Logical Volume to use all free space..."
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

    systemd.services =
      let
        vmsWithEncryptedStorage = lib.filterAttrs (
          _name: vm:
          let
            vmConfig = lib.ghaf.vm.getConfig vm;
          in
          vmConfig != null
          && lib.hasAttr "storagevm" vmConfig.ghaf
          && vmConfig.ghaf.storagevm.encryption.enable
        ) config.microvm.vms;

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
        extendbtrfs = {
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
      }
      // lib.optionalAttrs config.ghaf.virtualization.microvm.storeOnDisk.enable (
        lib.mapAttrs' (
          vmName: _:
          lib.nameValuePair "microvm@${vmName}" {
            # Disk-backed VM runners create sparse images and filesystems below
            # /persist before launching the VMM. On first boot /persist is still
            # a 2 GiB Btrfs filesystem until extendbtrfs completes. Starting the
            # runners concurrently can fill it, leaving touched but unformatted
            # images which the runners then mistake for initialized volumes on
            # later boots.
            after = [ "extendbtrfs.service" ];
            requires = [ "extendbtrfs.service" ];
          }
        ) config.microvm.vms
      )
      // lib.mapAttrs' (
        vmName: _:
        lib.nameValuePair "format-microvm-storage-${vmName}" {
          # Encrypted VM storage is prepared by a separate oneshot before the
          # VMM starts. Order that writer directly, rather than only ordering
          # microvm@, so it cannot fill the initial 2 GiB Btrfs filesystem
          # while extendbtrfs is still growing /persist on first boot.
          after = [ "extendbtrfs.service" ];
          requires = [ "extendbtrfs.service" ];
        }
      ) vmsWithEncryptedStorage;
  };
}
