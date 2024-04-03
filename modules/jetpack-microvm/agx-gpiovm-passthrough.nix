# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin.agx;
in {
  options.ghaf.hardware.nvidia.orin.agx.enableGPIOPassthrough =
    lib.mkEnableOption
    "GPIO passthrough to VM";
  config = lib.mkIf cfg.enableGPIOPassthrough {
    # Orin AGX GPIO Passthrough
    # Debug statement to log a message

    ghaf.virtualization.microvm.gpiovm.extraModules = [
      {
        microvm.devices = [
          {
            # GPIO passthrough uses a character device (/dev/vda). No need to specify?
          }
        ];
        microvm.kernelParams = [
          "rootwait"
          "root=/dev/vda"
          "console=ttyAMA0"
        ];
      }
    ];
    # No need to set host kernel boot params here
    boot.kernelParams = [
      "iommu=pt"
      "vfio.enable_unsafe_noiommu_mode=0"
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
      "vfio_platform.reset_required=0"
    ];

    # No need to set host device tree here ???
    /*
    hardware.deviceTree = {
      # Enable hardware.deviceTree for handle host dtb overlays
      enable = true;
      # name = "tegra234-p3701-0000-p3737-0000.dtb";
      # name = "tegra234-p3701-host-passthrough.dtb";

      # using overlay file:
      overlays = [
        {
          name = "gpio_pt_host_overlay";
          dtsFile = ./gpio_pt_host_overlay.dtso;

          # Apply overlay only to host passthrough device tree
          # filter = "tegra234-gpio-host-proxy.dtb";
          # filter = "tegra234-p3701-0000-p3737-0000.dtb";
          filter = "tegra234-p3701-host-passthrough.dtb";
        }
      ];
    };
    */
  };
}
