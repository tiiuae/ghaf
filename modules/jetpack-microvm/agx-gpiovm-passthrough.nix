# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  # bugtest variable
  # absoluteFilePath = "${builtins.currentSystem}/source/nixos-modules/host/";
  # absoluteFilePath = getBuildDir;

  # guestdts specifies specifically gpiovm's device tree
  gpioGuestPath = "./arch/arm64/boot/dts/nvidia/";
  gpioGuestSrcName = "tegra234-p3701-0000-p3737-0000.dtb";
  gpioGuestSrc = gpioGuestPath + gpioGuestSrcName;
  # gpioGuestDtbName = "tegra234-p3701-0000-gpio-passthrough.dtb";
  # gpioGuestDtb = gpioGuestPath + gpioGuestDtbName;
  # tmp debug fix -- fix bypasses copy which is a bug
  gpioGuestDtb = gpioGuestSrc;  # this line bypasses copy of DT blob -- for debug reasons
  gpioGuestDtbName = gpioGuestSrcName;

  # TODO we do not have a proper ./gpio_pt_guest_overlay.dtso yet -- using host's for build debugging
  gpioGuestDtso = ./gpio_pt_host_overlay.dtso;

  /*
  pkgs.stdenv.mkDerivation {
    inherit gpioGuestSrc gpioGuestDtb; # Ensure these variables are available in the builder script
    name = "copy-dtb";
    buildCommand = pkgs.writeText "copy-dtb.sh" ''
      cp ${gpioGuestSrc} ${gpioGuestDtb}
    '';
  }
  */

  # runCommand "copy-dtb" {} "coreutils-full./bin/cp gpioGuestSrc gpioGuestDtb"

  /*
  pkgs.runCommand "copy-dtb" {} ''
    cp ${gpioGuestSrc} ${gpioGuestDtb}
  '';
  */

  /*
  # Creating a new DTB file
  pkgs.buildPackages.utils.copyFile {
    inputFile = gpioGuestSrc;
    outputFile = gpioGuestDtb;
    override = true;
  };
  */

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

        hardware.deviceTree = {
          enable = true;
          name = gpioGuestDtbName;
          overlays = [
            {
              name = "gpio_pt_guest_overlay";
              # TODO we do not have ./gpio_pt_guest_overlay.dtso yet
              dtsFile = gpioGuestDtso;
              filter  = gpioGuestDtbName;
            }
          ];
        };
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
