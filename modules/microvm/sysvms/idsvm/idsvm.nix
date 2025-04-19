# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
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
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.givc
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

          };

          system.stateVersion = lib.trivial.release;

          nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

          microvm.hypervisor = "qemu";

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
    extraNetworking = lib.mkOption {
      type =
        let
          extraNetworkingType = import ../../../common/networking/common_types.nix { inherit lib; };
        in
        extraNetworkingType;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {

    ghaf.common.extraNetworking.hosts.ids-vm = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      config = idsvmBaseConfiguration // {
        imports = idsvmBaseConfiguration.imports ++ cfg.extraModules;

        ghaf.virtualization.microvm.vm-networking =
          {
            enable = true;
            isGateway = true;
            inherit vmName;
          }
          // lib.optionalAttrs ((cfg.extraNetworking.interfaceName or null) != null) {
            inherit (cfg.extraNetworking) interfaceName;
          };

      };
    };
  };
}
