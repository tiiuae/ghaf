# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ pkgs, ... }:
{
  _file = ./orin-agx.nix;

  imports = [
    ../../../../common/services/hwinfo
    # DCE display-proxy HOST integration (AGX only). Keeps gpu_vm
    # enabled, runs the host headless, force-loads tegra-dce so the host owns
    # the real DCE R5, and builds + loads the dce-host-proxy .ko (with an
    # injected nvidia,dce-host-proxy DT node) so the guest can drive the panel
    # through the host-owned DCE. AGX-only on purpose -- do not hoist into a
    # shared orin.nix.
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
      # gpu_vm is the compute capability (keeps host1x/gpu/media, drops
      # display, releases scanout for disp-vm); paired with disp_vm.enable
      # below (two-VM build).
      nvidia.passthroughs.gpu_vm.enable = true;
      # Display-only microvm for the two-VM build (branch-only). Owns only
      # scanout_p/disp_caps_pt/disp_chan_pt, disjoint from gpu_vm above.
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
        { ghaf.reference.personalize.keys.enable = true; }
      ];
    };
  };

  # To enable or disable wireless
  networking.wireless.enable = true;

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
