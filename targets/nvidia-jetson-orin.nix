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
  name = "nvidia-jetson-orin";
  system = "aarch64-linux";

  formatModule = nixos-generators.nixosModules.raw-efi;
  nvidia-jetson-orin = som: variant: extraModules: let
    netvmExtraModules = [
      {
        # The Nvidia Orin hardware dependent configuration is in
        # modules/hardware/nvidia-jetson-orin/jetson-orin.nx
        # Please refer to that section for hardware dependent netvm configuration.

        # To enable or disable wireless
        networking.wireless = {
          # Wireless Configuration
          # Orin AGX has WiFi enabled where Orin Nx does not
          enable =
            if som == "agx"
            then nixpkgs.lib.mkForce true
            else nixpkgs.lib.mkForce false;
        };

        # For WLAN firmwares
        hardware.enableRedistributableFirmware =
          if som == "agx"
          then nixpkgs.lib.mkForce true
          else nixpkgs.lib.mkForce false;
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
          ../modules/hardware/nvidia-jetson-orin
          microvm.nixosModules.host
          ../modules/host
          ../modules/virtualization/microvm/microvm-host.nix
          ../modules/virtualization/microvm/netvm.nix
          {
            ghaf = {
              hardware.nvidia.orin.enable = true;
              hardware.nvidia.orin.somType = som;

              virtualization.microvm-host.enable = true;
              host.networking.enable = true;

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
  in {
    inherit hostConfiguration;
    name = "${name}-${som}-${variant}";
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  nvidia-jetson-orin-agx-debug = nvidia-jetson-orin "agx" "debug" [];
  nvidia-jetson-orin-agx-release = nvidia-jetson-orin "agx" "release" [];
  nvidia-jetson-orin-nx-debug = nvidia-jetson-orin "nx" "debug" [];
  nvidia-jetson-orin-nx-release = nvidia-jetson-orin "nx" "release" [];
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
    nvidia-jetson-orin-agx-debug
    nvidia-jetson-orin-agx-release
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
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets));

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
