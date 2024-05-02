# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ 
  pkgs,
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

    ghaf.virtualization.microvm.gpiovm.extraModules = [
      {
        microvm = 
        {
          /*
          devices = [
            {
              # GPIO passthrough uses a character device (/dev/vda). No need to specify?
            }
          ];
          */

          # Make sure that Gpio-VM runs after the dependency service are enabled
          # systemd.services."microvm@gpio-vm".after = ["gpio-dependency.service"];

          kernelParams = builtins.trace "GpioVM: Evaluating microvm.kernelParams (qemu -append) for gpio-vm" [
            "rootwait"
          # "root=/dev/vda"
            # gpio-vm cannot open AMA0 reserved for passthrough console
            # since it does not have uarta passthough
            # "console=ttyAMA0 console=ttyS0"
            # "console=tty10"
          ];
        };

        /* no overlay when using dtb patch
         * Note: use qemu.extraArgs for -dtb
        hardware.deviceTree = builtins.trace "GpioVM: Evaluating hardware.deviceTree for gpio-vm" {
          enable = true;
          name = builtins.trace "GpioVM: Setting hardware.deviceTree.name" gpioGuestDtbName;
          # name = builtins.trace "GpioVM: Debugging with ${gpioGuestOrigName}" gpioGuestOrigName;
          overlays = builtins.trace "GpioVM: Setting hardware.deviceTree.overlays" [
            {
              name = "gpio_pt_guest_overlay";
              dtsFile = gpioGuestDts;
              # filter  = dtbFile;
              filter = gpioGuestDtbName;
            }
          ];
        };
        */
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
