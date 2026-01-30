# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  configHost = config;
  vmName = "ids-vm";
  idsvmBaseConfiguration = {
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.profiles
      (
        { lib, ... }:
        {
          imports = [
            ./mitmproxy
          ];

          ghaf = {
            type = "system-vm";
            profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;

            virtualization.microvm.idsvm.mitmproxy.enable =
              configHost.ghaf.virtualization.microvm.idsvm.mitmproxy.enable;

            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to NetVM
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };
            virtualization.microvm.vm-networking = {
              enable = true;
              isGateway = true;
              inherit vmName;
            };

            logging = {
              inherit (configHost.ghaf.logging) enable listener;
              client.enable = configHost.ghaf.logging.enable;
            };
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

          environment.systemPackages = [
            pkgs.snort # TODO: put into separate module
          ]
          ++ (lib.optional configHost.ghaf.profiles.debug.enable pkgs.tcpdump);

          microvm = {
            hypervisor = "qemu";
            optimize.enable = true;

            # Shared store (when not using storeOnDisk)
            shares = lib.optionals (!configHost.ghaf.virtualization.microvm.storeOnDisk) [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf (
              !configHost.ghaf.virtualization.microvm.storeOnDisk
            ) "/nix/.rw-store";
          }
          // lib.optionalAttrs configHost.ghaf.virtualization.microvm.storeOnDisk {
            storeOnDisk = true;
            storeDiskType = "erofs";
            storeDiskErofsFlags = [
              "-zlz4hc"
              "-Eztailpacking"
            ];
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.idsvm;
in
{
  imports = [
    ./mitmproxy
  ];

  options.ghaf.virtualization.microvm.idsvm = {
    enable = lib.mkEnableOption "Whether to enable IDS-VM on the system";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        IDSVM's NixOS configuration.
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

      config = idsvmBaseConfiguration // {
        imports = idsvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
