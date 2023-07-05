# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Polarfire Enablement Kit
{
  self,
  lib,
  nixpkgs,
  nixos-hardware,
}: let
  name = "microchip-icicle-kit";
  system = "riscv64-linux";
  microchip-icicle-kit = variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          nixos-hardware.nixosModules.microchip-icicle-kit
          ../modules/hardware/polarfire/mpfs-nixos-sdimage.nix
          ../modules/host

          {
            appstream.enable = false;
            boot = {
              enableContainers = false;
              loader = {
                grub.enable = false;
                generic-extlinux-compatible.enable = true;
              };
            };

            # Disable all the default UI applications
            ghaf = {
              profiles = {
                applications.enable = false;
                graphics.enable = false;
                #TODO clean this up when the microvm is updated to latest
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              development = {
                debug.tools.enable = variant == "debug";
                ssh.daemon.enable = true;
              };
              windows-launcher.enable = false;
            };
            nixpkgs = {
              buildPlatform.system = "x86_64-linux";
              hostPlatform.system = "riscv64-linux";
            };
            boot.kernelParams = ["root=/dev/mmcblk0p2" "rootdelay=5"];
            disabledModules = ["profiles/all-hardware.nix"];
          }
        ]
        ++ (import ../modules/module-list.nix)
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
  nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  packages = {
    riscv64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
