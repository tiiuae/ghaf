# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
let
  inherit (inputs.self) lib;
in
{
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
  ];

  perSystem =
    { self', system, ... }:
    {
      # customise pkgs
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system inputs;
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
            "jitsi-meet-1.0.8043"
          ];
        };
      };
      # make custom top-level lib available to all `perSystem` functions
      _module.args.lib = lib;

      # add the default overlay that will include our packages
      overlayAttrs = lib.flattenPkgs "/" [ ] self'.legacyPackages;
    };
}
