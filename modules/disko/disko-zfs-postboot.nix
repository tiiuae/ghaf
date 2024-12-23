# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
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
    ];
    text = ''
      set -xeuo pipefail

      # Check which physical disk is used by ZFS
      ENCRYPTED_POOL=zfs_data
      zpool import -f $ENCRYPTED_POOL
      ZFS_POOLNAME=$(zpool list | grep -v NAME | grep $ENCRYPTED_POOL | awk '{print $1}')
      ZFS_LOCATION=$(zpool status -P | grep dev | grep "$ZFS_POOLNAME" | awk '{print $1}')

      # Get the actual device path
      P_DEVPATH=$(cryptsetup status "$ZFS_POOLNAME" | grep device | awk '{print $2}')

      # Extract the partition number using regex
      if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
        PARTNUM=$(echo "$P_DEVPATH" | grep -o '[0-9]*$')
        PARENT_DISK=/dev/$(lsblk -no pkname "$P_DEVPATH" | head -n 1)
      else
        echo "No partition number found in device path: $P_DEVPATH"
      fi

      # Fix GPT first
      sgdisk "$PARENT_DISK" -e

      # Call partprobe to update kernel's partitions
      partprobe

      # Extend the partition to use unallocated space
      parted -s -a opt "$PARENT_DISK" "resizepart $PARTNUM 100%"

      # Extend ZFS pool to use newly allocated space
      zpool online -e "$ZFS_POOLNAME" "$ZFS_LOCATION"
    '';
  };

in
{
  # To debug postBootCommands, one may run
  # journalctl -u initrd-nixos-activation.service
  # inside the running Ghaf host.
  boot.postBootCommands = "${zfsPostBoot}/bin/zfsPostBootScript";
}
