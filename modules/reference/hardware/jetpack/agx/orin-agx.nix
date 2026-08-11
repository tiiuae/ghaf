# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{
  config,
  lib,
  pkgs,
  ...
}:
{
  _file = ./orin-agx.nix;

  imports = [
    ../../../../common/services/hwinfo
    # Host keeps the real DCE R5 and loads dce-host-proxy so the guest drives
    # the panel through it. Shared by AGX and NX.
    ../nvidia-jetson-orin/virtualization/common/dce-virt-common/dce-probe-host.nix
  ];

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
        somType = "agx";
        agx.enableNetvmWlanPCIPassthrough = true;
        carrierBoard = "devkit";
        # AGX devkit boots rootfs from eMMC.
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
      # Split topology: compute gpu-vm plus display-only disp-vm.
      nvidia.passthroughs.gpu_vm.enable = true;
      nvidia.passthroughs.disp_vm.enable = true;

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
        # Hardware info guest support. Crosvm has no fw_cfg, so share the same
        # generated JSON read-only through virtiofs instead.
        ({ config, ... }: {
          imports = [ ../../../../common/services/hwinfo ];
          ghaf.services.hwinfo-guest = {
            enable = true;
            filePath = lib.mkIf (config.microvm.hypervisor == "crosvm") "/run/ghaf-hwinfo/hwinfo.json";
          };
          microvm.shares = lib.optionals (config.microvm.hypervisor == "crosvm") [
            {
              tag = "ghaf-hwinfo";
              source = "/var/lib/ghaf-hwinfo";
              mountPoint = "/run/ghaf-hwinfo";
              proto = "virtiofs";
              readOnly = true;
            }
          ];
        })
        # QEMU arguments to pass hardware info via fw_cfg
        ({ config, ... }: {
          microvm.qemu.extraArgs = lib.mkIf (config.microvm.hypervisor == "qemu") [
            "-fw_cfg"
            "name=opt/com.ghaf.hwinfo,file=/var/lib/ghaf-hwinfo/hwinfo.json"
          ];
        })
        ../../../personalize
        # Developer SSH access is a DEBUG-build affordance: this option defaults to
        # the ghaf developer key list and grants each of those keys a shell.
        { ghaf.reference.personalize.keys.enable = config.ghaf.profiles.debug.enable; }
      ];
    };
  };

  # To enable or disable wireless
  networking.wireless.enable = true;

  # Both fw_cfg and the Crosvm virtiofs share consume this host-generated file.
  systemd.services."microvm@net-vm" = {
    wants = [ "ghaf-hwinfo-generate.service" ];
    after = [ "ghaf-hwinfo-generate.service" ];
  };

  hardware = {
    # Device Tree
    deviceTree.name = "tegra234-p3737-0000+p3701-0000-nv.dtb";
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
