# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "gpio-vm";
  macAddress = "02:00:00:02:02:02";
  netvmBaseConfiguration = {
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
            withName = "gpiovm-systemd";
            withPolkit = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        microvm.hypervisor = "qemu";

        networking = {
          firewall.allowedTCPPorts = [53];
          firewall.allowedUDPPorts = [53];
        };

        # Add simple wi-fi connection helper
        environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [pkgs.wifi-connector];

        # dnsmask is probably not necessary for gpio VM's networking needs
        # note we switch from NetVm's 192.168.100.0/24 base to 192.168.103.0/24
        # Dnsmasq is used as a DHCP/DNS server inside the VM
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = true;
          settings = {
            server = ["8.8.8.8"];
            dhcp-range = ["192.168.103.2,192.168.103.254"];
            dhcp-sequential-ip = true;
            dhcp-authoritative = true;
            domain = "ghaf";
            listen-address = ["127.0.0.1,192.168.103.1"];
            dhcp-option = [
              "option:router,192.168.103.1"
              "6,192.168.103.1"
            ];
            expand-hosts = true;
            domain-needed = true;
            bogus-priv = true;
          };
        };

        # Disable resolved since we are using Dnsmasq
        services.resolved.enable = false;

        systemd.network = {
          enable = true;
          networks."10-ethint0" = {
            matchConfig.MACAddress = macAddress;
            addresses = [
              {
                addressConfig.Address = "192.168.103.3/24";
              }
              {
# note: same debugging subnet as for NetVm
                # IP-address for debugging subnet
                addressConfig.Address = "192.168.101.3/24";
              }
            ];
            linkConfig.ActivationPolicy = "always-up";
          };
        };

        microvm = {
          optimize.enable = true;
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
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
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        netvmBaseConfiguration
        // {
          imports =
            netvmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
    };
  };
}
