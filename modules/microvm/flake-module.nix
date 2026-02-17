# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# MicroVM Module Definitions
#
# Note: Modules receive `inputs` via specialArgs from mkLaptopConfiguration.
# This eliminates the need for the `{ inputs }:` wrapper anti-pattern.
_: {
  _file = ./flake-module.nix;

  flake.nixosModules = {
    microvm.imports = [
      ./host/microvm-host.nix
      ./sysvms/netvm.nix
      ./sysvms/adminvm.nix
      ./appvm.nix
      ./sysvms/guivm.nix
      ./sysvms/audiovm.nix
      ./sysvms/idsvm/idsvm.nix
      ./common/microvm-store-mode.nix
      ./vm-config.nix
    ];

    mem-manager.imports = [
      ./host/mem-manager.nix
    ];

    vm-modules.imports = [
      ./common/microvm-store-mode.nix
      ./common/shared-directory.nix
      ./common/storagevm.nix
      ./common/vm-networking.nix
      ./common/vm-tpm.nix
      ./common/waypipe.nix
      ./common/xdghandlers.nix
      ./common/xdgitems.nix
    ];

    # GUI VM base module for layered composition
    # Use with extendModules pattern:
    #   lib.nixosSystem { modules = [ inputs.self.nixosModules.guivm-base ]; ... }
    #     .extendModules { modules = [ ../services ]; }
    guivm-base = ./sysvms/guivm-base.nix;

    # Admin VM base module for layered composition
    # Use with extendModules pattern:
    #   lib.nixosSystem { modules = [ inputs.self.nixosModules.adminvm-base ]; ... }
    #     .extendModules { modules = [ ... ]; }
    adminvm-base = ./sysvms/adminvm-base.nix;

    # Admin VM feature modules (vTPM services, etc.)
    # Auto-includes based on hostConfig conditions
    adminvm-features = ./adminvm-features;

    # IDS VM base module for layered composition
    # Use with extendModules pattern:
    #   lib.nixosSystem { modules = [ inputs.self.nixosModules.idsvm-base ]; ... }
    #     .extendModules { modules = [ ... ]; }
    idsvm-base = ./sysvms/idsvm/idsvm-base.nix;

    # Audio VM base module for layered composition
    # Use with extendModules pattern:
    #   lib.nixosSystem { modules = [ inputs.self.nixosModules.audiovm-base ]; ... }
    #     .extendModules { modules = [ ... ]; }
    audiovm-base = ./sysvms/audiovm-base.nix;

    # GUI VM feature modules (GPU/input/kernel/QEMU hardware passthrough)
    guivm-features = ./guivm-features;

    # Audio VM feature modules (bluetooth, xpadneo, hardware passthrough)
    audiovm-features = ./audiovm-features;

    # Net VM feature modules (nics hardware passthrough)
    netvm-features = ./netvm-features;

    # Net VM base module for layered composition
    # Use with extendModules pattern:
    #   lib.nixosSystem { modules = [ inputs.self.nixosModules.netvm-base ]; ... }
    #     .extendModules { modules = [ ... ]; }
    # Note: Jetson and other non-laptop platforms continue to use netvm.extraModules
    netvm-base = ./sysvms/netvm-base.nix;

    # App VM base module for layered composition
    # Unlike singleton VMs, App VMs are instantiated multiple times using mkAppVm.
    # Use with extendModules pattern:
    #   mkAppVm = vmDef: lib.nixosSystem {
    #     modules = [ inputs.self.nixosModules.appvm-base ];
    #     specialArgs = { hostConfig.appvm = vmDef; ... };
    #   }
    appvm-base = ./sysvms/appvm-base.nix;
  };

  # ═══════════════════════════════════════════════════════════════════════════
  # VM BASES - Composable Base Modules for Ghaf Virtual Machines
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # These modules provide the foundation for building Ghaf VMs using the
  # composition model. Each base includes:
  #   - Core VM configuration (microvm settings, networking)
  #   - Integration with globalConfig/hostConfig via specialArgs
  #   - Default services appropriate for the VM type
  #
  # USAGE PATTERN:
  #
  #   # 1. Create the base configuration
  #   guivmBase = lib.nixosSystem {
  #     inherit system;
  #     modules = [ inputs.ghaf.vmBases.guivm ];
  #     specialArgs = lib.ghaf.vm.mkSpecialArgs {
  #       inherit inputs;
  #       globalConfig = myGlobalConfig;
  #       hostConfig = { inherit (hostConfig) networking hardware; };
  #     };
  #   };
  #
  #   # 2. Extend with additional modules
  #   guivmExtended = guivmBase.extendModules {
  #     modules = [ ./my-custom-services.nix ];
  #   };
  #
  #   # 3. Use in microvm.vms
  #   microvm.vms.gui-vm = {
  #     evaluatedConfig = guivmExtended;
  #   };
  #
  # For downstream projects, import ghaf as a flake input and access:
  #   inputs.ghaf.vmBases.guivm
  #   inputs.ghaf.lib.ghaf.vm.mkSpecialArgs
  #
  # ═══════════════════════════════════════════════════════════════════════════
  flake.vmBases = {
    # GUI VM - Desktop environment and display management
    # Requires: GPU passthrough, display hardware
    guivm = ./sysvms/guivm-base.nix;

    # Network VM - External network connectivity and routing
    # Requires: Network device passthrough
    netvm = ./sysvms/netvm-base.nix;

    # Audio VM - Sound services and Bluetooth
    # Requires: Audio device passthrough (optional)
    audiovm = ./sysvms/audiovm-base.nix;

    # Admin VM - System administration and updates
    # Requires: Storage access for updates
    adminvm = ./sysvms/adminvm-base.nix;

    # IDS VM - Intrusion Detection System
    # Requires: Network tap access
    idsvm = ./sysvms/idsvm/idsvm-base.nix;

    # App VM - Template for application VMs
    # Instantiated multiple times (chrome-vm, comms-vm, etc.)
    # Use with mkAppVm pattern in profiles
    appvm = ./sysvms/appvm-base.nix;
  };
}
