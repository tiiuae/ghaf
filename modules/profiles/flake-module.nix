# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ inputs, ... }:
{
  _file = ./flake-module.nix;

  flake.nixosModules = {
    # The top-level profile should import all the common modules that can be shared across all targets
    # Only entries that can be included in those targets without causing conflicts should be included here
    profiles.imports = [
      inputs.self.nixosModules.common
      inputs.self.nixosModules.desktop
      inputs.self.nixosModules.development
      ./graphics.nix
      ./debug.nix
      ./release.nix
      ./minimal.nix
      ./host-hardening.nix
      # NOTE: kernel-hardening is NOT included here because it requires specific kernel
      # hardening options that don't exist in all configurations. Import it explicitly
      # in targets that support it.
    ];

    # speciic profiles that are needed for certain classes of devices should be included below.
    # This can be on a category basis or integrated into an existing category if it has a common base
    profiles-workstation.imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.microvm
      ./laptop-x86.nix
    ];

    profiles-orin.imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.microvm
      ./orin.nix
    ];

    profiles-thor.imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.microvm
      ./thor.nix
    ];

    # Profile for VM targets that run GUI on host (no gui-vm)
    profiles-vm.imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.microvm
      ./vm.nix
    ];
  };
}
