# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
{
  flake.checks =
    let
      pkgsPerSystem = system: self.inputs.nixpkgs.legacyPackages.${system};
    in
    {
      x86_64-linux =
        let
          pkgs = pkgsPerSystem "x86_64-linux";
        in
        {
          installer = pkgs.callPackage ./installer { inherit self; };
          # Fails after https://github.com/tiiuae/ghaf/commit/e45a8fc47dc82e37a0327bd794478277c5c7a043
          # firewall = pkgs.callPackage ./firewall { inherit self; };
          logging-fss = pkgs.callPackage ./logging { inherit self; };
          fss-test = pkgs.callPackage ./logging/test_scripts/fss-test.nix { };
        };
    };
}
