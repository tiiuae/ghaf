# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.virtualization.host.gpio;
in {
  options.ghaf.hardware.nvidia.virtualization.host.gpio.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable virtualization host support for NVIDIA Orin

      This option is an implementation level detail and is toggled automatically
      by modules that need it. Manually enabling this option is not recommended in
      release builds.
    '';
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization.enable = true;

    # in practice this configures both host and guest kernel becaue we use only one kernel in the whole system
    boot.kernelPatches = [
      {
        name = "GPIO virtualization host kernel configuration";
        patch = null;
        extraStructuredConfig = {
          VFIO_PLATFORM = lib.kernel.yes;
          TEGRA_GPIO_HOST_PROXY = lib.kernel.yes;
          TEGRA_GPIO_GUEST_PROXY = lib.kernel.yes;
        };
      }
    ];

    hardware.deviceTree = {
      # Enable hardware.deviceTree for handle host dtb overlays
      enable = true;
      # name = builtin.trace "Debug dtb: tegra234-p3701-0000-p3737-0000.dtb" "tegra234-p3701-0000-p3737-0000.dtb";
      # name = pkgs.builtin.trace "Debug dtb: tegra234-p3701-host-passthrough.dtb" "tegra234-p3701-host-passthrough.dtb";
      name = "tegra234-p3701-host-passthrough.dtb";

      # using overlay file:
      overlays = [
        {
          name = "gpio_pt_host_overlay";
          dtsFile = ./gpio_pt_host_overlay.dtso;

          # Apply overlay only to host passthrough device tree
          # filter = builtin.trace "Debug dtb: tegra234-p3701-0000-p3737-0000.dtb" "tegra234-p3701-0000-p3737-0000.dtb";
          # filter = pkgs.builtin.trace "Debug dtb: tegra234-p3701-host-passthrough.dtb" "tegra234-p3701-host-passthrough.dtb";
          filter = "tegra234-p3701-host-passthrough.dtb";
        }
      ];
    };
  };
}
