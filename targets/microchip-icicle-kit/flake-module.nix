# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Polarfire Enablement Kit
{
  inputs,
  lib,
  self,
  ...
}: let
  inherit (inputs) nixos-hardware nixpkgs;
  name = "microchip-icicle-kit";
  system = "riscv64-linux";
  microchip-icicle-kit = variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          nixos-hardware.nixosModules.microchip-icicle-kit
          self.nixosModules.common
          self.nixosModules.host
          self.nixosModules.polarfire

          {
            boot = {
              loader = {
                grub.enable = false;
                generic-extlinux-compatible.enable = true;
              };
            };

            # Disable all the default UI applications
            ghaf = {
              profiles = {
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              development = {
                debug.tools.enable = variant == "debug";
                ssh.daemon.enable = true;
              };
              firewall.kernel-modules.enable = true;
            };
            nixpkgs = {
              buildPlatform.system = "x86_64-linux";
              hostPlatform.system = "riscv64-linux";
              overlays = [
                (import ../../overlays/cross-compilation)
              ];
            };
            boot.kernelParams = ["root=/dev/mmcblk0p2" "rootdelay=5"];
            disabledModules = ["profiles/all-hardware.nix"];
          }
        ]
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.sdImage;
  };

  targets = [
    (microchip-icicle-kit "debug" [])
    (microchip-icicle-kit "release" [])
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages = {
      riscv64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
