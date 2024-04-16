# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "log-vm";
  macAddress = "02:00:00:01:01:02";
  logvmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {inherit vmName macAddress;})
      ({lib, ...}: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          development = {
            # NOTE: SSH port also becomes accessible on the network interface
            #       that has been passed through to NetVM
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
          systemd = {
            enable = true;
            withName = "logvm-systemd";
            withPolkit = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        networking = {
          firewall.allowedTCPPorts = [19532];
        };

        environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [];

        systemd.network = {
          enable = true;
          networks."10-ethint0" = {
            matchConfig.MACAddress = macAddress;
            addresses = [
              {
                addressConfig.Address = "192.168.100.66/24";
              }
              {
                # IP-address for debugging subnet
                addressConfig.Address = "192.168.101.66/24";
              }
            ];
            linkConfig.ActivationPolicy = "always-up";
          };
        };

        users.users.systemd-journal-remote = {
          isSystemUser = true;
          group = "systemd-journal";
        };

        systemd.tmpfiles.rules = [ "d /var/log/journal/remote 755 systemd-journal-remote systemd-journal" ];

        systemd.services.systemd-journal-remote = {
          enable = true;
        };

        microvm = {
          optimize.enable = true;
          hypervisor = "cloud-hypervisor";
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
          ];
          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
        };

        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.logvm;
in {
  options.ghaf.virtualization.microvm.logvm = {
    enable = lib.mkEnableOption "LogVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        LogVM's NixOS configuration.
      '';
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        logvmBaseConfiguration
        // {
          imports =
            logvmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
    };
  };
}
