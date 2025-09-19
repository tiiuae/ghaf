# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  vmName = "net-vm";
  netvmBaseConfiguration = {
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
            profiles.debug.enable = lib.mkDefault config.ghaf.profiles.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to NetVM
              ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
            };
            users = {
              proxyUser = {
                enable = true;
                extraGroups = [
                  "networkmanager"
                ];
              };
            };

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "netvm-systemd";
              withPolkit = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = config.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.netvm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
            };

            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              isGateway = true;
              inherit vmName;
            };

            # Services
            services = {
              power-manager.vm = {
                enable = pkgs.stdenv.hostPlatform.isx86;
                pciSuspendServices = [
                  "NetworkManager.service"
                  "wpa_supplicant.service"
                ];
              };
            };

            logging.client = true;

            security = {
              fail2ban.enable = config.ghaf.development.ssh.daemon.enable;
              ssh-tarpit = {
                inherit (config.ghaf.development.ssh.daemon) enable;
                listenAddress = config.ghaf.networking.hosts.${vmName}.ipv4;
              };
            };
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = config.nixpkgs.buildPlatform.system;
            hostPlatform.system = config.nixpkgs.hostPlatform.system;
          };

          ghaf.firewall =
            let
              dnsPort = 53;
            in
            {
              allowedTCPPorts = [ dnsPort ];
              allowedUDPPorts = [ dnsPort ];
            };

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            hypervisor = "qemu";
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
            qemu = {
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${config.nixpkgs.hostPlatform.system};
              extraArgs = [
                "-device"
                "qemu-xhci"
              ];
            };
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.netvm;
in
{
  options.ghaf.virtualization.microvm.netvm = {
    enable = lib.mkEnableOption "NetVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        NetVM's NixOS configuration.
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
      autostart = !config.ghaf.microvm-boot.enable;
      restartIfChanged = false;
      inherit (inputs) nixpkgs;
      specialArgs = { inherit lib; };

      config = netvmBaseConfiguration // {
        imports = netvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };

}
