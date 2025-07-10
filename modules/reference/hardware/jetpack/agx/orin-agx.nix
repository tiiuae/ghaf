# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{
  ghaf.hardware.nvidia.orin = {
    enable = true;
    kernelVersion = "upstream-6-6";
    somType = "agx";
    agx.enableNetvmWlanPCIPassthrough = true;
    carrierBoard = "devkit";
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
      kernel.version = "upstream-6-6";
      flashScriptOverrides = {
        flashArgs = [
          "-r"
          "jetson-agx-orin-devkit"
          "mmcblk0p1"
        ];
      };
      firmware.uefi = {
        logo = ../../../../../../docs/src/img/1600px-Ghaf_logo.svg;
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

  ghaf.profiles.orin.netvmExtraModules = [
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

      services.dnsmasq.settings.dhcp-option = [
        "option:router,192.168.100.1" # set net-vm as a default gw
        "option:dns-server,192.168.100.1"
      ];
    }
  ];
}
