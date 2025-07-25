# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ inputs, ... }:
{
  flake.nixosModules = {
    reference-appvms.imports = [ ./appvms ];
    reference-desktop.imports = [ ./desktop ];
    reference-host-demo-apps.imports = [ ./host-demo-apps ];
    reference-personalize.imports = [ ./personalize ];
    reference-programs.imports = [ ./programs ];
    reference-services.imports = [ ./services ];
    reference-profiles.imports = [
      inputs.self.nixosModules.reference-appvms
      inputs.self.nixosModules.reference-programs
      inputs.self.nixosModules.reference-services
      inputs.self.nixosModules.reference-personalize
      inputs.self.nixosModules.reference-desktop
      ./profiles/mvp-user-trial.nix
      ./profiles/mvp-user-trial-extras.nix
    ];
    reference-profiles-orin.imports = [
      inputs.self.nixosModules.reference-appvms
      inputs.self.nixosModules.reference-programs
      inputs.self.nixosModules.reference-services
      inputs.self.nixosModules.reference-personalize
      inputs.self.nixosModules.reference-desktop
      ./profiles/mvp-orinuser-trial.nix
      ./profiles/mvp-orinuser-trial-extras.nix
    ];
  };
}
