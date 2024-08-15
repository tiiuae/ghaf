# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  configHost = config;
  vmName = "ids-vm";
  macAddress = "02:00:00:01:01:02";
  idsvmBaseConfiguration = {
    imports = [
      (import ../common/vm-networking.nix {
        inherit
          config
          lib
          vmName
          macAddress
          ;
        internalIP = 4;
      })
      (
        { lib, ... }:
        {
          ghaf = {
            users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
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
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

          microvm.hypervisor = "cloud-hypervisor";

          environment.systemPackages = [
            pkgs.snort # TODO: put into separate module
          ] ++ (lib.optional configHost.ghaf.profiles.debug.enable pkgs.tcpdump);

          microvm = {
            optimize.enable = true;
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

          imports = [
            ../../../../common
            ./mitmproxy
          ];
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.idsvm;
in
{
  options.ghaf.virtualization.microvm.idsvm = {
    enable = lib.mkEnableOption "Whether to enable IDS-VM on the system";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        IDSVM's NixOS configuration.
      '';
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config = idsvmBaseConfiguration // {
        imports = idsvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
