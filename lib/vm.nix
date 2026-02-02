# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Helper Functions - Layer 0
#
# Pure functions for VM creation and composition.
# These functions have no implicit config access.
#
{ lib }:
{
  /*
    Creates the base structure for VM system parameters.

    This extracts the minimal set of host configuration values
    that VMs need, creating an explicit contract between host and VMs.

    # Arguments
    - config: The host NixOS configuration

    # Returns
    An attribute set with VM-relevant parameters
  */
  mkVmSystemParams = config: {
    # Build profiles
    profiles = {
      debug = {
        enable = config.ghaf.profiles.debug.enable or false;
      };
      release = {
        enable = config.ghaf.profiles.release.enable or false;
      };
    };

    # Development settings
    development = {
      ssh = {
        daemon = {
          enable = config.ghaf.development.ssh.daemon.enable or false;
        };
      };
      debug = {
        tools = {
          enable = config.ghaf.development.debug.tools.enable or false;
        };
      };
      nix-setup = {
        enable = config.ghaf.development.nix-setup.enable or false;
      };
    };

    # Platform information
    platform = {
      build = config.nixpkgs.buildPlatform.system;
      host = config.nixpkgs.hostPlatform.system;
    };

    # Virtualization settings
    virtualization = {
      storeOnDisk = config.ghaf.virtualization.microvm.storeOnDisk or false;
      storageEncryption = {
        enable = config.ghaf.virtualization.storagevm-encryption.enable or false;
      };
    };

    # Logging
    logging = {
      enable = config.ghaf.logging.enable or false;
    };

    # Time settings
    timeZone = config.time.timeZone or "UTC";
  };

  /*
    Creates shared microvm store configuration.

    # Arguments
    - storeOnDisk: Whether to use store on disk mode

    # Returns
    Microvm shares configuration for nix store
  */
  mkStoreShares =
    storeOnDisk:
    lib.optionals (!storeOnDisk) [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
    ];

  /*
    Creates common VM shares configuration.

    # Returns
    List of common virtiofs shares for VMs
  */
  mkCommonShares = [
    {
      tag = "ghaf-common";
      source = "/persist/common";
      mountPoint = "/etc/common";
      proto = "virtiofs";
    }
  ];

  /*
    Gets the QEMU machine type for a given platform.

    # Arguments
    - system: The target system (e.g., "x86_64-linux")

    # Returns
    The QEMU machine type string
  */
  getQemuMachine =
    system:
    {
      x86_64-linux = "q35";
      aarch64-linux = "virt";
    }
    .${system} or "q35";

  /*
    Gets the guest configuration from a microvm definition.

    This handles both the `config` and `evaluatedConfig` patterns,
    returning the NixOS configuration in either case.

    NOTE: As of the evaluatedConfig migration, ALL VMs now use evaluatedConfig.
    This function is kept for backward compatibility but can be simplified to:
      microvmDef.evaluatedConfig.config

    # Arguments
    - microvmDef: The microvm definition from config.microvm.vms.<name>

    # Returns
    The NixOS configuration of the guest VM
  */
  getGuestConfig =
    microvmDef:
    # All VMs now use evaluatedConfig, but keep fallback for safety
    if microvmDef.evaluatedConfig != null then
      microvmDef.evaluatedConfig.config
    else
      microvmDef.config.config;

  /*
    Extends a VM configuration with additional modules.

    This is a convenience wrapper around extendModules that makes
    it easier for downstream projects to customize VMs.

    # Arguments
    - vmConfig: A VM configuration created by mkAudioVm, mkNetVm, etc.
    - modules: List of additional NixOS modules to add

    # Returns
    Extended VM configuration

    # Example
    ```nix
    extendVmConfig audioVm [
      { ghaf.services.audio.customOption = true; }
    ]
    ```
  */
  extendVmConfig = vmConfig: modules: vmConfig.extendModules { inherit modules; };

  /*
    Creates host binding module for VM hardware passthrough.

    This creates a NixOS module that binds host-specific hardware
    configuration to a VM. Used when VMs need access to host hardware.

    # Arguments
    - devices: List of PCI devices to pass through
    - extraShares: Additional virtiofs shares to add
    - storeOnDisk: Whether store is on disk (disables ro-store share)

    # Returns
    A NixOS module with microvm device configuration
  */
  mkHostBindings =
    {
      devices ? [ ],
      extraShares ? [ ],
      storeOnDisk ? false,
    }:
    {
      microvm = {
        inherit devices;
        shares =
          (lib.optionals (!storeOnDisk) [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
          ])
          ++ extraShares;
        writableStoreOverlay = lib.mkIf (!storeOnDisk) "/nix/.rw-store";
      };
    };
}
