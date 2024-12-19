# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  ...
}:
let
  diskEncryption = config.ghaf.disk.encryption.enable;
in
{
  boot.initrd.systemd.extraBin = {
    grep = "${pkgs.gnugrep}/bin/grep";
    lsblk = "${pkgs.util-linux}/bin/lsblk";
    sgdisk = "${pkgs.gptfdisk}/bin/sgdisk";
    partprobe = "${pkgs.parted}/bin/partprobe";
    parted = "${pkgs.parted}/bin/parted";
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
  };

  # To debug luksEncryption, one may run
  # journalctl -u luksEncryption.service
  # inside the running Ghaf host.
  boot.initrd.systemd.services.luksEncryption = {
    description = "Disk encryption service";
    wantedBy = [ "basic.target" ];
    before = [ "sysroot.mount" ];
    after = [ "local-fs.target" ];

    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    script = ''
      set -xeuo pipefail
      DISK_PSWD="" TPM2_PIN=""

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
        # Request the password from the user, only if not entered previously
        if [[ -z "$DISK_PSWD" ]]; then
          DISK_PSWD=$(systemd-ask-password --keyname=diskPswd --accept-cached -n "Please enter password you want to keep for disk encryption:")
        fi

        # Format with LUKS and open the device
        echo -n "$DISK_PSWD" | cryptsetup luksFormat --type luks2 -q "$1"
        echo -n "$DISK_PSWD" | cryptsetup luksOpen "$1" "$2" --persistent

        # Request TPM2 PIN from the user, only if not entered previously
        if [[ -z "$TPM2_PIN" ]]; then
          TPM2_PIN=$(systemd-ask-password --keyname=diskPswd --accept-cached -n "Please enter TPM2 token PIN for disk encryption:")
        fi

        # Automatically assigns keys to a specific slot in the TPM
        NEWPIN="$TPM2_PIN" PASSWORD="$DISK_PSWD" systemd-cryptenroll --tpm2-device auto --tpm2-with-pin=yes "$1"
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

      # Check if ZFS pool has LUKS encryption
      set +o pipefail
      if (cryptsetup status "$DATA_POOLNAME") | grep -q "is inactive"; then
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
}
