# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  nixpkgs,
  nixos-generators,
  microvm,
  jetpack-nixos,
}: let
  name = "nvidia-jetson-orin";
  system = "aarch64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;
  nvidia-jetson-orin = variant: extraModules: let
    hostConfiguration = nixpkgs.lib.nixosSystem {
      inherit system;
      modules =
        [
          (import ../modules/host {
            inherit self microvm netvm guivm;
          })

          jetpack-nixos.nixosModules.default
          ../modules/hardware/nvidia-jetson-orin

          ./common-${variant}.nix

          formatModule
        ]
        ++ extraModules;
    };
    netvm = "netvm-${name}-${variant}";
    guivm = "guivm-${name}-${variant}";
  in {
    inherit hostConfiguration netvm guivm;
    name = "${name}-${variant}";
    netvmConfiguration =
      (import ../microvmConfigurations/netvm {
        inherit nixpkgs microvm system;
      })
      .extendModules {
        modules = [
          {
            microvm.devices = [
              {
                bus = "pci";
                path = "0001:01:00.0";
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
    guivmConfiguration =
      (import ../microvmConfigurations/guivm {
        inherit nixpkgs microvm system;
      })
      .extendModules {
        modules = [
          {
            microvm.devices = [
              {
                bus = "pci";
                path = "0005:01:00.0";
              }
              {
                bus = "pci";
                path = "0005:01:00.1";
              }
            ];
          }
        ];
      };
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  nvidia-jetson-orin-debug = nvidia-jetson-orin "debug" [];
  nvidia-jetson-orin-release = nvidia-jetson-orin "release" [];
  generate-cross-from-x86_64 = tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            nixpkgs.buildPlatform.system = "x86_64-linux";
          }

          ../modules/overlays/cross-compilation.nix
        ];
      };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  targets = [
    nvidia-jetson-orin-debug
    nvidia-jetson-orin-release
  ];
  crossTargets = map generate-cross-from-x86_64 targets;
  mkFlashScript = import ../modules/hardware/nvidia-jetson-orin/mk-flash-script.nix;
  generate-flash-script = tgt: flash-tools-system:
    mkFlashScript {
      inherit nixpkgs;
      inherit (tgt) hostConfiguration;
      inherit jetpack-nixos;
      inherit flash-tools-system;
    };
in {
  nixosConfigurations =
    builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets))
    // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.netvm t.netvmConfiguration) targets)
    // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.guivm t.guivmConfiguration) targets);

  packages = {
    aarch64-linux =
      builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.package) targets)
      # EXPERIMENTAL: The aarch64-linux hosted flashing support is experimental
      #               and it simply might not work. Providing the script anyway
      // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "aarch64-linux")) targets);
    x86_64-linux =
      builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.package) crossTargets)
      // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "x86_64-linux")) (targets ++ crossTargets));
  };
}
