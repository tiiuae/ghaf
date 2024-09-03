# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  postBootCmds = ''
    set -xeuo pipefail

    # Check which physical disk is used by ZFS
    ZFS_POOLNAME=$(${pkgs.zfs}/bin/zpool list | ${pkgs.gnugrep}/bin/grep -v NAME |  ${pkgs.gawk}/bin/awk '{print $1}')
    ZFS_LOCATION=$(${pkgs.zfs}/bin/zpool status -P | ${pkgs.gnugrep}/bin/grep dev | ${pkgs.gawk}/bin/awk '{print $1}')

    # Get the actual device path
    P_DEVPATH=$(readlink -f "$ZFS_LOCATION")

    # Extract the partition number using regex
    if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
      PARTNUM=$(echo "$P_DEVPATH" | ${pkgs.gnugrep}/bin/grep -o '[0-9]*$')
      PARENT_DISK=$(echo "$P_DEVPATH" | ${pkgs.gnused}/bin/sed 's/[0-9]*$//')
    else
      echo "No partition number found in device path: $P_DEVPATH"
    fi

    # Fix GPT first
    ${pkgs.gptfdisk}/bin/sgdisk "$PARENT_DISK" -e

    # Call partprobe to update kernel's partitions
    ${pkgs.parted}/bin/partprobe

    # Extend the partition to use unallocated space
    ${pkgs.parted}/bin/parted -s -a opt "$PARENT_DISK" "resizepart $PARTNUM 100%"

    # Extend ZFS pool to use newly allocated space
    ${pkgs.zfs}/bin/zpool online -e "$ZFS_POOLNAME" "$ZFS_LOCATION"
  '';
in
{
  boot.postBootCommands = postBootCmds;
}
