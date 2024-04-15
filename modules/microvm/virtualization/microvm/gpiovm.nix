# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
} : with pkgs; let
  configHost = config;
  vmName = "gpio-vm";

  /*
  # bugtest variable
  # absoluteFilePath = "${builtins.currentSystem}/source/nixos-modules/host/";
  # absoluteFilePath = getBuildDir;

  # guestdts specifies specifically gpiovm's device tree
  gpioGuestSrcName = "tegra234-p3701-0000-p3737-0000.dtb";
  gpioGuestDtbName = "tegra234-p3701-0000-gpio-passthrough.dtb";
  gpioGuestPath = "./arch/arm64/boot/dts/nvidia/";
  gpioGuestSrc = gpioGuestPath + gpioGuestSrcName;
  # gpioGuestDtb = gpioGuestPath + gpioGuestDtbName;
  # tmp debug fix
  gpioGuestDtb = gpioGuestSrc;  # this line bypasses copy of DT blob -- for debug reasons

  # TODO we do not have ./gpio_pt_guest_overlay.dtso yet
  dtsoGpioFile = "./gpio_pt_host_overlay.dtso";
  */
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

  gpiovmBaseConfiguration = {
    imports = [
      ({lib, ...}: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          development = {
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
          systemd = {
            enable = true;
            withName = "gpiovm-systemd";
            withPolkit = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        microvm.hypervisor = "qemu";
        # microvm.hypervisor.extraargs = ["--dtb", dtbfilepath];

        /*
        services.xxx = {
          # we define a servce in extraModules variable below with import ./gpio-test.nix 
        }
        */
        microvm = {
          optimize.enable = true;
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

          /* 
          qemu.extraargs = [
              "--dtb" gpioGuestDtb
          ];
          */
        };

        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.gpiovm;
in {
  options.ghaf.virtualization.microvm.gpiovm = {
    enable = lib.mkEnableOption "gpio-vm";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        gpio-vm's NixOS configuration.
      '';
      # A service that runs a script to test gpio pins
      default = [ import ./gpio-test.nix { pkgs = pkgs; } ];
    };
  };

  #pkgs.runCommand "copy-dtb" {} "pkgs.coreutils-full./bin/cp gpioGuestSrc gpioGuestDtb"
  # runCommand "copy-dtb" {} "coreutils-full./bin/cp gpioGuestSrc gpioGuestDtb"

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        gpiovmBaseConfiguration
        // {
          imports =
            gpiovmBaseConfiguration.imports
            ++ cfg.extraModules;
          /*
          hardware.deviceTree = {
            enable = true;
            name = gpioGuestDstName;
            overlays = [
              {
                name = "gpio_pt_guest_overlay";
                # TODO we do not have ./gpio_pt_guest_overlay.dtso yet
                # dtsFile = builtins.toPath gpioGuestDtb;
                filter = gpioGuestDtbName;
              }
            ];
          };
          */
        };
      # specialArgs = {inherit lib;};

    };

    /*
    # Creating a new DTB file
    # pkgs.buildPackages.utils.copyFile {
    # pkgs.stdenv.lib.callPackage {
    pkgs.stdenv.lib.copyFile {
      inputFile = gpioGuestSrc;
      outputFile = gpioGuestDtb;
      override = true;
    };
    */
  };
}
