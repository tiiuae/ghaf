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
  gpioGuestDtbName = ''tegra234-gpio-guest-passthrough.dtb'';

  gpioGuestDts = ./gpio_pt_guest_overlay.dtso;

  copyDtbTmp = pkgs.stdenv.mkDerivation {
    name = "copy-dtb-file";
    buildInputs = [ pkgs.coreutils-full gpioGuestOrigName gpioGuestDtbName ];
    buildPhase = ''cp -v ${gpioGuestOrigName} ${gpioGuestDtbName}; pwd;'';
    pwd = builtins.getEnv "PWD";
    outputs = [ gpioGuestDtbName ];
  };
  copyDtb = builtins.trace "Evaluating copyDtb = ${copyDtbTmp} derivation in gpio-vm" copyDtbTmp;

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
        microvm = builtins.trace "Building ghaf.virtualization.microvm.gpiovm.extraModules.microvm"
        {
          /*
          devices = [
            {
              # GPIO passthrough uses a character device (/dev/vda). No need to specify?
            }
          ];
          */

          qemu.serialConsole = false;
          graphics.enable= false;

          kernelParams = builtins.trace "Evaluating kernelParams for gpio-vm" [
            "rootwait"
            "root=/dev/vda"
            "console=null"
          ];
          # "console=ttyAMA0"     # removed gpio-vm cannot open console since it does not have uarta passthough
        };

        hardware.deviceTree = builtins.trace "Evaluating hardware.deviceTree for gpio-vm" {
          enable = true;
          #name = builtins.trace "Setting hardware.deviceTree.name to ${gpioGuestDtbName}" gpioGuestDtbName;
          name = builtins.trace "Setting hardware.deviceTree.name to predefined constant string" ''tegra234-gpio-guest-passthrough.dtb'';
          overlays = builtins.trace "Setting hardware.deviceTree.overlays" [
            {
              name = "gpio_pt_guest_overlay";
              dtsFile = gpioGuestDts;
              # filter  = dtbFile;
              filter = gpioGuestDtbName;
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
