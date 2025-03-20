# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.partitioning.disko;

  postBootCmds = pkgs.writeShellApplication {
    name = "postBootScript";
    runtimeInputs = with pkgs; [
      btrfs-progs
      gnugrep
      gawk
      util-linux
      gptfdisk
      parted
    ];
    text = ''
      set -xeuo pipefail

      # Check which physical disk is used by btrfs
      # TODO use a label in case there are more than one btrfs partitions/subvolumes
      BTRFS_LOCATION=$(btrfs filesystem show | grep '/dev' | awk '{print $8}')

      # Get the actual device path
      P_DEVPATH=$(readlink -f "$BTRFS_LOCATION")

      # Extract the partition number using regex
      if [[ "$P_DEVPATH" =~ [0-9]+$ ]]; then
        PARTNUM=$(echo "$P_DEVPATH" | grep -o '[0-9]*$')
        PARENT_DISK=/dev/$(lsblk -no pkname "$P_DEVPATH")
      else
        echo "No partition number found in device path: $P_DEVPATH"
      fi

      # Fix GPT first
      sgdisk "$PARENT_DISK" -e

      # Call partprobe to update kernel's partitions
      partprobe

      # Extend the partition to use unallocated space
      parted -s -a opt "$PARENT_DISK" "resizepart $PARTNUM 100%"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
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
        description = "Extend the persistence partition";
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
