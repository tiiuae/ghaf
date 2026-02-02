# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# MicroVM Flake Module
#
# Note: VM modules receive `self` and `inputs` via specialArgs (not currying).
# Target builders must pass both in specialArgs for modules to access self.lib.*
#
_: {
  imports = [
    # Export vmBase NixOS module
    ./vmConfigurations/flake-module.nix
  ];

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
      ./vm-extensions.nix
      # NOTE: modules.nix has been removed
      # Hardware passthrough and service modules are now included directly
      # in the sysvm modules (netvm.nix, guivm.nix, etc.) via hardwareModules
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

    # VM feature modules - read from sharedSystemConfig
    # Used by VM builders for consistent feature configuration
    vm-features.imports = [
      ./features
    ];
  };
}
