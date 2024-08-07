# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0


# based on admin vm
{
  config,
  lib,
  ...
}: let
  configHost = config;
  vmName = "admin-vm";
  macAddress = "02:00:00:AD:01:01";
  isLoggingEnabled = config.ghaf.logging.client.enable;

  gpiovmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {
        inherit config lib vmName macAddress;
        internalIP = 10;
      })
      ({lib, ...}: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
          development = {
            # NOTE: SSH port also becomes accessible on the network interface
            #       that has been passed through to VM
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
          systemd = {
            enable = true;
            withName = "gpiovm-systemd";
            withNss = true;
            withResolved = true;
            withPolkit = true;
            withTimesyncd = true;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        networking = {
          firewall.allowedTCPPorts = lib.mkIf isLoggingEnabled [config.ghaf.logging.listener.port];
          firewall.allowedUDPPorts = [];
        };

        systemd.network = {
          enable = true;
          networks."10-ethint0" = {
            matchConfig.MACAddress = macAddress;
            linkConfig.ActivationPolicy = "always-up";
          };
        };

        microvm = {
          optimize.enable = true;
          hypervisor = "qemu";
        };
        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.gpiovm;
in {
  options.ghaf.virtualization.microvm.gpiovm = {
    enable = lib.mkEnableOption "gpiovm";

    /* extraModules are declared in ./modules/jetpack/nvidia-jetson-orin/virtualization/passthrough/gpio-vm/
     * TODO make a list concatenation */
    extraModules = builtins.trace "GpioVM: mkOption ghaf.virtualization.microvm.gpiovm.extraModules"
      lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        gpiovm's NixOS configuration.
      '';
      default = [];
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
    };
  };
}
