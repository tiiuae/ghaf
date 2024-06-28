# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "admin-vm";
  macAddress = "02:00:00:AD:01:01";
  isLoggingEnabled = config.ghaf.logging.client.enable;

  adminvmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {
        inherit config lib vmName macAddress;
        internalIP = 10;
      })
      # We need to proccess logs received and then forward to loki service
      (import ../../../common/log/logs-process.nix {inherit config lib pkgs;})
      (import ../../../common/log/loki.nix {inherit config lib pkgs;})
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
            withName = "adminvm-systemd";
            withPolkit = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        networking = {
          firewall.allowedTCPPorts = [];
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
          hypervisor = "cloud-hypervisor";
          shares =
            [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ]
            ++ lib.optionals isLoggingEnabled [
              {
                # Creating a persistent log-store which is mapped on ghaf-host
                tag = "log-store";
                source = "/var/lib/loki";
                mountPoint = "/var/lib/loki";
                proto = "virtiofs";
              }
            ];

          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
        };
        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.adminvm;
in {
  options.ghaf.virtualization.microvm.adminvm = {
    enable = lib.mkEnableOption "AdminVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        AdminVM's NixOS configuration.
      '';
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        adminvmBaseConfiguration
        // {
          imports =
            adminvmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
    };
  };
}
