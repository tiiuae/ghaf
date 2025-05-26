# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# Copyright 2020-2023 Pacman99 and the Digga Contributors
#
# SPDX-License-Identifier: MIT
# FlattenTree and rakeLeaves originate from
# https://github.com/divnix/digga
{ inputs, ... }:
let
  inherit (inputs) nixpkgs;
in
nixpkgs.lib.extend (
  lib: _: {
    /*
         *
         Filters Nix packages based on the target system platform.
         Returns a filtered attribute set of Nix packages compatible with the target system.

      # Example

      ```
      lib.platformPkgs "x86_64-linux" {
         hello-compatible = pkgs.hello.overrideAttrs (old: { meta.platforms = ["x86_64-linux"]; });
         hello-inccompatible = pkgs.hello.overrideAttrs (old: { meta.platforms = ["aarch-linux"]; });
      }
      => { hello-compatible = «derivation /nix/store/g2mxdrkwr1hck4y5479dww7m56d1x81v-hello-2.12.1.drv»; }
      ```

      # Type

      ```
      filterAttrs :: String -> AttrSet -> AttrSet
      ```

      # Arguments

      - [system] Target system platform (e.g., "x86_64-linux").
      - [pkgsSet] a set of Nix packages.
    */
    # TODO should this be replaced with flake-parts pkgs-by-name
    platformPkgs =
      system:
      lib.filterAttrs (
        _: value:
        let
          platforms =
            lib.attrByPath
              [
                "meta"
                "platforms"
              ]
              [ ]
              value;
        in
        lib.elem system platforms
      );

    genPkgWithFlashScript =
      pkg: system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      pkgs.linkFarm "ghaf-image" [
        {
          name = "image";
          path = pkg;
        }
        {
          name = "flash-script";
          path = pkgs.callPackage ./packages/pkgs-by-name/flash-script/package.nix { };
        }
      ];
  }
)
