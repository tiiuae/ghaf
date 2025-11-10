# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    {
      config,
      pkgs,
      self',
      lib,
      ...
    }:
    {
      checks = {
        pre-commit-check = config.pre-commit.devShell;
      }
      // (lib.mapAttrs' (n: lib.nameValuePair "package-${n}") self'.packages);

      pre-commit = {
        settings = {
          hooks = {
            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
            };
            reuse = {
              enable = true;
              package = pkgs.reuse;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
            };
            end-of-file-fixer = {
              enable = true;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
            };
            trim-trailing-whitespace = {
              enable = true;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
            };
          };
        };
      };
    };
}
