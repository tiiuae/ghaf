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
        /*
        microvm.devices = [
          {
            # GPIO passthrough uses a character device (/dev/vda). No need to specify?
          }
        ];
        */

        microvm.kernelParams = [
          "rootwait"
          # "root=/dev/vda"
          "console=ttyAMA0"
        ];
      }
    ];

    /* tmp note: further kernel settings for nvidia in:
    ../jetpack/nvidia-jetson-orin/virtualization/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/common/gpio-virt-common/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/host/gpio-virt-host/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/host/bpmp-virt-host/default.nix
    */
  };
}
