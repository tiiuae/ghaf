# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  nixpkgs,
  flake-utils,
}: let
  systems = with flake-utils.lib.system; [
    x86_64-linux
    aarch64-linux
  ];
in
  flake-utils.lib.eachSystem systems (system: {
    packages = let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      gala-app = pkgs.callPackage ./gala {};
      windows-launcher = pkgs.callPackage ./windows-launcher {};
    };
  })
