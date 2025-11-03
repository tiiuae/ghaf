# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [ ];
  perSystem =
    {
      pkgs,
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
              nodejs
              nix
              nixci
              nixos-rebuild
              nix-output-monitor
              nix-tree
              reuse
              statix
              nix-fast-build
              ;
          }
          ++ lib.optional (pkgs.stdenv.hostPlatform.system != "riscv64-linux") pkgs.cachix;
      };
    };
}
