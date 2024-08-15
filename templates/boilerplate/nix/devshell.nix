# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [ ];
  perSystem =
    {
      pkgs,
      inputs',
      lib,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        name = "Ghaf derived devshell";
        packages =
          builtins.attrValues {
            inherit (pkgs)
              alejandra
              git
              mdbook
              nix
              nixci
              nixos-rebuild
              nix-output-monitor
              nix-tree
              reuse
              statix
              ;
          }
          ++ [ inputs'.nix-fast-build.packages.default ]
          ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") pkgs.cachix;
      };
    };
}
