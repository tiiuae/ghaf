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
    nixpkgs.overlays = [(import ./overlays/qemu)];

    # ghaf.hardware.nvidia.virtualization.enable = true;

    boot.kernelPatches = [
      /* we use overlays not patches for DT
      {
        name = "Gpio virtualisation host proxy device tree"
        patch = ./patches/0007-gpio-host-gpio-dts.patch
      }
      {
        name = "Gpio virtualization host uarta device tree";
        patch = ./patches/0002-gpio-host-uarta-dts.patch;
      }
      */
      {
        name = "GPIO virtualization host kernel configuration";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          VFIO_PLATFORM = yes;
          TEGRA_GPIO_HOST_PROXY = yes;
        };
      }
    ];

    # this differes from bpmp implementation in that DT is overlayed here
    hardware.deviceTree = {
      # Enable hardware.deviceTree for handle host dtb overlays
      enable = true;
      # name = "tegra234-p3701-0000-p3737-0000.dtb";
      name = "tegra234-p3701-host-passthrough.dtb";

      # using overlay file:
      overlays = [
        {
          name = "gpio_pt_host_overlay";
          dtsFile = ./gpio_pt_host_overlay.dtso;

          # Apply overlay only to host passthrough device tree
          # filter = "tegra234-p3701-0000-p3737-0000.dtb";
          # filter = "tegra234-p3701-host-passthrough.dtb";
        }
      ];
    };

    # TODO: Consider if these are really needed, maybe add only in debug builds?
    environment.systemPackages = with pkgs; [
      qemu
      dtc
    ];
  };
}
