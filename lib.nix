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
  lib: _:
  # some utils for importing trees
  rec {
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
    platformPkgs =
      system:
      lib.filterAttrs (
        _: value:
        let
          platforms = lib.attrByPath [
            "meta"
            "platforms"
          ] [ ] value;
        in
        lib.elem system platforms
      );

    /*
        *
      Flattens a _tree_ of the shape that is produced by rakeLeaves.
      An attrset with names in the spirit of the Reverse DNS Notation form
      that fully preserve information about grouping from nesting.

      # Example

      ```
      flattenTree {
        a = {
          b = {
            c = <path>;
          };
        };
      }
      => { "a.b.c" = <path>; }
      ```
    */
    flattenTree =
      tree:
      let
        op =
          sum: path: val:
          let
            pathStr = builtins.concatStringsSep "." path; # dot-based reverse DNS notation
          in
          if builtins.isPath val then
            # builtins.trace "${toString val} is a path"
            (sum // { "${pathStr}" = val; })
          else if builtins.isAttrs val then
            # builtins.trace "${builtins.toJSON val} is an attrset"
            # recurse into that attribute set
            (recurse sum path val)
          else
            # ignore that value
            # builtins.trace "${toString path} is something else"
            sum;

        recurse =
          sum: path: val:
          builtins.foldl' (sum: key: op sum (path ++ [ key ]) val.${key}) sum (builtins.attrNames val);
      in
      recurse { } [ ] tree;

    /*
      *
      Recursively collect the nix files of _path_ into attrs.
      Return an attribute set where all `.nix` files and directories with `default.nix` in them
      are mapped to keys that are either the file with .nix stripped or the folder name.
      All other directories are recursed further into nested attribute sets with the same format.

      # Example

      Example file structure:

      ```
      ./core/default.nix
      ./base.nix
      ./main/dev.nix
      ./main/os/default.nix
      ```

      ```nix
      rakeLeaves .
      => {
        core = ./core;
        base = base.nix;
        main = {
          dev = ./main/dev.nix;
          os = ./main/os;
        };
      }
      ```
    */

    rakeLeaves =
      dirPath:
      let
        seive =
          file: type:
          # Only rake `.nix` files or directories
          (type == "regular" && lib.hasSuffix ".nix" file) || (type == "directory");

        collect = file: type: {
          name = lib.removeSuffix ".nix" file;
          value =
            let
              path = dirPath + "/${file}";
            in
            if (type == "regular") || (type == "directory" && builtins.pathExists (path + "/default.nix")) then
              path
            # recurse on directories that don't contain a `default.nix`
            else
              rakeLeaves path;
        };

        files = lib.filterAttrs seive (builtins.readDir dirPath);
      in
      lib.filterAttrs (_n: v: v != { }) (lib.mapAttrs' collect files);

    importLeaves =
      #
      # Create an import stanza by recursing a directory to find all default.nix and <file.nix>
      # files beneath withough manually having to list all the subsequent files.
      #
      path: builtins.attrValues (lib.mapAttrs (_: import) (rakeLeaves path));
  }
)
