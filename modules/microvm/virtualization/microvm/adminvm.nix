# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{ config, lib, ... }:
let
  configHost = config;
  vmName = "admin-vm";
  macAddress = "02:00:00:AD:01:01";
  isLoggingEnabled = config.ghaf.logging.client.enable;

  adminvmBaseConfiguration = {
    imports = [
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc-adminvm
      (import ./common/vm-networking.nix {
        inherit
          config
          lib
          vmName
          macAddress
          ;
        internalIP = 10;
      })
      # We need to retrieve mac address and start log aggregator
      ../../../common/logging/hw-mac-retrieve.nix
      ../../../common/logging/logs-aggregator.nix
      ./common/storagevm.nix
      (
        { lib, ... }:
        {
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
              withAudit = configHost.ghaf.profiles.debug.enable;
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withTimesyncd = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            storagevm = {
              enable = true;
              name = "adminvm";
              files = [
                "/etc/locale-givc.conf"
                "/etc/timezone.conf"
              ];
            };

            givc.adminvm.enable = true;

            # Log aggregation configuration
            logging = {
              client.enable = isLoggingEnabled;
              listener = {
                inherit (configHost.ghaf.logging.listener) address port;
              };
              identifierFilePath = "/var/lib/private/alloy/MACAddress";
              server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
            };
          };

          system.stateVersion = lib.trivial.release;

          systemd.network = {
            enable = true;
            networks."10-ethint0" = {
              matchConfig.MACAddress = macAddress;
              linkConfig.ActivationPolicy = "always-up";
            };
          };

          nixpkgs = {
            buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
            hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
          };

          networking.firewall = {
            allowedTCPPorts = lib.mkIf isLoggingEnabled [ config.ghaf.logging.listener.port ];
            allowedUDPPorts = [ ];
          };

          microvm = {
            optimize.enable = true;
            #TODO: Add back support cloud-hypervisor
            #the system fails to switch root to the stage2 with cloud-hypervisor
            hypervisor = "qemu";
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
                  # This is only to preserve logs state across adminvm reboots
                  tag = "log-store";
                  source = "/var/lib/private/alloy";
                  mountPoint = "/var/lib/private/alloy";
                  proto = "virtiofs";
                }
              ];

            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
          };
          imports = [ ../../../common ];
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.adminvm;
in
{
  options.ghaf.virtualization.microvm.adminvm = {
    enable = lib.mkEnableOption "AdminVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        AdminVM's NixOS configuration.
      '';
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config = adminvmBaseConfiguration // {
        imports = adminvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
