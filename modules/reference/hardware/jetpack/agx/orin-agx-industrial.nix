# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ pkgs, lib, ... }:
{
  _file = ./orin-agx-industrial.nix;

  imports = [ ../../../../common/services/hwinfo ];

  ghaf = {
    # Enable hardware info generation on host
    services.hwinfo = {
      enable = true;
      outputDir = "/var/lib/ghaf-hwinfo";
    };

    hardware = {
      nvidia.orin = {
        enable = true;
        kernelVersion = "upstream-6-6";
        somType = "agx-industrial";
        agx.enableNetvmWlanPCIPassthrough = true;
        carrierBoard = "devkit";
        # AGX industrial devkit boots rootfs from eMMC.
        flashScriptOverrides = {
          deviceDisk = "mmcblk0";
          deviceDiskEspPartition = "mmcblk0p1";
          deviceDiskRootfsPartition = "mmcblk0p2";
        };
      };

      # AGX has the on-SoC MGBE0 ethernet controller (Aquantia PHY on the
      # p3737 carrier); pass it through to net-vm. Orin NX has no MGBE0.
      nvidia.passthroughs.mgbe0_net_vm.enable = true;
      nvidia.passthroughs.gpu_vm.enable = true;

      # Net VM hardware-specific modules - use hardware.definition for composition model
      definition.netvm.extraModules = [
        {
          # The Nvidia Orin hardware dependent configuration is in
          # modules/reference/hardware/jetpack Please refer to that
          # section for hardware dependent netvm configuration.

          # Wireless Configuration. Orin AGX has WiFi enabled where Orin NX and
          # Orin AGX-industrial does not.

          # To enable or disable wireless
          networking.wireless.enable = lib.mkForce false;

        }
        # Hardware info guest support
        {
          imports = [ ../../../../common/services/hwinfo ];
          ghaf.services.hwinfo-guest.enable = true;
        }
        # Ensure hardware info is generated before net-vm starts
        {
          systemd.services."microvm@net-vm" = {
            wants = [ "ghaf-hwinfo-generate.service" ];
            after = [ "ghaf-hwinfo-generate.service" ];
          };
        }
        # QEMU arguments to pass hardware info via fw_cfg
        {
          microvm.qemu.extraArgs = [
            "-fw_cfg"
            "name=opt/com.ghaf.hwinfo,file=/var/lib/ghaf-hwinfo/hwinfo.json"
          ];
        }
        ../../../personalize
        (
          { lib, globalConfig, ... }:
          {
            # Dev-team SSH keys are a debug convenience; this hardware
            # definition applies to release variants too, so gate on the
            # variant carried by globalConfig.
            ghaf.reference.personalize.keys.enable = lib.mkDefault (globalConfig.debug.enable or false);
          }
        )
      ];
    };
  };

  # To enable or disable wireless
  networking.wireless.enable = lib.mkForce false;

  hardware = {
    # Device Tree
    deviceTree.name = "tegra234-p3737-0000+p3701-0008-nv.dtb";
    nvidia-jetpack = {
      enable = true;
      som = "orin-agx-industrial";
      carrierBoard = "devkit";
      modesetting.enable = true;
      flashScriptOverrides = {
        flashArgs = [
          "-r"
          "jetson-agx-orin-devkit-industrial"
          "mmcblk0p1"
        ];
      };
      firmware.uefi = {
        logo = "${pkgs.ghaf-artwork}/1600px-Ghaf_logo.svg";
      };
    };
  };
}
