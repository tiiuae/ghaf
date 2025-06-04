# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  enable =
    ((builtins.hasAttr "verity" config.ghaf.partitioning) && config.ghaf.partitioning.verity.enable)
    || ((builtins.hasAttr "disko" config.ghaf.partitioning) && config.ghaf.partitioning.disko.enable);
in
{
  config = lib.mkIf enable {
    systemd.services.extendpersist =
      let
        partResizeCmds = pkgs.writeShellApplication {
          name = "partResizeScript";
          runtimeInputs =
            with pkgs;
            [
              btrfs-progs
              gnugrep
              gawk
              util-linux
              gptfdisk
              parted
            ]
            ++ lib.optionals config.ghaf.storage.encryption.enable [
              cryptsetup
            ];
          text = ''
            set -xeuo pipefail

            # Check which physical disk is used by btrfs
            # TODO use a label in case there are more than one btrfs partitions/subvolumes
            BTRFS_LOCATION=$(btrfs filesystem show | grep '/dev' | awk '{print $8}')
          ''
          + lib.optionalString config.ghaf.storage.encryption.enable ''
            # on encrypted disk `btrfs filesystem show` will return /dev/mapper/persist
            # map it to the actual partition
            BTRFS_LOCATION=$(cryptsetup status "$BTRFS_LOCATION" | grep 'device:' | awk '{ print $2 }')
          ''
          + ''
            # Get the actual device path
            P_DEVPATH=$(readlink -f "$BTRFS_LOCATION")

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
            echo '- +' | sfdisk -f -N "$PARTNUM" "$PARENT_DISK"

            # Call partprobe to update kernel's partitions
            partprobe

            touch /persist/.extendpersist
          ''
          + lib.optionalString config.ghaf.storage.encryption.enable ''
            echo | cryptsetup resize persist
          '';
        };
      in
      {
        description = "Extend the persist partition";
        unitConfig = {
          DefaultDependencies = "no"; # run before VMs are launched
          ConditionPathExists = "!/persist/.extendpersist";
        };
        wants = [
          "nix-store.mount"
          "persist.mount"
        ]
        ++ lib.optionals config.ghaf.storage.encryption.enable [
          "dev-mapper-persist.device"
        ];
        after = [
          "nix-store.mount"
          "persist.mount"
        ];
        wantedBy = [
          "sysinit.target"
        ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ]
        ++ lib.optionals config.ghaf.storage.encryption.enable [
          config.systemd.services.luks-enroll-tpm.name
        ];
        conflicts = [
          "shutdown.target"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe partResizeCmds}";
        };
      };

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
