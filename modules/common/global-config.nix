# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Global Configuration Options Module
#
# This module defines the ghaf.global-config options that propagate to all VMs.
# Settings here are the "single source of truth" for configuration values
# that should be consistent across host and all guest VMs.
#
# Supports versioned profiles via lib.ghaf.profiles and lib.ghaf.mkGlobalConfig.
#
# Usage:
#   # Use a predefined profile
#   ghaf.global-config = lib.ghaf.profiles.debug;
#
#   # Or customize a profile
#   ghaf.global-config = lib.ghaf.mkGlobalConfig "debug" {
#     storage.encryption.enable = true;
#   };
#
#   # Or set options directly
#   ghaf.global-config = {
#     debug.enable = true;
#     development.ssh.daemon.enable = true;
#   };
#
# Backward Compatibility:
#   This module provides sync from existing ghaf.* options → global-config.
#   Old-style settings will automatically populate global-config so that
#   VMs using the new pattern receive correct values.
{
  config,
  lib,
  options,
  ...
}:
let

  # Helper to check if an option path exists in the options tree
  optionExists = path: lib.hasAttrByPath path options;

  # Helper to get config value if option exists, otherwise use default
  configOrDefault =
    path: default: if optionExists path then lib.getAttrFromPath path config else default;
in
{
  _file = ./global-config.nix;

  options.ghaf.global-config = lib.mkOption {
    type = lib.types.globalConfig;
    default = { };
    description = ''
      Global configuration options that automatically propagate to all VMs.

      These settings represent the "single source of truth" for values that
      should be consistent across the host and all guest virtual machines.

      You can use predefined profiles:
        ghaf.global-config = lib.ghaf.profiles.debug;

      Or customize a profile:
        ghaf.global-config = lib.ghaf.mkGlobalConfig "debug" {
          storage.encryption.enable = true;
        };

      Or set options directly:
        ghaf.global-config = {
          debug.enable = true;
          development.ssh.daemon.enable = true;
          storage.encryption.enable = true;
        };

      VMs automatically inherit these settings but can override them if needed:
        ghaf.virtualization.microvm.guivm.extraModules = [{
          ghaf.profiles.debug.enable = lib.mkForce false;  # Override for this VM only
        }];
    '';
  };

  config = {
    # Populate platform information from host config
    ghaf.global-config.platform = {
      buildSystem = lib.mkDefault config.nixpkgs.buildPlatform.system;
      hostSystem = lib.mkDefault config.nixpkgs.hostPlatform.system;
      timeZone = lib.mkDefault (if config.time.timeZone != null then config.time.timeZone else "UTC");
    };

    # Backward compatibility: sync from old-style ghaf.* options → global-config
    # Use lib.mkOverride 900 so explicit global-config settings (priority 1000) take precedence
    # but these defaults take precedence over the type defaults (priority 1500)

    # Debug settings
    ghaf.global-config.debug.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "profiles" "debug" "enable" ] false
    );

    # Development settings
    ghaf.global-config.development.ssh.daemon.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "development" "ssh" "daemon" "enable" ] false
    );

    ghaf.global-config.development.debug.tools.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "development" "debug" "tools" "enable" ] false
    );

    ghaf.global-config.development.nix-setup.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "development" "nix-setup" "enable" ] false
    );

    # Logging settings
    ghaf.global-config.logging.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "logging" "enable" ] false
    );

    ghaf.global-config.logging.listener.address = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "logging" "listener" "address" ] ""
    );

    ghaf.global-config.logging.server.endpoint = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "logging" "server" "endpoint" ] ""
    );

    # Security settings
    ghaf.global-config.security.audit.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "security" "audit" "enable" ] false
    );

    # GIVC settings
    ghaf.global-config.givc.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "givc" "enable" ] false
    );

    ghaf.global-config.givc.debug = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "givc" "debug" ] false
    );

    # Services settings
    ghaf.global-config.services.power-manager.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "services" "power-manager" "enable" ] false
    );

    ghaf.global-config.services.performance.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "services" "performance" "enable" ] false
    );

    # Storage settings
    ghaf.global-config.storage.encryption.enable = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "virtualization" "storagevm-encryption" "enable" ] false
    );

    ghaf.global-config.storage.storeOnDisk = lib.mkOverride 900 (
      configOrDefault [ "ghaf" "virtualization" "microvm" "storeOnDisk" ] false
    );
  };
}
