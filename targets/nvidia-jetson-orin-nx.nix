# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  nixpkgs,
  nixos-generators,
  microvm,
  jetpack-nixos,
}: let
  name = "nvidia-jetson-orin-nx";
  system = "aarch64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;
  nvidia-jetson-orin-nx = variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          (import ../modules/host {
            inherit self microvm netvm;
          })

          jetpack-nixos.nixosModules.default

          ../modules/hardware/nvidia-jetson-orin-nx

          {
            ghaf = {
              hardware.nvidia.orin.enable = true;
              # Enable all the default UI applications
              profiles = {
                applications.enable = true;

                #TODO clean this up when the microvm is updated to latest
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              # TODO when supported on x86 move under virtualization
              windows-launcher.enable = true;
            };
          }

          formatModule
        ]
        ++ (import ../modules/module-list.nix)
        ++ extraModules;
    };
    netvm = "netvm-${name}-${variant}";
  in {
    inherit hostConfiguration netvm;
    name = "${name}-${variant}";
    netvmConfiguration =
      (import ../modules/virtualization/microvm/netvm.nix {
        inherit lib microvm system;
      })
      .extendModules {
        modules = [
          {
            microvm.devices = [
              {
                bus = "pci";
                path = "0004:00:00.0";
              }
              {
                bus = "pci";
                path = "0008:00:00.0";
              }
            ];

            # For WLAN firmwares
            hardware.enableRedistributableFirmware = true;

            networking.wireless = {
              enable = true;

              # networks."SSID_OF_NETWORK".psk = "WPA_PASSWORD";
            };
          }
        ];
      };
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  nvidia-jetson-orin-nx-debug = nvidia-jetson-orin-nx "debug" [];
  nvidia-jetson-orin-nx-release = nvidia-jetson-orin-nx "release" [];
  generate-cross-from-x86_64 = tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            nixpkgs.buildPlatform.system = "x86_64-linux";
          }

          ../overlays/cross-compilation.nix
        ];
      };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  targets = [
    nvidia-jetson-orin-nx-debug
    nvidia-jetson-orin-nx-release
  ];
  crossTargets = map generate-cross-from-x86_64 targets;
  mkFlashScript = import ../lib/mk-flash-script.nix;
  generate-flash-script = tgt: flash-tools-system:
    mkFlashScript {
      inherit nixpkgs;
      inherit (tgt) hostConfiguration;
      inherit jetpack-nixos;
      inherit flash-tools-system;
    };
in {
  nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets))
    // builtins.listToAttrs (map (t: lib.nameValuePair t.netvm t.netvmConfiguration) targets);

  packages = {
    aarch64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets)
      # EXPERIMENTAL: The aarch64-linux hosted flashing support is experimental
      #               and it simply might not work. Providing the script anyway
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "aarch64-linux")) targets);
    x86_64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "x86_64-linux")) (targets ++ crossTargets));
  };
}
