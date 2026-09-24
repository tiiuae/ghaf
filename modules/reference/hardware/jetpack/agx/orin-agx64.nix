# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ config, pkgs, ... }:
{
  _file = ./orin-agx64.nix;

  ghaf = {
    hardware = {
      nvidia.orin = {
        enable = true;
        kernelVersion = "upstream-6-6";
        somType = "agx64";
        agx.enableNetvmWlanPCIPassthrough = true;
        carrierBoard = "devkit";
        # AGX64 devkit boots rootfs from eMMC.
        flashScriptOverrides = {
          deviceDisk = "mmcblk0";
          deviceDiskEspPartition = "mmcblk0p1";
          deviceDiskRootfsPartition = "mmcblk0p2";
        };
      };

      # AGX has the on-SoC MGBE0 ethernet controller (Aquantia PHY on the
      # p3737 carrier); pass it through to net-vm. Orin NX has no MGBE0.
      nvidia.passthroughs.mgbe0_net_vm.enable = true;

      # Reserve space for the desktop closure on 64 GiB eMMC.
      nvidia.orin.flashScriptOverrides.appPartitionSizeBytes = 34359738368;
      # Net VM hardware-specific modules - use hardware.definition for composition model
      definition.netvm.extraModules = [
        {
          # The Nvidia Orin hardware dependent configuration is in
          # modules/reference/hardware/jetpack Please refer to that
          # section for hardware dependent netvm configuration.

          # Wireless Configuration. Orin AGX has WiFi enabled where Orin NX does
          # not.

          # To enable or disable wireless
          networking.wireless.enable = true;

          # For WLAN firmwares
          hardware = {
            enableRedistributableFirmware = true;
            wirelessRegulatoryDatabase = true;
          };

        }
        ../../../personalize
        # Developer SSH access is a DEBUG-build affordance: this option defaults to
        # the ghaf developer key list and grants each of those keys a shell.
        { ghaf.reference.personalize.keys.enable = config.ghaf.profiles.debug.enable; }
      ];
    };
  };

  # To enable or disable wireless
  networking.wireless.enable = true;

  hardware = {
    # Device Tree
    deviceTree.name = "tegra234-p3737-0000+p3701-0005-nv.dtb";
    nvidia-jetpack = {
      enable = true;
      som = "orin-agx";
      carrierBoard = "devkit";
      modesetting.enable = true;
      flashScriptOverrides = {
        flashArgs = [
          "-r"
          "jetson-agx-orin-devkit"
          "mmcblk0p1"
        ];
      };
      firmware.uefi = {
        logo = "${pkgs.ghaf-artwork}/1600px-Ghaf_logo.svg";
      };
    };
  };
}
