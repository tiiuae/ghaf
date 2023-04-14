# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  nixpkgs,
  microvm,
  system,
}:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    # TODO: Enable only for development builds
    ../../modules/development/authentication.nix
    ../../modules/development/ssh.nix
    ../../modules/development/packages.nix

    microvm.nixosModules.microvm

    ({pkgs, ...}: {
      networking.hostName = "netvm";
      # TODO: Maybe inherit state version
      system.stateVersion = "22.11";

      # TODO: crosvm PCI passthrough does not currently work
      microvm.hypervisor = "qemu";

      networking.enableIPv6 = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.allowedTCPPorts = [22];

      microvm.interfaces = [
        {
          type = "tap";
          id = "vm-netvm";
          mac = "02:00:00:01:01:01";
        }
      ];

      microvm.qemu.bios.enable = false;
    })
  ];
}
