# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, pkgs, ... }:
let
  diskEncryption = config.ghaf.disk.encryption.enable;
  zfsPostBoot = pkgs.writeShellApplication {
    name = "zfsPostBootScript";
    runtimeInputs = with pkgs; [
      zfs
      gnugrep
      gawk
      cryptsetup
      util-linux
      gptfdisk
      parted
      systemd
    ];
    text = ''
      set -xeuo pipefail

      disk_resize() {
        # Fix GPT first
        sgdisk "$1" -e

        # Call partprobe to update kernel's partitions
        partprobe

        # Extend the partition to use unallocated space
        parted -s -a opt "$1" "resizepart $2 100%"

        # Extend ZFS pool to use newly allocated space
        zpool online -e "$3" "$4"
      }

      device_encryption() {
        # Generate a random password with 12 characters
        pswd=$(tr -dc 'A-Za-z0-9!@$%' < /dev/urandom | head -c 12)

        # Format with LUKS and open the device
        echo -n "$pswd" | cryptsetup luksFormat --type luks2 -q "$1"
        echo -n "$pswd" | cryptsetup luksOpen "$1" "$2" --persistent

        # Automatically assigns keys to a specific slot in the TPM
        PASSWORD="$pswd" systemd-cryptenroll --tpm2-device auto "$1"

        # Add recovery mechanism
        echo -e "\n\nBelow are the recovery keys generated for $1 \n" >> /root/recovery_keys 2>&1
        PASSWORD="$pswd" systemd-cryptenroll --recovery-key "$1" >> /root/recovery_keys 2>&1
      }

      IS_DISK_ENCRYPTION_ENABLED=${toString diskEncryption}
      DATA_POOLNAME=zfs_data
      zpool import -f "$DATA_POOLNAME"

      # Check which physical disk is used by ZFS
      ZFS_POOLNAME=$(zpool list | grep -v NAME | grep $DATA_POOLNAME | awk '{print $1}')
      ZFS_LOCATION=$(zpool status "$ZFS_POOLNAME" -P | grep dev | awk '{print $1}')

      # Get the actual device path
      P_DEVPATH=$(readlink -f "$ZFS_LOCATION")

      # Extract the partition number using regex
      if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
        PARTNUM=$(echo "$P_DEVPATH" | grep -o '[0-9]*$')
        PARENT_DISK=/dev/$(lsblk -no pkname "$P_DEVPATH")
      else
        echo "No partition number found in device path: $P_DEVPATH"
      fi

      # In case we are not using encryption, resize and exit
      if ((!IS_DISK_ENCRYPTION_ENABLED)); then
        disk_resize "$PARENT_DISK" "$PARTNUM" "$ZFS_POOLNAME" "$ZFS_LOCATION"
        exit 0
      fi

      set +o pipefail
      # Check if ZFS pool has LUKS encryption
      if (cryptsetup status "$ZFS_POOLNAME") | grep -q "is inactive"; then
        disk_resize "$PARENT_DISK" "$PARTNUM" "$ZFS_POOLNAME" "$ZFS_LOCATION"

        # Exporting pool to avoid device in use errors
        zpool export "$ZFS_POOLNAME"

        device_encryption "$P_DEVPATH" "$ZFS_POOLNAME"

        # Create pool, datasets as luksFormat will erase pools, ZFS datasets stored on that partition
        zpool create -o ashift=12 -O compression=lz4 -O acltype=posixacl -O xattr=sa -f "$ZFS_POOLNAME" /dev/mapper/"$ZFS_POOLNAME"
        zfs create -o quota=30G "$ZFS_POOLNAME"/vm_storage
        zfs create -o quota=10G -o mountpoint=none "$ZFS_POOLNAME"/recovery
        zfs create -o quota=50G "$ZFS_POOLNAME"/gp_storage
        zfs create "$ZFS_POOLNAME"/storagevm

        # This will allocate 10GB of reserved memory on the pool
        zfs set refreservation=10G "$ZFS_POOLNAME"
      fi

      SWAP_DEVICE=$(blkid -t TYPE=swap -o device)
      # Check if swap memory has LUKS encryption
      if ! (cryptsetup status "$SWAP_DEVICE" | grep -q "active"); then
        device_encryption "$SWAP_DEVICE" "swap"

        # Create a swap filesystem
        mkswap /dev/mapper/swap -L swap
      fi

      # Activate swap memory
      swapon /dev/mapper/swap
    '';
  };

in
{
  # To debug postBootCommands, one may run
  # journalctl -u initrd-nixos-activation.service
  # inside the running Ghaf host.
  boot.postBootCommands = "${zfsPostBoot}/bin/zfsPostBootScript";
}
