# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ 
  pkgs,
  lib,
  config,
  ...
}: let
  # gpioDtbPath = ./arch/arm64/boot/dts/nvidia;
  gpioGuestOrigName = ''tegra234-p3701-0000-p3737-0000.dtb'';
  gpioGuestDtbName = "tegra234-p3701-0000-gpio-passthrough.dtb";

  gpioGuestDts = ./gpio_pt_guest_overlay.dtso;

  copyDtb = pkgs.stdenv.mkDerivation {
    name = "copy-dtb-file";
    buildInputs = [ pkgs.coreutils-full.cp gpioGuestOrigName gpioGuestDtbName ];
    buildPhase = ''cp ${gpioGuestOrigName} ${gpioGuestDtbName}'';
    outputs = [ gpioGuestDtbName ];
  };

  # dtbFile specifies specifically gpiovm's device tree
  dtbFileList = copyDtb.outputs;
  dtbFile = builtins.elemAt dtbFileList 0;

  cfg = config.ghaf.hardware.nvidia.orin.agx;
in {
  options.ghaf.hardware.nvidia.orin.agx.enableGPIOPassthrough =
    lib.mkEnableOption
    "GPIO passthrough to VM";

  config = lib.mkIf cfg.enableGPIOPassthrough {
    # Orin AGX GPIO Passthrough

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
          "root=/dev/vda"
        ];
        # "console=ttyAMA0"     # removed gpio-vm cannot open console since it does not have uarta passthough

        hardware.deviceTree = {
          enable = true;
          name = gpioGuestDtbName;
          overlays = [
            {
              name = "gpio_pt_guest_overlay";
              dtsFile = gpioGuestDts;
              filter  = dtbFile;
            }
          ];
        };
      }
    ];
 
    /*
    kernel = {
      inherit kernel;
      #phases = _ old.phases + { name='install'; func = ''echo "do copy here"'' };
    };
    */

    /* tmp note: further kernel settings for nvidia in:
    ../jetpack/nvidia-jetson-orin/virtualization/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/common/gpio-virt-common/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/host/gpio-virt-host/default.nix
    ../jetpack/nvidia-jetson-orin/virtualization/host/bpmp-virt-host/default.nix
    */
  };
}
