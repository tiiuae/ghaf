# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{
  ghaf.hardware.nvidia.orin = {
    enable = true;
    kernelVersion = "upstream-6-6";
    somType = "nx";
    nx.enableNetvmEthernetPCIPassthrough = true;
    carrierBoard = "xavierNXdevkit";
  };
  hardware = {
    # Sake of clarity: Jetson 35.4 and IO BASE B carrier board
    # uses "tegra234-p3767-0000-p3509-a02.dtb"-device tree.
    # p3509-a02 == IO BASE B carrier board
    # p3767-0000 == Orin NX SOM
    # p3768-0000 == Official NVIDIA's carrier board
    # Upstream kernel has only official carrier board device tree,
    # but it works with IO BASE B carrier board with minor
    # modifications.
    deviceTree.name = "tegra234-p3768-0000+p3767-0000-nv.dtb";
    nvidia-jetpack = {
      enable = true;
      som = "orin-nx";
      carrierBoard = "xavierNXdevkit";
      modesetting.enable = true;
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
    }
    ../../../personalize
    { ghaf.reference.personalize.keys.enable = true; }
  ];
}
