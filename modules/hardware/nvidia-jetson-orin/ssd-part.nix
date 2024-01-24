# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin;
  # cfg = config.ghaf.hardware.nvidia.orin.ssd;
    
  # TODO: create and label SSD partitions if they do not exist
  fileSystems = {
         "/home" = {
           autoFormat = true;
           label = "HOME";
           # device = "/dev/disk/by-label/HOME";
           fsType = "ext4";
        };
        "/nix/store/" = {
           autoFormat = true;
           label = "STORE";
           # device = "/dev/disk/by-label/STORE";
           fsType = "ext4";
        };
  };
  # TODO executed conditinally in nix (if partitions do not exist)
  # SSD disk "should" be /dev/nvme0n1
  # WARNING -- DANGER - do not use this code before careful review
  # disk data may be destroyed
  ssdPartCmd = ''
	# check if at least one of HOME or STORAGE already exist (condition can be changed to [ <condition> != "2" ] )
	# failing mount of STORE or HOME is not critical

  	ssd='/dev/nvme0n1' # we could also grep for SSD in /dev/disk/by-id
 	if [ $(lsblk -o LABEL "{ssd" grep -e"^HOME$" -e"^STORAGE$" | wc -l) == "0" ]
	then
		# calculate partition sizes
		sectors=$(blockdev --getsz "$ssd")
		# assuming 2024 Master Boot Record sectors.
		let sect_25=($sectors-2048)/4 # ~25% of disk

		# Apply fdisk commands
		fdisk_cmd="g\nn\n\n1\n$sect_25\nn\n\n2\nw\n"
		fdisk "$ssd" <<< "$fdisk_cmd"

		# label new partitions
		e2label "$ssdp1" HOME
		e2label "$ssdp2" STORE

		# formatting not needed with Nix fileSystems.autoFormat 
	fi
  '';
in
  with lib; {
    config = mkIf cfg.enable {
    };
}
