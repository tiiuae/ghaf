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
  inherit (lib) mkOption mkEnableOption types;
in
rec {
  # Type definition for global config options
  # This is used in the ghaf.global-config option definition
  globalConfigType = types.submodule {
    options = {
      debug.enable = mkEnableOption "debug mode globally (host and all VMs)";

      development = {
        ssh.daemon.enable = mkEnableOption "SSH daemon globally";
        debug.tools.enable = mkEnableOption "debug tools globally";
        nix-setup.enable = mkEnableOption "Nix development setup globally";
      };

      logging = {
        enable = mkEnableOption "logging globally";

        listener = {
          address = mkOption {
            type = types.str;
            default = "";
            description = "Logging listener address";
          };

          port = mkOption {
            type = types.port;
            default = 9999;
            description = "Logging listener port";
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

      security.audit.enable = mkEnableOption "security auditing globally";

      givc = {
        enable = mkEnableOption "GIVC (Ghaf Inter-VM Communication) globally";

        debug = mkEnableOption "GIVC debug mode";
      };

      storage = {
        encryption.enable = mkEnableOption "storage encryption globally";
        storeOnDisk = mkEnableOption "storing VM nix stores on disk rather than virtiofs";
      };

      # Shared memory configuration
      shm = {
        enable = mkEnableOption "shared memory for inter-VM communication";

        serverSocketPath = mkOption {
          type = types.str;
          default = "";
          description = "Shared memory server socket path";
        };

        flataddr = mkOption {
          type = types.str;
          default = "0x920000000";
          description = "Maps the shared memory to a physical address for kvm_ivshmem";
        };
      };

      # Graphics/boot UI settings
      graphics.boot.enable = mkEnableOption "graphical boot support (splash screen, user login detection)";

      # IDS VM specific settings
      idsvm.mitmproxy.enable = mkEnableOption "MITM proxy in IDS VM for traffic inspection";

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

      # ═══════════════════════════════════════════════════════════════════════
      # FEATURES - Service Assignment Configuration
      # ═══════════════════════════════════════════════════════════════════════
      #
      # Features define which services are enabled and in which VMs they run.
      # Each feature has:
      #   - enable: Whether the feature is available system-wide
      #   - targetVms: List of VMs that should have this feature
      #
      # Usage in downstream:
      #   ghaf.global-config.features.fprint.targetVms = [ "admin-vm" ];
      #   ghaf.global-config.features.yubikey.targetVms = [ "gui-vm" "admin-vm" ];
      #
      # VM base modules check: lib.ghaf.features.isEnabledFor globalConfig "fprint" vmName
      #
      features = {
        # Hardware authentication services
        fprint = {
          enable = mkEnableOption "fingerprint authentication support" // {
            default = true;
          };
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ "gui-vm" ];
            example = [
              "gui-vm"
              "admin-vm"
            ];
            description = "VMs that should have fingerprint support";
          };
        };

        yubikey = {
          enable = mkEnableOption "Yubikey 2FA support" // {
            default = true;
          };
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ "gui-vm" ];
            example = [
              "gui-vm"
              "admin-vm"
            ];
            description = "VMs that should have Yubikey support";
          };
        };

        brightness = {
          enable = mkEnableOption "brightness control via VirtIO" // {
            default = true;
          };
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ "gui-vm" ];
            description = "VMs that should have brightness control";
          };
        };

        # Networking services
        wifi = {
          enable = mkEnableOption "WiFi networking support" // {
            default = true;
          };
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ "net-vm" ];
            description = "VMs that should have WiFi support";
          };
        };

        # Audio services
        audio = {
          enable = mkEnableOption "audio services" // {
            default = true;
          };
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ "audio-vm" ];
            description = "VMs that should have audio support";
          };
        };

        bluetooth = {
          enable = mkEnableOption "Bluetooth support" // {
            default = true;
          };
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ "audio-vm" ];
            description = "VMs that should have Bluetooth support";
          };
        };

        power-manager = {
          enable = mkEnableOption "Ghaf power management";
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "VMs where Ghaf power management should be enabled";
          };
        };

        performance = {
          enable = mkEnableOption "Ghaf performance and PPD profiles";
          targetVms = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "VMs where Ghaf performance and PPD profiles should be enabled";
          };
        };
      };
    };
  };

  # ═══════════════════════════════════════════════════════════════════════════
  # FEATURE UTILITIES
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # Helper functions for checking and managing service feature assignments.
  # These are used by VM base modules to determine which services to enable.
  #
  # Usage in VM base modules:
  #   ghaf.services.fprint.enable = lib.ghaf.features.isEnabledFor globalConfig "fprint" vmName;
  #
  features = {
    # Check if a feature should be enabled for a specific VM
    #
    # Usage:
    #   lib.ghaf.features.isEnabledFor globalConfig "fprint" "gui-vm"
    #   # Returns: true if fprint.enable && "gui-vm" in fprint.targetVms
    #
    # Parameters:
    #   globalConfig: The ghaf.global-config attribute set (from specialArgs)
    #   featureName: Name of the feature (e.g., "fprint", "wifi")
    #   vmName: Name of the VM to check (e.g., "gui-vm", "net-vm")
    #
    # Returns: bool
    isEnabledFor =
      globalConfig: featureName: vmName:
      let
        featuresAttr = globalConfig.features or { };
        feature =
          featuresAttr.${featureName} or {
            enable = false;
            targetVms = [ ];
          };
      in
      (feature.enable or false) && builtins.elem vmName (feature.targetVms or [ ]);
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

      # Logging enabled with Ghaf's central logging infrastructure
      # Note: listener.address is auto-populated from admin-vm IP by
      # modules/common/global-config.nix (no need to set it per profile).
      logging = {
        enable = true;
        server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
      };

      security.audit.enable = false;

      givc = {
        enable = true;
        # givc.debug disabled to allow logging (they conflict due to security)
        debug = false;
      };

      storage = {
        encryption.enable = false;
        storeOnDisk = false;
      };

      graphics.boot.enable = true;

      shm.enable = false;
      idsvm.mitmproxy.enable = false;

      # Feature defaults for debug profile
      features = {
        fprint = {
          enable = true;
          targetVms = [ "gui-vm" ];
        };
        yubikey = {
          enable = true;
          targetVms = [ "gui-vm" ];
        };
        brightness = {
          enable = true;
          targetVms = [ "gui-vm" ];
        };
        wifi = {
          enable = true;
          targetVms = [ "net-vm" ];
        };
        audio = {
          enable = true;
          targetVms = [ "audio-vm" ];
        };
        bluetooth = {
          enable = true;
          targetVms = [ "audio-vm" ];
        };
        power-manager = {
          enable = true;
          targetVms = [
            "gui-vm"
            "audio-vm"
            "net-vm"
          ];
        };
        performance = {
          enable = true;
          targetVms = [
            "gui-vm"
            "audio-vm"
            "net-vm"
          ];
        };
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

      storage = {
        encryption.enable = true;
        storeOnDisk = false;
      };

      graphics.boot.enable = true;

      shm.enable = false;
      idsvm.mitmproxy.enable = false;

      # Feature defaults for release profile
      features = {
        fprint = {
          enable = true;
          targetVms = [ "gui-vm" ];
        };
        yubikey = {
          enable = true;
          targetVms = [ "gui-vm" ];
        };
        brightness = {
          enable = true;
          targetVms = [ "gui-vm" ];
        };
        wifi = {
          enable = true;
          targetVms = [ "net-vm" ];
        };
        audio = {
          enable = true;
          targetVms = [ "audio-vm" ];
        };
        bluetooth = {
          enable = true;
          targetVms = [ "audio-vm" ];
        };
        power-manager = {
          enable = true;
          targetVms = [
            "gui-vm"
            "audio-vm"
            "net-vm"
          ];
        };
        performance = {
          enable = true;
          targetVms = [
            "gui-vm"
            "audio-vm"
            "net-vm"
          ];
        };
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

      storage = {
        encryption.enable = false;
        storeOnDisk = false;
      };

      shm.enable = false;
      idsvm.mitmproxy.enable = false;

      # Feature defaults for minimal profile - all disabled
      features = {
        fprint = {
          enable = false;
          targetVms = [ ];
        };
        yubikey = {
          enable = false;
          targetVms = [ ];
        };
        brightness = {
          enable = false;
          targetVms = [ ];
        };
        wifi = {
          enable = false;
          targetVms = [ ];
        };
        audio = {
          enable = false;
          targetVms = [ ];
        };
        bluetooth = {
          enable = false;
          targetVms = [ ];
        };
        power-manager = {
          enable = false;
          targetVms = [ ];
        };
        performance = {
          enable = false;
          targetVms = [ ];
        };
      };
    };
  };

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

  # ═══════════════════════════════════════════════════════════════════════════
  # VM COMPOSITION NAMESPACE
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # All VM composition helpers are organized under lib.ghaf.vm.*
  #
  # Functions:
  #   lib.ghaf.vm.mkSpecialArgs - Create specialArgs for VM modules
  #   lib.ghaf.vm.mkHostConfig  - Extract host config for VM specialArgs
  #   lib.ghaf.vm.getConfig     - Get inner NixOS config from microvm.vms entry
  #   lib.ghaf.vm.applyVmConfig - Build modules list with vmConfig applied
  #
  # Usage Example:
  #   guivmBase = lib.nixosSystem {
  #     modules = [ inputs.ghaf.vmBases.guivm ];
  #     specialArgs = lib.ghaf.vm.mkSpecialArgs {
  #       inherit inputs;
  #       globalConfig = config.ghaf.global-config;
  #       hostConfig = lib.ghaf.vm.mkHostConfig { inherit config; vmName = "gui-vm"; };
  #     };
  #   };
  #
  # ═══════════════════════════════════════════════════════════════════════════
  vm = {
    # Create specialArgs for VM modules
    # This ensures consistent propagation of global config to VMs
    #
    # Arguments:
    #   lib         - Extended lib with ghaf functions
    #   inputs      - Flake inputs
    #   globalConfig - Global config value (from config.ghaf.global-config)
    #   hostConfig  - Optional host-specific config (from vm.mkHostConfig)
    #   extraArgs   - Optional additional specialArgs
    #
    # Returns: Attribute set suitable for specialArgs
    mkSpecialArgs =
      {
        lib,
        inputs,
        globalConfig,
        hostConfig ? null,
        extraArgs ? { },
      }:
      {
        inherit lib inputs globalConfig;
      }
      // (if hostConfig != null then { inherit hostConfig; } else { })
      // extraArgs;

    # Extract host-specific config for VM specialArgs
    # This passes settings that are inherently host-bound and cannot be globalized.
    #
    # Arguments:
    #   config      - Host configuration
    #   vmName      - VM name (e.g., "gui-vm", "audio-vm")
    #   extraConfig - Optional additional config to merge
    #
    # Returns: Attribute set with host-specific VM config
    mkHostConfig =
      {
        config,
        vmName,
        extraConfig ? { },
      }:
      let
        vmType = builtins.replaceStrings [ "-" ] [ "" ] vmName;
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

        # Hardware devices
        hardware = {
          devices = config.ghaf.hardware.devices or { };
        };
        # Common namespace (for killswitch, etc.)
        common = config.ghaf.common or { };
        # User configuration (complex, kept as-is for now)
        users = config.ghaf.users or { };

        # Reference config (profile-specific)
        reference = {
          services = config.ghaf.reference.services or { };
          desktop = config.ghaf.reference.desktop or { };
        };

        # Networking info (IP addresses, CIDs, etc. for this VM and others)
        networking = {
          hosts = config.ghaf.networking.hosts or { };
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
        # Use enabledVms which has derived values including applications from vmDef
        appvms = config.ghaf.virtualization.microvm.appvm.enabledVms or { };
        # GUIVM applications (needed by guivm for local launcher generation)
        guivm = {
          applications = config.ghaf.virtualization.microvm.guivm.applications or [ ];
        };
      }
      // extraConfig;

    # Get the inner NixOS config from a microvm.vms entry
    #
    # microvm.nix supports two ways to define VMs:
    # 1. `config` - module-based (evaluates via eval-config.nix)
    #    Access inner config: vmEntry.config.config
    # 2. `evaluatedConfig` - pre-evaluated NixOS system
    #    Access inner config: vmEntry.evaluatedConfig.config
    #
    # This helper abstracts that difference.
    #
    # WARNING: For legacy VMs (using `config` not `evaluatedConfig`),
    # this triggers full VM evaluation which can cause infinite recursion
    # if the VM imports modules that reference host config.
    #
    # Arguments:
    #   vmEntry - Entry from config.microvm.vms.<name>
    #
    # Returns: Inner NixOS config, or null if not available
    getConfig =
      vmEntry:
      if vmEntry.evaluatedConfig != null then
        vmEntry.evaluatedConfig.config
      else if vmEntry.config != null then
        vmEntry.config.config
      else
        null;

    # Build modules list with vmConfig applied
    #
    # This function collects modules from hardware.definition and vmConfig
    # and builds a resource allocation module from vmConfig.mem/vcpu.
    #
    # Module merge order (highest priority last):
    #   1. Base module (guivm-base.nix) - sets mkDefault values
    #   2. resourceModule - applies vmConfig.mem/vcpu
    #   3. hwModules - hardware.definition.<vm>.extraModules
    #   4. vmConfigModules - vmConfig.<vm>.extraModules (highest priority)
    #
    # Arguments:
    #   config - Host configuration (with ghaf.hardware.definition and ghaf.virtualization.vmConfig)
    #   vmName - VM name without -vm suffix (e.g., "guivm", "netvm")
    #
    # Returns: List of modules to add via extendModules
    #
    # Usage in profiles:
    #   guivmBase.extendModules {
    #     modules = lib.ghaf.vm.applyVmConfig { inherit config; vmName = "guivm"; };
    #   };
    applyVmConfig =
      {
        config,
        vmName,
      }:
      let
        hwDef = config.ghaf.hardware.definition.${vmName} or { };
        vmCfg = config.ghaf.virtualization.vmConfig.${vmName} or { };

        hwModules = hwDef.extraModules or [ ];
        vmConfigModules = vmCfg.extraModules or [ ];

        # Resource allocation module (applies vmConfig.mem/vcpu)
        resourceModule =
          lib.optionalAttrs (vmCfg.mem or null != null) { microvm.mem = vmCfg.mem; }
          // lib.optionalAttrs (vmCfg.vcpu or null != null) { microvm.vcpu = vmCfg.vcpu; };
      in
      [ resourceModule ] ++ hwModules ++ vmConfigModules;
  };
}
