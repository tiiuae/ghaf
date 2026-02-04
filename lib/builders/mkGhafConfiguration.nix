# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkGhafConfiguration - Unified Ghaf Configuration Builder
#
# Creates a Ghaf configuration for any supported target type.
# This builder unifies mkLaptopConfiguration and mkOrinConfiguration into
# a single, composable API with vmConfig support for resource allocation.
#
# Usage:
#   let
#     ghafConfig = ghaf.builders.mkGhafConfiguration {
#       inherit self inputs;
#     };
#   in ghafConfig {
#     name = "lenovo-x1-carbon-gen11";
#     system = "x86_64-linux";
#     profile = "laptop-x86";
#     hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
#     variant = "debug";
#     extraModules = [ ... ];
#     extraConfig = { ... };
#     vmConfig = {
#       guivm = { mem = 16384; vcpu = 8; };
#     };
#   }
#
# Parameters:
#   name           - Target machine name (e.g., "lenovo-x1-carbon-gen11")
#   system         - Target system architecture ("x86_64-linux" or "aarch64-linux")
#   profile        - Target profile: "laptop-x86" or "orin"
#   hardwareModule - NixOS module for hardware-specific configuration
#   variant        - Build variant: "debug" or "release" (default: "debug")
#   extraModules   - Additional NixOS modules for the host (default: [])
#   extraConfig    - Additional ghaf.* configuration (default: {})
#   vmConfig       - VM resource allocation and modules (default: {})
#                    Maps to ghaf.virtualization.vmConfig
#
# Output:
#   {
#     name              - Full configuration name (e.g., "lenovo-x1-carbon-gen11-debug")
#     variant           - The variant type
#     hostConfiguration - The NixOS system configuration
#     package           - The build output (ghafImage or formatAttr)
#     extendHost        - Function to extend host with additional modules
#     extendVm          - Function to extend a specific VM
#     getVmConfig       - Function to get a VM's final configuration
#   }
#
{
  self,
  inputs,
  lib ? self.lib,
}:
let
  # The actual builder function that accepts configuration parameters
  mkGhafConfiguration =
    {
      name,
      system,
      profile,
      hardwareModule,
      variant ? "debug",
      extraModules ? [ ],
      extraConfig ? { },
      vmConfig ? { },
    }:
    let
      # Select the profile module based on target type
      profileModule =
        {
          "laptop-x86" = self.nixosModules.profiles-workstation;
          "orin" = self.nixosModules.profiles-orin;
        }
        .${profile}
          or (throw "mkGhafConfiguration: Unknown profile '${profile}'. Valid profiles: laptop-x86, orin");

      # Module to map vmConfig parameter to ghaf.virtualization.vmConfig option
      vmConfigModule = {
        ghaf.virtualization.vmConfig = vmConfig;
      };

      # Module for extraConfig (wrapped properly)
      extraConfigModule = lib.optionalAttrs (extraConfig != { }) { ghaf = extraConfig; };

      # Common nixpkgs configuration
      nixpkgsModule = {
        nixpkgs = {
          hostPlatform.system = system;

          # Increase the support for different devices by allowing the use
          # of proprietary drivers from the respective vendors
          config = {
            allowUnfree = true;
            # jitsi was deemed insecure because of an obscure potential security
            # vulnerability but it is still used by many people
            permittedInsecurePackages = [
              "jitsi-meet-1.0.8043"
              "qtwebengine-5.15.19"
            ];
          };

          overlays = [ self.overlays.default ];
        };
      };

      # Variant configuration (debug/release profiles)
      variantModule = {
        ghaf.profiles = {
          debug.enable = variant == "debug";
          release.enable = variant == "release";
        };
      };

      # Build the host NixOS configuration
      hostConfiguration = lib.nixosSystem {
        specialArgs = inputs // {
          inherit lib inputs;
        };
        modules = [
          profileModule
          hardwareModule
          nixpkgsModule
          variantModule
          vmConfigModule
          extraConfigModule
        ]
        ++ extraModules;
      };

      # Full configuration name
      fullName = "${name}-${variant}";

      # Determine the package output based on profile
      package =
        if profile == "orin" then
          hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr}
        else
          hostConfiguration.config.system.build.ghafImage;

      # Recursive reference for composition helpers
      mkGhafConfiguration' = args: (import ./mkGhafConfiguration.nix { inherit self inputs lib; }) args;

      # Helper: Extend host with additional modules
      extendHost =
        modules:
        mkGhafConfiguration' {
          inherit
            name
            system
            profile
            hardwareModule
            variant
            extraConfig
            vmConfig
            ;
          extraModules = extraModules ++ modules;
        };

      # Helper: Extend a specific VM with additional modules
      extendVm =
        vmName: modules:
        mkGhafConfiguration' {
          inherit
            name
            system
            profile
            hardwareModule
            variant
            extraModules
            extraConfig
            ;
          vmConfig = vmConfig // {
            ${vmName} = (vmConfig.${vmName} or { }) // {
              extraModules = (vmConfig.${vmName}.extraModules or [ ]) ++ modules;
            };
          };
        };

      # Helper: Get a VM's final configuration
      getVmConfig =
        vmName:
        lib.ghaf.vm.getConfig {
          inherit vmName;
          inherit (hostConfiguration) config;
        };

    in
    {
      inherit
        hostConfiguration
        package
        variant
        extendHost
        extendVm
        getVmConfig
        ;
      name = fullName;
    };
in
mkGhafConfiguration
