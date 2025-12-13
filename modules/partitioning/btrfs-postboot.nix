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
      ]
      ++ lib.optionals config.ghaf.storage.encryption.enable [
        cryptsetup
      ];
    text = ''
      if [ ! -f /persist/.extendpersist ]; then
        # Extracts the Physical Volume path
        DEV_LOCATION=$(pvdisplay | grep "PV Name" | awk '{print $3}')
        DEVICE="$DEV_LOCATION"
    ''
    + lib.optionalString config.ghaf.storage.encryption.enable ''
      # on encrypted disk `pvdisplay` will return /dev/mapper/crypted
      # map it to the actual partition
      DEV_LOCATION=$(cryptsetup status "$DEVICE" | grep 'device:' | awk '{ print $2 }')
    ''
    + ''
      # Get the actual device path
      P_DEVPATH=$(readlink -f "$DEV_LOCATION")

      # Extract the partition number using regex
      if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
        PARTNUM=$(echo "$P_DEVPATH" | grep -o '[0-9]*$')
        PARENT_DISK=/dev/$(lsblk --nodeps --noheadings -o pkname "$P_DEVPATH")
      else
        echo "No partition number found in device path: $P_DEVPATH"
      fi

      # Fix GPT first
      sgdisk "$PARENT_DISK" -e

      # Extend the partition to use unallocated space
      parted -s -a opt "$PARENT_DISK" "resizepart $PARTNUM 100%"

      # Call partprobe to update kernel's partitions
      partprobe
    ''
    + lib.optionalString config.ghaf.storage.encryption.enable ''
      echo | cryptsetup resize crypted
    ''
    + ''
        echo "Extending 'persist' Logical Volume to use all free space..."
        pvresize "$DEVICE"
        lvextend -l +100%FREE /dev/pool/persist
        touch /persist/.extendpersist
      fi
    '';
  };

  enable =
    ((builtins.hasAttr "verity" config.ghaf.partitioning) && config.ghaf.partitioning.verity.enable)
    || ((builtins.hasAttr "disko" config.ghaf.partitioning) && config.ghaf.partitioning.disko.enable);
in
{
  config = lib.mkIf enable {

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
