# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#  Configuration for NVIDIA Jetson Orin AGX/NX
#
{
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (inputs) jetpack-nixos nixpkgs;
  system = "aarch64-linux";
  pkgsX86 = nixpkgs.legacyPackages.x86_64-linux;
  lazyPackage =
    name: drv:
    (lib.lazyDerivation {
      derivation = drv;
    })
    // {
      inherit name;
    };

  # Unified Ghaf configuration builder
  ghaf-configuration = self.builders.mkGhafConfiguration {
    inherit self inputs;
    inherit (self) lib;
  };

  # Orin-specific modules (UEFI patches, OP-TEE, format modules)
  orinSpecificModules = [
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/format-module.nix
    jetpack-nixos.nixosModules.default
  ];

  # Common modules shared across all Orin configurations
  commonModules = orinSpecificModules ++ [
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-profiles-orin
    self.nixosModules.profiles
  ];

  # All Orin configurations using mkGhafConfiguration
  target-configs = [
    # ============================================================
    # Debug Configurations
    # ============================================================

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx64";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx64;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx-industrial";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx-industrial;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-nx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-nx;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    # ============================================================
    # Release Configurations
    # ============================================================

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx64";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx64;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx-industrial";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx-industrial;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-nx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-nx;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })
  ];

  generate-nodemoapps =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-nodemoapps";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          { ghaf.reference.host-demo-apps.demo-apps.enableDemoApplications = lib.mkForce false; }
        ];
      };
      package = hostConfiguration.config.system.build.ghafImage;
    };

  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ self.nixosModules.cross-compilation-from-x86_64 ];
      };
      package = lazyPackage name hostConfiguration.config.system.build.ghafImage;
    };

  # Add nodemoapps targets
  targets = target-configs ++ (map generate-nodemoapps target-configs);
  crossTargets = map generate-cross-from-x86_64 targets;
  secureTarget =
    t: qspiOnly:
    let
      innerName = t.hostConfiguration.config.hardware.nvidia-jetpack.name;
      noSB =
        (t.hostConfiguration.extendModules {
          modules = [
            {
              ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
            }
          ];
        }).pkgs.nvidia-jetpack.flashScript;
      withSB =
        (t.hostConfiguration.extendModules {
          modules = [
            {
              ghaf.hardware.nvidia.orin.secureboot.enable = lib.mkForce true;
              ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
            }
          ];
        }).pkgs.nvidia-jetpack.flashScript;
    in
    # Single `*-flash-script` entrypoint that picks between two
    # pre-built QSPI firmware variants at flash time.
    #
    # Why two variants instead of one profile-level toggle:
    #
    # `ghaf.hardware.nvidia.orin.secureboot.enable` is evaluated at Nix
    # build time. When true, it bakes the `UefiDefaultSecurityKeys`
    # device-tree overlay and PK/KEK/db ESLs into the QSPI firmware, so
    # the device enrolls keys and turns Secure Boot on at first boot.
    # Flipping it on unconditionally in the Orin profile would brick the
    # default unsigned flash path: the QSPI carries enrollment material
    # but BOOTAA64.EFI is unsigned, leaving the board in the UEFI
    # Interactive Shell with no recoverable boot entry.
    #
    # `-s/--signed-sd-image` is a *runtime* flag on the flash script: it
    # only swaps in a signed BOOTAA64.EFI / kernel staged from a signed
    # sd-image, it cannot influence the QSPI firmware that was already
    # produced at Nix evaluation time. So the QSPI variant has to be
    # selected *before* the script runs, which is what the wrapper does:
    #
    #   - no `-s`  → unsigned QSPI (no DTBO, no ESLs) + unsigned BOOTAA64.EFI
    #   - with `-s` → SB-enabled QSPI (DTBO + ESLs) + signed BOOTAA64.EFI
    #
    # Both variants share substituted store paths (jetpack-nixos
    # `flashScript` is a thin wrapper around the same per-target
    # derivations), so the second build is mostly a Nix-eval cost.
    pkgsX86.writeShellApplication {
      name = "flash-ghaf-host";
      text = ''
        signed=0
        for arg in "$@"; do
          case "$arg" in
            -s|--signed-sd-image) signed=1 ;;
          esac
        done
        if [ "$signed" = 1 ]; then
          exec ${withSB}/bin/flash-${innerName} "$@"
        else
          exec ${noSB}/bin/flash-${innerName} "$@"
        fi
      '';
    };
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets)
    );

    packages = {
      aarch64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
        // builtins.listToAttrs (
          map (
            t:
            #Note: secureTarget does not toggle between secureboot on/off!!
            lib.nameValuePair "${t.name}-flash-script" (
              lazyPackage "${t.name}-flash-script" (secureTarget t false)
            )
          ) crossTargets
        )
        // builtins.listToAttrs (
          map (
            t:
            #Note: secureTarget does not toggle between secureboot on/off!!
            lib.nameValuePair "${t.name}-flash-qspi" (lazyPackage "${t.name}-flash-qspi" (secureTarget t true))
          ) crossTargets
        );
    };
  };
}
