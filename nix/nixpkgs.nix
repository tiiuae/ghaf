# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  perSystem =
    {
      system,
      lib,
      ...
    }:
    {
      # customise pkgs
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system inputs;
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
            "jitsi-meet-1.0.8043"
            "qtwebengine-5.15.19"
          ];
        };

      };
      # make custom top-level lib available to all `perSystem` functions
      _module.args.lib = lib;
    };
}
