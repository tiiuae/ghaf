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
            inherit self microvm netvm;
          })

          jetpack-nixos.nixosModules.default
          ../modules/hardware/nvidia-jetson-orin.nix

          ./common-${variant}.nix

          ../modules/graphics/weston.nix

          formatModule
        ]
        ++ extraModules;
    };
    netvm = "netvm-${name}-${variant}";
  in {
    inherit hostConfiguration netvm;
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
        ];
      };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  targets = [
    nvidia-jetson-orin-debug
    nvidia-jetson-orin-release
  ];
  crossTargets = map generate-cross-from-x86_64 targets;
  flash-script = import ./nvidia-jetson-orin-flash-script.nix;
  generate-flash-script = tgt:
    flash-script {
      inherit nixpkgs;
      package = tgt.package;
      hostConfiguration = tgt.hostConfiguration;
    };
in {
  nixosConfigurations =
    builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets))
    // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.netvm t.netvmConfiguration) targets);

  packages = {
    aarch64-linux =
      builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.package) targets);
    x86_64-linux =
      builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.package) crossTargets)
      // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t)) (targets ++ crossTargets));
  };
}
