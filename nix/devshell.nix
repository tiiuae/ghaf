# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [ ./devshell/kernel.nix ];
  perSystem =
    {
      config,
      pkgs,
      inputs',
      lib,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        name = "Ghaf devshell";
        meta.description = "Ghaf development environment";
        #TODO look at adding Mission control etc here
        inputsFrom = [
          config.treefmt.build.programs # See ./treefmt.nix
        ];
        packages =
          builtins.attrValues {
            inherit (pkgs)
              git
              mdbook
              nix
              nixci
              nixos-rebuild
              nix-output-monitor
              nix-tree
              reuse
              nix-eval-jobs
              jq
              ;
          }
          ++ [ inputs'.nix-fast-build.packages.default ]
          ++ [
            (pkgs.callPackage ../packages/flash { })
            (pkgs.callPackage ../packages/make-checks { })
          ]
          ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") pkgs.cachix;

        # TODO Add pre-commit.devShell (needs to exclude RiscV)
        # https://flake.parts/options/pre-commit-hooks-nix
      };
    };
}
