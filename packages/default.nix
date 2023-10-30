# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    inherit (lib.flakes) platformPkgs;
    inherit (pkgs) callPackage;
  in {
    packages = platformPkgs system {
      gala-app = callPackage ./gala {};
      kernel-hardening-checker = callPackage ./kernel-hardening-checker {};
      windows-launcher = callPackage ./windows-launcher {enableSpice = false;};
      windows-launcher-spice = callPackage ./windows-launcher {enableSpice = true;};
      doc = callPackage ../docs {
        revision = lib.ghaf-version;
        options = let
          cfg = lib.nixosSystem {
            inherit system;
            modules = import ../modules/module-list.nix;
          };
        in
          cfg.options;
      };
    };
  };
}
