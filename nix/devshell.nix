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
              [
                pkgs.jq
                pkgs.mdbook
                pkgs.nix-eval-jobs
                pkgs.nix-fast-build
                pkgs.nix-output-monitor
                pkgs.nix-tree
                pkgs.nixVersions.latest
                pkgs.reuse
                config.treefmt.build.wrapper
                (pkgs.callPackage ../packages/flash { })
                (pkgs.callPackage ../packages/ghaf-build-helper {
                  inherit (pkgs) writeShellApplication nixos-rebuild ipcalc;
                })
              ]
              ++ lib.attrValues config.treefmt.build.programs # make all the trefmt packages available
              ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") pkgs.cachix;
          };
          commands = [
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
            {
              help = "Ghaf nixos-rebuild command";
              name = "ghaf-rebuild";
              command = "ghaf-build-helper $@";
              category = "builder";
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
