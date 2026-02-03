# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Global Configuration Types, Profiles, and Utilities
#
# This module defines the types and helper functions for ghaf.global-config.
# These options are set once at the top level (host configuration) and
# automatically propagate to all VMs via specialArgs.
#
# The global-config system supports versioned profiles (debug, release, minimal)
# that can be selected and extended as needed.
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
#   # In VM modules, access via specialArgs
#   { globalConfig, ... }:
#   {
#     ghaf.profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;
#   }
{ lib }:
let
  inherit (lib) mkOption types;
in
rec {
  # Type definition for global config options
  # This is used in the ghaf.global-config option definition
  globalConfigType = types.submodule {
    options = {
      debug = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable debug mode globally (host and all VMs)";
        };
      };

      development = {
        ssh = {
          daemon = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable SSH daemon globally";
            };
          };
        };

        debug = {
          tools = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable debug tools globally";
            };
          };
        };

        nix-setup = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Nix development setup globally";
          };
        };
      };

      logging = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable logging globally";
        };

        listener = {
          address = mkOption {
            type = types.str;
            default = "";
            description = "Logging listener address";
          };
        };

        server = {
          endpoint = mkOption {
            type = types.str;
            default = "";
            description = "Logging server endpoint";
          };
        };
      };

      security = {
        audit = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable security auditing globally";
          };
        };
      };

      givc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable GIVC (Ghaf Inter-VM Communication) globally";
        };

        debug = mkOption {
          type = types.bool;
          default = false;
          description = "Enable GIVC debug mode";
        };
      };

      services = {
        power-manager = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable power manager service globally";
          };
        };

        performance = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable performance service globally";
          };
        };
      };

      storage = {
        encryption = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable storage encryption globally";
          };
        };

        storeOnDisk = mkOption {
          type = types.bool;
          default = false;
          description = "Store VM nix stores on disk rather than virtiofs";
        };
      };

      # Platform information (populated from host config)
      platform = {
        buildSystem = mkOption {
          type = types.str;
          default = "x86_64-linux";
          description = "Build platform system (e.g., x86_64-linux)";
        };

        hostSystem = mkOption {
          type = types.str;
          default = "x86_64-linux";
          description = "Host platform system (e.g., x86_64-linux)";
        };

        timeZone = mkOption {
          type = types.str;
          default = "UTC";
          description = "System timezone";
        };
      };

      # Extensible: additional settings discovered during migration
      # will be added here as we migrate more VMs
    };
  };

  # Predefined global config profiles
  # These can be selected and extended in target configurations
  profiles = {
    # Debug profile - full development/debugging capabilities
    debug = {
      debug.enable = true;
      development = {
        ssh.daemon.enable = true;
        debug.tools.enable = true;
        nix-setup.enable = true;
      };
      logging.enable = true;
      security.audit.enable = false;
      givc = {
        enable = true;
        debug = true;
      };
      services = {
        power-manager.enable = false;
        performance.enable = false;
      };
      storage = {
        encryption.enable = false;
        storeOnDisk = false;
      };
    };

    # Release profile - production settings
    release = {
      debug.enable = false;
      development = {
        ssh.daemon.enable = false;
        debug.tools.enable = false;
        nix-setup.enable = false;
      };
      logging.enable = false;
      security.audit.enable = true;
      givc = {
        enable = true;
        debug = false;
      };
      services = {
        power-manager.enable = true;
        performance.enable = true;
      };
      storage = {
        encryption.enable = true;
        storeOnDisk = false;
      };
    };

    # Minimal profile - bare minimum
    minimal = {
      debug.enable = false;
      development = {
        ssh.daemon.enable = false;
        debug.tools.enable = false;
        nix-setup.enable = false;
      };
      logging.enable = false;
      security.audit.enable = false;
      givc = {
        enable = false;
        debug = false;
      };
      services = {
        power-manager.enable = false;
        performance.enable = false;
      };
      storage = {
        encryption.enable = false;
        storeOnDisk = false;
      };
    };
  };

  # Helper function to create specialArgs for VM modules
  # This ensures consistent propagation of global config
  #
  # Usage:
  #   microvm.vms.my-vm = {
  #     specialArgs = lib.ghaf.mkVmSpecialArgs {
  #       inherit lib inputs globalConfig;
  #     };
  #   };
  mkVmSpecialArgs =
    {
      lib,
      inputs,
      globalConfig,
      extraArgs ? { },
    }:
    {
      inherit lib inputs globalConfig;
    }
    // extraArgs;

  # Helper to merge a profile with overrides
  #
  # Usage:
  #   ghaf.global-config = lib.ghaf.mkGlobalConfig "debug" {
  #     storage.encryption.enable = true;
  #   };
  mkGlobalConfig =
    profileName: overrides:
    let
      base = profiles.${profileName} or (throw "Unknown global-config profile: ${profileName}");
    in
    lib.recursiveUpdate base overrides;
}
