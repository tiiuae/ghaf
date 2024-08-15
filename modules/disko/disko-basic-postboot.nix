# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  postBootCmds = ''
    set -xeuo pipefail

    readarray -t partitions <<<"$(${pkgs.util-linux}/bin/lsblk -np -o PATH,MAJ:MIN,PKNAME,MOUNTPOINT)"

    # Find out the root partition in a loop, and its LVM pool parent disk
    for p in "''${partitions[@]}"
    do
            P_DEVPATH=$(echo "$p" | ${pkgs.gawk}/bin/awk '{print $1}')
            P_PKNAME=$(echo "$p" | ${pkgs.gawk}/bin/awk '{print $3}')
            P_MOUNTPOINT=$(echo "$p" | ${pkgs.gawk}/bin/awk '{print $4}')

            [[ "$P_MOUNTPOINT" == "/" ]] && {
                    FOUND=1
                    DEVPATH="$P_DEVPATH"
                    PKNAME="$P_PKNAME"
            }
    done

    # If root partition was not found, exit at this point, but still return 0, so
    # it won't stop device from booting.
    [[ "$FOUND" != 1 ]] && echo "Did not find root partition" && exit 0

    # Find parent device of the root partition
    for p in "''${partitions[@]}"
    do
            P_DEVPATH=$(echo "$p" | ${pkgs.gawk}/bin/awk '{print $1}')
            P_MAJMIN=$(echo "$p" | ${pkgs.gawk}/bin/awk '{print $2}')
            P_PKNAME=$(echo "$p" | ${pkgs.gawk}/bin/awk '{print $3}')

            [[ "$P_DEVPATH" == "$PKNAME" ]] && {
                    FOUND_PARENT=1
                    PARENT_DISK="$P_PKNAME"
                    PARTNUM=$(echo "$P_MAJMIN" | ${pkgs.gawk}/bin/awk -F: '{print $2}')
            }
    done

    # If boot device was not found, exit at this point, but still return 0, so it
    # won't stop device from booting.
    [[ "$FOUND_PARENT" != 1 ]] && echo "Did not find boot device" && exit 0

    # First enlarge the physical volume on the disk
    echo ",+," | ${pkgs.util-linux}/bin/sfdisk -N"$PARTNUM" --no-reread "$PARENT_DISK"

    # Call partprobe to update kernel's partitions
    ${pkgs.parted}/bin/partprobe

    # Extend the phyiscal volume
    ${pkgs.lvm2.bin}/bin/pvresize "$PKNAME"

    # Extend the logical volume
    ${pkgs.lvm2.bin}/bin/lvextend --noudevsync -l +100%FREE "$DEVPATH"

    # Finally resize the filesystem inside the logical volume
    ${pkgs.e2fsprogs}/bin/resize2fs "$DEVPATH"
  '';
in
{
  boot.postBootCommands = postBootCmds;
}
