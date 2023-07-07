# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  microvm,
  system,
  nixpkgs,
}:
lib.nixosSystem {
  inherit system;
  specialArgs = {inherit lib;};
  modules =
    [
      {
        ghaf = {
          users.accounts.enable = true;
          development = {
            ssh.daemon.enable = true;
            debug.tools.enable = true;
          };
        };
      }

      microvm.nixosModules.microvm

      ({config, lib, pkgs, ...}: {
        networking.hostName = "guivm";
        # TODO: Maybe inherit state version
        system.stateVersion = lib.trivial.release;

        # TODO: crosvm PCI passthrough does not currently work
        microvm.hypervisor = "qemu";

        nixpkgs.overlays = [
          (self: super: {
            qemu_kvm = super.qemu_kvm.overrideAttrs (self: super: {
              patches = super.patches ++ [./qemu-aarch-memory.patch];
            });
          })
        ];

        networking = {
          enableIPv6 = false;
          interfaces.ethint0.useDHCP = false;
          firewall.allowedTCPPorts = [22];
          firewall.allowedUDPPorts = [67];
          useNetworkd = true;
        };

        environment.systemPackages = with pkgs; [
        weston
      ];

        hardware.nvidia.modesetting.enable = true;
        nixpkgs.config.allowUnfree = true;
        services.xserver.videoDrivers = ["nvidia"];
        hardware.nvidia.open = false;
        hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;

        boot.kernelParams = [
          "pci=nomsi"
        ];

        microvm.interfaces = [
          {
            type = "tap";
            id = "vm-guivm";
            mac = "02:00:00:02:01:01";
          }
        ];

        networking.nat = {
          enable = true;
          internalInterfaces = ["ethint0"];
        };

        # Set internal network's interface name to ethint0
        systemd.network.links."10-ethint0" = {
          matchConfig.PermanentMACAddress = "02:00:00:02:01:01";
          linkConfig.Name = "ethint0";
        };

        systemd.network = {
          enable = true;
          networks."10-ethint0" = {
            matchConfig.MACAddress = "02:00:00:02:01:01";
            networkConfig.DHCPServer = true;
            dhcpServerConfig.ServerAddress = "192.168.200.1/24";
            addresses = [
              {
                addressConfig.Address = "192.168.200.1/24";
              }
              {
                # IP-address for debugging subnet
                addressConfig.Address = "192.168.201.1/24";
              }
            ];
            linkConfig.ActivationPolicy = "always-up";
          };
        };

        microvm.qemu.bios.enable = false;
        microvm.storeDiskType = "squashfs";
      })
    ]
    ++ (import ../../module-list.nix);
}

