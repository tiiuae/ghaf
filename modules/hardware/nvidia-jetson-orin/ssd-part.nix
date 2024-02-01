# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{ lib, config, pkgs, system, ... }:
let
  cfg = config.ghaf.hardware.nvidia.orin.ssd;
    
  # WARNING -- DANGER - do not use this code before careful review
  # disk data may be destroyed

  # check if at least one of HOME or STORAGE already exists
  # (condition can be changed to [ <condition> != "2" ] )
  # failing mount of STORE or HOME is not critical
in
{
  options.ghaf.hardware.nvidia.orin.ssd.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
    	Enable partititioning and setup of SSD.
	Warning: Disk data may be lost!
    '';
  };

  config = lib.mkIf cfg.enable {
    fileSystems = {
      "/home" = {
        autoFormat = true;
        label = "HOME";
        # device = "/dev/disk/by-label/HOME";
        fsType = "ext4";
      };
      "/nix/store" = {
        autoFormat = true;
        label = "STORE";
        # device = "/dev/disk/by-label/STORE";
        fsType = "ext4";
      };
    };
    system.build = {
      enable = true;
      script = pkgs.writeScript "ssdPartScript" ''
        #!/bin/bash -e

	echo "Executing SSD partitioning script"

	# grep for SSD in /dev/disk/by-id
        # found SSD disk "should" be a link to /dev/nvme0n1

	unset ssd
	ssd=$(ls -X /dev/disk/by-id/*SSD* | head -1)
  	# ssd='/dev/nvme0n1'
	if [ "$ssd" ] && [ $(lsblk -o LABEL "{ssd" grep -e"^HOME$" -e"^STORAGE$" | wc -l) == "0" ]
	then
		# calculate partition sizes
		sectors=$(blockdev --getsz "$ssd")
		# assuming 2024 Master Boot Record sectors.
		let sect_25=($sectors-2048)/4 # ~25% of disk

	        echo "Debug Alert -- Partitioning of the SSD would have been done on disk $ssd"; exit;

		# Apply fdisk commands
		fdisk_cmd="g\nn\n\n1\n$sect_25\nn\n\n2\nw\n"
		fdisk "$ssd" <<< "$fdisk_cmd"

		# label new partitions
		e2label "$ssd""p1" HOME
		e2label "$ssd""p2" STORE

		# formatting not needed with Nix fileSystems.autoFormat 
	fi
    '';
    };
  };
}
