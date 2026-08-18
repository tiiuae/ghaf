# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkGhafConfiguration - Unified Ghaf Configuration Builder
#
# Creates a Ghaf configuration for any supported target type.
# This builder unifies mkLaptopConfiguration and mkOrinConfiguration into
# a single, composable API with vmConfig support for resource allocation.
#
# Usage (inside ghaf, where self/inputs are ghaf's own):
#   let
#     ghafConfig = ghaf.builders.mkGhafConfiguration {
#       inherit self inputs;
#     };
#   in ghafConfig {
#     name = "intel-laptop";
#     system = "x86_64-linux";
#     profile = "laptop-x86";
#     hardwareModule = self.nixosModules.hardware-intel-laptop;
#     variant = "debug";
#     extraModules = [ ... ];
#     extraConfig = { ... };
#     vmConfig = {
#       sysvms.guivm = { mem = 16384; vcpu = 8; };
#     };
#   }
#
# DOWNSTREAM projects should use the PRE-BOUND form exported alongside this one
# (see ./flake-module.nix), which is already bound to ghaf's self/inputs/lib:
#
#   inputs.ghaf.builders.ghafConfiguration {
#     name = "my-laptop";
#     system = "x86_64-linux";
#     profile = "laptop-x86";
#     hardwareModule = inputs.ghaf.nixosModules.hardware-intel-laptop;
#     # reach your own flake from inside your modules, host and VMs alike,
#     # as `inputs.mine`:
#     extraInputs = { mine = self; };
#   }
#
# Parameters:
#   name           - Target machine name (e.g., "intel-laptop")
#   system         - Target system architecture ("x86_64-linux" or "aarch64-linux")
#   profile        - Target profile: "laptop-x86" or "orin"
#   hardwareModule - NixOS module for hardware-specific configuration
#   variant        - Build variant: "debug" or "release" (default: "debug")
#   extraModules   - Additional NixOS modules for the host (default: [])
#   extraConfig    - Additional ghaf.* configuration (default: {})
#   vmConfig       - VM resource allocation and modules (default: {})
#                    Maps to ghaf.virtualization.vmConfig
#   extraInputs    - Extra names merged into `inputs` (default: {}). Visible as
#                    module arguments of the host and, because ghaf's profiles
#                    forward the same attrset, of every VM. This is how a
#                    DOWNSTREAM reaches its own flake from inside a module --
#                    `self` and `inputs` there are ghaf's. Cannot shadow `lib`
#                    or `inputs`.
#
# Output:
#   {
#     name              - Full configuration name (e.g., "intel-laptop-debug")
#     variant           - The variant type
#     hostConfiguration - The NixOS system configuration
#     package           - The build output (ghafImage)
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
      extraInputs ? { },
      buildSysupdateImage ? false,
    }:
    let
      # Select the profile module based on target type
      profileModule =
        {
          "laptop-x86" = self.nixosModules.profiles-laptop-x86;
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
      # Sets both:
      # 1. ghaf.profiles.{debug,release}.enable for host-side module activation
      # 2. ghaf.global-config to the corresponding profile for VM-side config propagation
      #
      # Note: global-config uses mkDefault so target modules can still override specific
      # values when needed.

      variantModule = {
        ghaf.profiles = {
          debug.enable = variant == "debug";
          release.enable = variant == "release";
        };
        # Set global-config to match the variant's profile using mkDefault
        ghaf.global-config = lib.mapAttrsRecursive (_: v: lib.mkDefault v) (
          lib.ghaf.profiles.${variant} or lib.ghaf.profiles.minimal
        );
      };

      # Extra names a downstream wants visible from inside its own modules.
      #
      # These are merged into `inputs` rather than added alongside it, and that
      # is deliberate: `inputs` is the ONLY part of the host's specialArgs that
      # reaches the VMs. The profiles build each VM with
      # lib.ghaf.vm.mkSpecialArgs { inherit lib inputs; globalConfig; hostConfig; }
      # (modules/profiles/laptop-x86.nix), so a name added to the host's
      # specialArgs but not to `inputs` resolves on the host and is missing in
      # every guest -- which fails only once a guest module happens to read it.
      #
      # Merging here means `inputs.<name>` resolves identically in host,
      # system-VM and app-VM modules.
      allInputs = inputs // extraInputs;

      # Build the host NixOS configuration
      hostConfiguration = lib.nixosSystem {
        specialArgs = allInputs // {
          inherit lib;
          inputs = allInputs;
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
      # Determine the package output
      package = hostConfiguration.config.system.build.ghafImage;

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
            extraInputs
            buildSysupdateImage
            ;
          extraModules = extraModules ++ modules;
        };

      # Helper: Extend a specific VM with additional modules
      extendVm =
        vmName: modules:
        let
          inSysvms = (vmConfig.sysvms or { }) ? ${vmName};
          inAppvms = (vmConfig.appvms or { }) ? ${vmName};
          updatedVmConfig =
            if inSysvms then
              vmConfig
              // {
                sysvms = vmConfig.sysvms // {
                  ${vmName} = vmConfig.sysvms.${vmName} // {
                    extraModules = (vmConfig.sysvms.${vmName}.extraModules or [ ]) ++ modules;
                  };
                };
              }
            else if inAppvms then
              vmConfig
              // {
                appvms = vmConfig.appvms // {
                  ${vmName} = vmConfig.appvms.${vmName} // {
                    extraModules = (vmConfig.appvms.${vmName}.extraModules or [ ]) ++ modules;
                  };
                };
              }
            else
              throw "extendVm: '${vmName}' not found in vmConfig.sysvms or vmConfig.appvms";
        in
        mkGhafConfiguration' {
          inherit
            name
            system
            profile
            hardwareModule
            variant
            extraModules
            extraConfig
            extraInputs
            buildSysupdateImage
            ;
          vmConfig = updatedVmConfig;
        };

      # Helper: Get a VM's final configuration
      #
      # `vmName` is the microvm.vms key, i.e. the hyphenated form ("gui-vm").
      # That is what lib.ghaf.vm.getConfig documents as its argument and what
      # every other caller in the tree passes.
      #
      # Note this differs from extendVm above, which takes the
      # ghaf.virtualization.vmConfig.sysvms key ("guivm"). Both conventions
      # exist across the codebase -- global-config's features.targetVms is
      # hyphenated, hardware.definition.<vm> is not -- and reconciling them is
      # a separate change.
      getVmConfig = vmName: lib.ghaf.vm.getConfig hostConfiguration.config.microvm.vms.${vmName};

    in
    {
      inherit
        hostConfiguration
        package
        variant
        extendHost
        extendVm
        getVmConfig
        buildSysupdateImage
        ;
      name = fullName;
    };
in
mkGhafConfiguration
