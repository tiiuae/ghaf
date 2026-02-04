# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# MicroVM Module Definitions
#
# Note: Modules receive `inputs` via specialArgs from mkLaptopConfiguration.
# This eliminates the need for the `{ inputs }:` wrapper anti-pattern.
_: {
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
      ./modules.nix
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

    # Audio VM feature modules (bluetooth, xpadneo, hardware passthrough)
    # Currently not used - hardware passthrough handled via hardware.definition.audiovm.extraModules
    # TODO: Revisit in future phase with proper hostConfig structure
    # audiovm-features = ./audiovm-features;
  };
}
