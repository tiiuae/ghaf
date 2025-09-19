# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  ...
}:
let

  configHost = config;
  vmName = "admin-vm";

  adminvmBaseConfiguration = {
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        { lib, ... }:
        {
          ghaf = {
            # Profiles
            profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to VM
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };

            # System
            type = "admin-vm";
            systemd = {
              enable = true;
              withName = "adminvm-systemd";
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withTimesyncd = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.adminvm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              files = [
                "/etc/locale-givc.conf"
                "/etc/timezone.conf"
              ];
            };
            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };
            # Services
            # Enable logging server on admin-vm
            logging.server = true;

            security.fail2ban.enable = configHost.ghaf.development.ssh.daemon.enable;

          };

          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
            hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
          };

          microvm = {
            optimize.enable = false;
            #TODO: Add back support cloud-hypervisor
            #the system fails to switch root to the stage2 with cloud-hypervisor
            hypervisor = "qemu";
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
              {
                tag = "ghaf-common";
                source = "/persist/common";
                mountPoint = "/etc/common";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
          };
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
    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      specialArgs = { inherit lib; };
      config = adminvmBaseConfiguration // {
        imports = adminvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
