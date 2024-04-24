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

  gpioGuestDtbName = ./qemu-gpio-guestvm.dtb;
  tmp_rootfs = ./tegra_rootfs.qcow2;

  gpiovmBaseConfiguration = {
    imports = [
      ({lib, ...}: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          /*
          development = {
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
          */
          systemd = {
            enable = true;
            withName = "gpiovm-systemd";
            withPolkit = true;
            # withDebug = configHost.ghaf.profiles.debug.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        /*
        services.xxx = {
          # we define a servce in extraModules variable below with import ./gpio-test.nix 
        }
        */
        microvm = {
          optimize.enable = true;
          hypervisor = "qemu";

          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          # writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

          graphics.enable= false;
          qemu = {
            machine =
              {
                # Use the same machine type as the host
                x86_64-linux = "q35";
                aarch64-linux ="virt";
              }
              .${configHost.nixpkgs.hostPlatform.system};
            serialConsole = true;
            extraArgs = [
              # "-dtb ${gpioGuestDtbName}"
              # "-monitor chardev=mon0,mode=readline"
              # "-no-reboot"
            ];
            /*
            extraArgs = builtins.trace "Evaluating qemu.extraArgs for gpio-vm" [
              # Add custom dtb to Gpio-VM with VDA
              "-dtb ${gpioGuestDtbName}"
              "-monitor chardev=mon0,mode=readline"
              "-no-reboot"
              # "-drive file=${tmp_rootfs},if=virtio,format=qcow2"
              # -nographic \
              # -machine virt,accel=kvm \
              # -cpu host \
              # -m 4G \
              # -smp 2 \
              # -kernel ${kernel} \
            ];
            */
          };
        };

        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.gpiovm;
in {
  options.ghaf.virtualization.microvm.gpiovm = {
    enable = lib.mkEnableOption "GpioVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        GpioVM's NixOS configuration.
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
