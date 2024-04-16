# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ 
  pkgs,
  lib,
  config,
  ...
}: let
  #kernel = options.ghaf.host.kernel;
  kernel = config.ghaf.host.kernel;

  # guestdts specifies specifically gpiovm's device tree
  gpioGuestPath = ./arch/arm64/boot/dts/nvidia;
  gpioGuestOrigName = ''tegra234-p3701-0000-p3737-0000.dtb'';
  gpioGuestOrig = gpioGuestPath + gpioGuestOrigName;
  # gpioGuestDtbName = "tegra234-p3701-0000-gpio-passthrough.dtb";
  # gpioGuestDtb = gpioGuestPath + gpioGuestDtbName;

  gpioGuestDts = ./gpio_pt_guest_overlay.dtso;

  # tmp debug fix -- fix bypasses copy which is a bug
  gpioGuestDtb = gpioGuestOrig;  # this line bypasses copy of DT blob -- for debug reasons
  gpioGuestDtbName = gpioGuestOrigName;

  /*
  gpioGuestCopyDtb = runCommand "copy dtb file for guest" {}
    ''
      cp ${gpioGuestOrig} ${gpioGuestDtb}
    '';
  */

  # TODO we do not have a proper ./gpio_pt_guest_overlay.dtso yet -- using host's for build debugging

  /*
  pkgs.stdenv.mkDerivation {
    inherit gpioGuestOrig gpioGuestDtb; # Ensure these variables are available in the builder script
    name = "copy-dtb";
    buildCommand = pkgs.writeText "copy-dtb.sh" ''
      cp ${gpioGuestOrig} ${gpioGuestDtb}
    '';
  }
  */

  # pkgs.runCommand "copy-dtb" {} "coreutils-full./bin/cp gpioGuestOrig gpioGuestDtb"

  /*
  pkgs.runCommand "copy-dtb" {} ''
    cp ${gpioGuestOrig} ${gpioGuestDtb}
  '';
  */

  /*
  # Creating a new DTB file
  pkgs.buildPackages.utils.copyFile {
    inputFile = gpioGuestOrig;
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
          "console=ttyAMA0"
        ];

        hardware.deviceTree = {
          enable = true;
          name = gpioGuestDtbName;
          overlays = [
            {
              name = "gpio_pt_guest_overlay";
              # TODO we do not have ./gpio_pt_guest_overlay.dtso yet
              dtsFile = gpioGuestDts;
              filter  = gpioGuestDtbName;
            }
          ];
        };
        /*
        buildPhase = ''
          # Copy the dtb file
          # TODO: Adjust the command to copy the dtb file as needed
          # cp ${gpioGuestOrig} ${gpioGuestDtb}
        '';
        installPhase = ''
          pwd
        '';
        */
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
