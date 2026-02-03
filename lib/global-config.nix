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

      # Shared memory configuration
      shm = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable shared memory for inter-VM communication";
        };

        serverSocketPath = mkOption {
          type = types.str;
          default = "";
          description = "Shared memory server socket path";
        };
      };

      # IDS VM specific settings
      idsvm = {
        mitmproxy = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable MITM proxy in IDS VM for traffic inspection";
          };
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
      shm.enable = false;
      idsvm.mitmproxy.enable = false;
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
      shm.enable = false;
      idsvm.mitmproxy.enable = false;
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
      shm.enable = false;
      idsvm.mitmproxy.enable = false;
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
      hostConfig ? null, # Optional host-specific config (from mkVmHostConfig)
      extraArgs ? { },
    }:
    {
      inherit lib inputs globalConfig;
    }
    // (if hostConfig != null then { inherit hostConfig; } else { })
    // extraArgs;

  # Helper to create host-specific config for VM specialArgs
  # This passes settings that are inherently host-bound (hardware, kernel, qemu)
  # and cannot be globalized.
  #
  # Usage:
  #   microvm.vms.audio-vm = {
  #     specialArgs = lib.ghaf.mkVmSpecialArgs {
  #       inherit lib inputs;
  #       globalConfig = config.ghaf.global-config;
  #       hostConfig = lib.ghaf.mkVmHostConfig {
  #         inherit config;
  #         vmName = "audio-vm";
  #       };
  #     };
  #   };
  mkVmHostConfig =
    {
      config, # Host config
      vmName, # e.g., "gui-vm", "audio-vm"
      extraConfig ? { },
    }:
    let
      vmType = builtins.replaceStrings [ "-vm" ] [ "" ] vmName;

      # Safely get nested attributes with default
    in
    {
      # VM name for reference
      inherit vmName vmType;

      # Kernel configuration for this VM type (if defined)
      kernel = config.ghaf.kernel.${vmType} or null;

      # QEMU configuration for this VM type (if defined)
      qemu = config.ghaf.qemu.${vmType} or null;

      # Hardware passthrough settings
      passthrough = {
        qemuExtraArgs = config.ghaf.hardware.passthrough.qemuExtraArgs.${vmName} or [ ];
        # vmUdevExtraRules is a list in the host config; join into a single string
        vmUdevExtraRules =
          let
            rules = config.ghaf.hardware.passthrough.vmUdevExtraRules.${vmName} or [ ];
          in
          if rules == [ ] then "" else lib.concatStringsSep "\n" rules;
      };

      # Host filesystem paths
      sharedVmDirectory = config.ghaf.virtualization.microvm-host.sharedVmDirectory or null;

      # Boot configuration
      microvmBoot = {
        enable = config.ghaf.microvm-boot.enable or false;
      };

      # Hardware devices (for modules.nix)
      hardware = {
        devices = config.ghaf.hardware.devices or { };
      };

      # User configuration (complex, kept as-is for now)
      users = config.ghaf.users or { };

      # Reference services (profile-specific)
      reference = {
        services = config.ghaf.reference.services or { };
      };

      # Networking info (IP addresses, CIDs, etc. for this VM and others)
      networking = {
        hosts = config.ghaf.networking.hosts or { };
        # Convenience accessor for this VM's network config
        thisVm = config.ghaf.networking.hosts.${vmName} or { };
      };

      # GIVC configuration
      givc = {
        cliArgs = config.ghaf.givc.cliArgs or "";
        enableTls = config.ghaf.givc.enableTls or false;
      };

      # Security settings (SSH keys, etc.)
      security = {
        sshKeys = config.ghaf.security.sshKeys or { };
      };

      # AppVM configurations (needed by guivm for launcher generation)
      appvms = config.ghaf.virtualization.microvm.appvm.vms or { };
    }
    // extraConfig;

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

  # Helper to extend a VM base with additional modules
  #
  # This function takes a base VM configuration (lib.nixosSystem result)
  # and extends it with additional modules for profile-specific functionality.
  #
  # Usage:
  #   let
  #     guivmBase = lib.ghaf.mkGuiVmBase { inherit lib inputs system; };
  #     extendedGuivm = lib.ghaf.mkExtendedVm {
  #       vmBase = guivmBase;
  #       extraModules = [
  #         ../services
  #         ../programs
  #       ];
  #       globalConfig = config.ghaf.global-config;
  #       hostConfig = lib.ghaf.mkVmHostConfig { inherit config; vmName = "gui-vm"; };
  #     };
  #   in
  #   ghaf.virtualization.microvm.guivm.evaluatedConfig = extendedGuivm;
  #
  mkExtendedVm =
    {
      vmBase, # lib.nixosSystem result with .extendModules
      extraModules ? [ ],
      globalConfig ? { },
      hostConfig ? { },
      extraSpecialArgs ? { },
    }:
    vmBase.extendModules {
      modules = extraModules;
      specialArgs = {
        inherit globalConfig hostConfig;
      }
      // extraSpecialArgs;
    };

  # Helper to get the inner NixOS config from a microvm.vms entry
  #
  # microvm.nix supports two ways to define VMs:
  # 1. `config` - module-based (evaluates via eval-config.nix)
  #    Access inner config: vmEntry.config.config
  # 2. `evaluatedConfig` - pre-evaluated NixOS system
  #    Access inner config: vmEntry.evaluatedConfig.config
  #
  # This helper abstracts that difference.
  #
  # Usage:
  #   lib.ghaf.getVmConfig config.microvm.vms.gui-vm
  #   => returns the inner NixOS config of the VM
  #
  getVmConfig =
    vmEntry:
    if vmEntry.evaluatedConfig != null then
      vmEntry.evaluatedConfig.config
    else if vmEntry.config != null then
      vmEntry.config.config
    else
      null;
}
