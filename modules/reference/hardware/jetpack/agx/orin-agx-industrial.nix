# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ pkgs, lib, ... }:
{
  imports = [ ../../../../common/services/hwinfo ];

  # Enable hardware info generation on host
  ghaf.services.hwinfo = {
    enable = true;
    outputDir = "/var/lib/ghaf-hwinfo";
  };

  ghaf.hardware.nvidia.orin = {
    enable = true;
    kernelVersion = "upstream-6-6";
    somType = "agx-industrial";
    agx.enableNetvmWlanPCIPassthrough = true;
    carrierBoard = "devkit";
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
        edk2NvidiaPatches = [
          # This effectively disables EFI FB Simple Framebuffer, which does
          # not work properly but causes kernel panic during the boot if the
          # HDMI cable is connected during boot time.
          #
          # The patch reverts back to old behavior, which is to always reset
          # the display when exiting UEFI, instead of doing handoff, when
          # means not to reset anything.
          # ./edk2-nvidia-always-reset-display.patch
        ];
      };
    };
  };

  # Net VM hardware-specific modules - use hardware.definition for composition model
  ghaf.hardware.definition.netvm.extraModules = [
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
    { ghaf.reference.personalize.keys.enable = true; }
  ];
}
