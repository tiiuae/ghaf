# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ inputs, ... }:
let
  # The personalize module was folded into the org layer; keep a guided
  # error for downstreams that still set its toggle.
  personalizeRemoval =
    inputs.nixpkgs.lib.mkRemovedOptionModule
      [
        "ghaf"
        "reference"
        "personalize"
        "keys"
        "enable"
      ]
      "The dev-key roster is org data: enable ghaf.reference.org.tii or set ghaf.org.identity.ssh.debugKeys.";
in
{
  _file = ./flake-module.nix;

  flake.nixosModules = {
    reference-appvms.imports = [ ./appvms ];
    reference-desktop.imports = [ ./desktop ];
    reference-host-demo-apps.imports = [ ./host-demo-apps ];
    reference-org-tii.imports = [ ./org/tii.nix ];
    reference-programs.imports = [ ./programs ];
    reference-services.imports = [ ./services ];
    reference-passthrough.imports = [ ./passthrough ];
    reference-profiles.imports = [
      inputs.self.nixosModules.reference-appvms
      inputs.self.nixosModules.reference-programs
      inputs.self.nixosModules.reference-services
      inputs.self.nixosModules.reference-desktop
      inputs.self.nixosModules.reference-passthrough
      inputs.self.nixosModules.reference-org-tii
      ./profiles/mvp-user-trial.nix
      ./profiles/mvp-user-trial-extras.nix
      personalizeRemoval
    ];
    reference-profiles-orin.imports = [
      inputs.self.nixosModules.reference-appvms
      inputs.self.nixosModules.reference-programs
      inputs.self.nixosModules.reference-services
      inputs.self.nixosModules.reference-desktop
      inputs.self.nixosModules.reference-passthrough
      inputs.self.nixosModules.reference-org-tii
      ./profiles/mvp-orinuser-trial.nix
      ./profiles/mvp-orinuser-trial-extras.nix
      personalizeRemoval
    ];
  };
}
