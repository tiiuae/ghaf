# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Reference Profiles
#
{ inputs, ... }:
{
  flake.nixosModules = {
    # Top level profiles
    reference-profile-mvp-user-trials.imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.profiles-laptop
      ./mvp-user-trial.nix
    ];
    reference-profile-mvp-user-trials-extras.imports = [
      inputs.self.nixosModules.reference-profile-mvp-user-trials
      ./mvp-user-trial-extras.nix
    ];
  };
}
