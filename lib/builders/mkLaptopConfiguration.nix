# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Laptop Configuration Builder Library
#
# This module provides a reusable function for building laptop configurations
# that can be consumed by both Ghaf internally and downstream projects.
#
# Key features:
# - Creates a shared system configuration that's used by both host and all VMs
# - Exposes extendModules for downstream composition
# - Provides vmConfigurations for downstream to extend individual VMs
#
# Usage in downstream projects:
#   let mkLaptopConfiguration = inputs.ghaf.lib.builders.mkLaptopConfiguration inputs.ghaf;
#   in mkLaptopConfiguration "my-laptop" "debug" [...]
#
# Extended usage for downstream customization:
#   let
#     baseConfig = mkLaptopConfiguration "my-laptop" "debug" [];
#     # Extend the host configuration
#     customHost = baseConfig.extendModules {
#       modules = [{ ghaf.myCustomOption = true; }];
#     };
#     # Extend a specific VM
#     customAudioVm = baseConfig.vmBuilders.mkAudioVm {
#       extraModules = [{ ghaf.myAudioOption = true; }];
#     };
#   in { ... }
#
{
  self,
  inputs,
  lib ? self.lib,
  system ? "x86_64-linux",
}:
let
  # Use flake exports - self.lib
  inherit (self.lib) mkSharedSystemConfig vmBuilders;

  # Instantiate VM builders with inputs and lib
  instantiatedVmBuilders = builtins.mapAttrs (_: builder: builder { inherit inputs lib; }) vmBuilders;

  mkLaptopConfiguration =
    machineType: variant: extraModules:
    let
      # Create the shared configuration that's used by BOTH host AND all VMs
      # This eliminates the need to copy values between host and VMs
      # Note: Logging settings are handled by the profile (mvp-user-trial etc.)
      # which sets them correctly with the admin-vm IP address
      sharedSystemConfig = mkSharedSystemConfig {
        inherit lib variant;
        # Default settings based on variant
        sshDaemonEnable = variant == "debug";
        debugToolsEnable = variant == "debug";
        nixSetupEnable = variant == "debug";
        # Logging is configured by reference profiles with correct IP addresses
        # loggingEnable defaults to true in sharedSystemConfig but listener.address
        # must come from the profile where it has access to networking config
        timeZone = "UTC";
      };

      hostConfiguration = lib.nixosSystem {
        specialArgs = inputs // {
          inherit self inputs lib;
          # Pass sharedSystemConfig to all modules via specialArgs
          # This allows VM modules to use it directly
          inherit sharedSystemConfig;
        };
        modules = [
          self.nixosModules.profiles-workstation
          # Import the shared config in the host
          sharedSystemConfig
          {
            ghaf = {
              profiles = {
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };
            };

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
          }
        ]
        ++ extraModules;
      };

      # Create standalone VM configurations that can be extended by downstream
      # These use the same sharedSystemConfig as the host for consistency
      standaloneVmConfigs = {
        audioVm = instantiatedVmBuilders.mkAudioVm {
          inherit system;
          systemConfigModule = sharedSystemConfig;
        };
        netVm = instantiatedVmBuilders.mkNetVm {
          inherit system;
          systemConfigModule = sharedSystemConfig;
        };
        guiVm = instantiatedVmBuilders.mkGuiVm {
          inherit system;
          systemConfigModule = sharedSystemConfig;
        };
        adminVm = instantiatedVmBuilders.mkAdminVm {
          inherit system;
          systemConfigModule = sharedSystemConfig;
        };
        idsVm = instantiatedVmBuilders.mkIdsVm {
          inherit system;
          systemConfigModule = sharedSystemConfig;
        };
      };
    in
    {
      inherit hostConfiguration;
      inherit variant;
      inherit sharedSystemConfig;
      name = "${machineType}-${variant}";
      package = hostConfiguration.config.system.build.ghafImage;

      # Expose extendModules for downstream host composition
      inherit (hostConfiguration) extendModules;

      # Expose standalone VM configurations for downstream composition
      # Each VM can be extended via .extendModules
      vmConfigurations = standaloneVmConfigs;

      # Expose VM builders for creating custom VMs with the same sharedSystemConfig
      vmBuilders = instantiatedVmBuilders;

      # Helper function to extend a VM with additional modules
      extendVm =
        vmName: extraVmModules:
        if builtins.hasAttr vmName standaloneVmConfigs then
          standaloneVmConfigs.${vmName}.extendModules { modules = extraVmModules; }
        else
          throw "Unknown VM: ${vmName}. Available: ${builtins.concatStringsSep ", " (builtins.attrNames standaloneVmConfigs)}";

      # Helper function to create a custom app VM
      mkCustomAppVm =
        vmSpec:
        instantiatedVmBuilders.mkAppVm {
          inherit system;
          vm = vmSpec;
          systemConfigModule = sharedSystemConfig;
        };
    };
in
mkLaptopConfiguration
