# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ inputs, ... }:
{
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
    ];

    # speciic profiles that are needed for certain classes of devices should be included below.
    # This can be on a category basis or integrated into an existing category if it has a common base
    profiles-laptop.imports = [
      ./laptop-x86.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop
    ];
  };
}
