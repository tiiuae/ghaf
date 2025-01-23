# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, lib, ... }:
{
  imports = [
    inputs.devshell.flakeModule
    ./devshell/kernel.nix
  ];
  perSystem =
    {
      config,
      pkgs,
      inputs',
      system,
      ...
    }:
    {
      devshells = {
        # the main developer environment
        default = {
          devshell = {
            name = "Ghaf devshell";
            meta.description = "Ghaf development environment";
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
              ++ [
                inputs'.nix-fast-build.packages.default
                config.treefmt.build.wrapper
              ]
              ++ [
                (pkgs.callPackage ../packages/flash { })
                (pkgs.callPackage ../packages/make-checks { })
              ]
              ++ lib.attrValues config.treefmt.build.programs # make all the trefmt packages available
              ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") pkgs.cachix;
          };
          commands = [
            {
              help = "Check flake evaluation";
              name = "check-eval";
              command = "make-checks";
              category = "checker";
            }
            {
              help = "Format";
              name = "format-repo";
              command = "treefmt";
              category = "checker";
            }
            {
              help = "Check license";
              name = "check-license";
              command = "reuse lint";
              category = "linters";
            }
          ];
        };

        smoke-test = {
          devshell = {
            name = "Ghaf smoke test";
            meta.description = "Ghaf smoke test environment";
            packagesFrom = [ inputs.ci-test-automation.devShell.${system} ];
          };

          commands = [
            # TODO: Add smoke test commands
            # something like this
            {
              help = "Run smoke tests";
              name = "smoke-test-agx";
              command = "ci-test-automation smoke-test-agx";
              category = "test";
            }
          ];
        };
      };
    };
}
