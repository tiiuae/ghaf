# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  nixpkgs,
  nixos-generators,
  microvm,
  jetpack-nixos,
}: let
  name = "nvidia-jetson-orin";
  system = "aarch64-linux";

  # Import custom format module
  formatModule = {
    imports = [
      # Needed for formatAttr
      (nixos-generators + "/format-module.nix")

      ../../modules/hardware/nvidia-jetson-orin/format-module.nix
    ];
  };
  nvidia-jetson-orin = som: variant: extraModules: let
    netvmExtraModules = [
      {
        # The Nvidia Orin hardware dependent configuration is in
        # modules/hardware/nvidia-jetson-orin/jetson-orin.nx
        # Please refer to that section for hardware dependent netvm configuration.
        # To enable or disable wireless
        networking.wireless.enable = som == "agx";
        # Wireless Configuration
        # Orin AGX has WiFi enabled where Orin Nx does not

        # For WLAN firmwares
        hardware.enableRedistributableFirmware = som == "agx";
        # Note: When 21.11 arrives replace the below statement with
        # wirelessRegulatoryDatabase = true;
      }
    ];
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};

      modules =
        [
          jetpack-nixos.nixosModules.default
          ../../modules/hardware/nvidia-jetson-orin
          microvm.nixosModules.host
          ../../modules/host
          ../../modules/virtualization/microvm/microvm-host.nix
          ../../modules/virtualization/microvm/netvm.nix
          ({config, ...}: {
            ghaf = {
              hardware.nvidia.orin = {
                enable = true;
                somType = som;
                agx.enableNetvmWlanPCIPassthrough = som == "agx";
                nx.enableNetvmEthernetPCIPassthrough = som == "nx";
              };

              virtualization.microvm-host.enable = true;
              host.networking.enable = true;

              virtualization.microvm.netvm.enable = true;
              virtualization.microvm.netvm.extraModules = netvmExtraModules;

              # Enable all the default UI applications
              profiles = {
                applications.enable = true;

                #TODO clean this up when the microvm is updated to latest
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              # Disable windows-launcher with cross-compilation for now
              windows-launcher.enable =
                config.nixpkgs.buildPlatform.system
                == config.nixpkgs.hostPlatform.system;
            };
          })

          (import ./optee.nix {inherit jetpack-nixos;})

          formatModule
        ]
        ++ (import ../../modules/module-list.nix)
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${som}-${variant}";
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  nvidia-jetson-orin-agx-debug = nvidia-jetson-orin "agx" "debug" [];
  nvidia-jetson-orin-agx-release = nvidia-jetson-orin "agx" "release" [];
  nvidia-jetson-orin-nx-debug = nvidia-jetson-orin "nx" "debug" [];
  nvidia-jetson-orin-nx-release = nvidia-jetson-orin "nx" "release" [];
  generate-nodemoapps = tgt:
    tgt
    // rec {
      name = tgt.name + "-nodemoapps";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            ghaf.graphics.weston.enableDemoApplications = lib.mkForce false;
          }
        ];
      };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  generate-cross-from-x86_64 = tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            nixpkgs.buildPlatform.system = "x86_64-linux";
          }

          ../../overlays/cross-compilation
        ];
      };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  # Base targets to use for generating demoapps and cross-compilation targets
  baseTargets = [
    nvidia-jetson-orin-agx-debug
    nvidia-jetson-orin-agx-release
    nvidia-jetson-orin-nx-debug
    nvidia-jetson-orin-nx-release
  ];
  # Add nodemoapps targets
  targets = baseTargets ++ (map generate-nodemoapps baseTargets);
  crossTargets = map generate-cross-from-x86_64 targets;
  mkFlashScript = import ../../lib/mk-flash-script;
  # Generate flash script variant which flashes both QSPI and eMMC
  generate-flash-script = tgt: flash-tools-system:
    mkFlashScript {
      inherit nixpkgs;
      inherit (tgt) hostConfiguration;
      inherit jetpack-nixos;
      inherit flash-tools-system;
    };
  # Generate flash script variant which flashes QSPI only. Useful for Orin NX
  # and non-eMMC based development.
  generate-flash-qspi = tgt: flash-tools-system:
    mkFlashScript {
      inherit nixpkgs;
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = true;
          }
        ];
      };
      inherit jetpack-nixos;
      inherit flash-tools-system;
    };
in {
  flake.nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets));

  flake.packages = {
    aarch64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets)
      # EXPERIMENTAL: The aarch64-linux hosted flashing support is experimental
      #               and it simply might not work. Providing the script anyway
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "aarch64-linux")) targets)
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-flash-qspi" (generate-flash-qspi t "aarch64-linux")) targets);
    x86_64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-flash-script" (generate-flash-script t "x86_64-linux")) (targets ++ crossTargets))
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-flash-qspi" (generate-flash-qspi t "x86_64-linux")) (targets ++ crossTargets));
  };
}
