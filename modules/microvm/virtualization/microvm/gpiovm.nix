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
  # guestdts specifies specifically gpiovm's device tree
  # todo synchronise with (move to) definition in ../host/gpio-virt-host/default.nix
  dtbSrc = "tegra234-p3701-0000-p3737-0000";
  dtName = "tegra234-p3701-gpio-guestvm";
  # TODO we do not have ./gpio_pt_guest_overlay.dtso yet
  dtsFile = ../../..jetpack/nvidia-jetson-orin/virtualization/host/gpio-virt-host/gpio_pt_host_overlay.dtso;
  gpioGuestOutput = dtName + ".dtb";
  gpioGuestDtb = new File gpioPtGuestOutput {};

  # Creating a new DTB file named gpio_pt_guest.dtb
  nixpkgs.buildInputs.utils.copy-file {
    inputFile = "${sourcePath}/${name}";
    outputFile = gpioPtGuestOutput;
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
        /*
        options.hardware.devicetree = {
          enable = true;
          name = dtName;
          overlays = [
            {
              name = "gpio_pt_guest_overlay";
              # TODO we do not have ./gpio_pt_guest_overlay.dtso yet
              dtsFile = dtsFile;
              filter = gpioPtGuestOutput;
            }
          ];
        };
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

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        gpiovmBaseConfiguration
        // {
          imports =
            gpiovmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
      # specialArgs = {inherit lib;};
    };
  };
}
